//
//  WMRenderer.m
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

#import "WMTypes.h"
#import "WMUtilities.h"
#import "WMMatrixUtilities.h"
#import "WMCamera.h"
#import "WMMeshModel.h"

#import "WMRenderer.h"

// The max number of command buffers in flight
static const NSUInteger kMaxInflightBuffers = 3;

@interface WMRenderer()

@property (nonatomic, weak) MTKView *view;

@end

@implementation WMRenderer
{
  dispatch_semaphore_t _inflight_semaphore;
  id <MTLBuffer>       _dynamicConstantBuffer;
  
  // Uniforms
  id <MTLBuffer>       _sharedUniformBuffer;
  id <MTLBuffer>       _meshModelUniformBuffer;
  uint8_t              _constantDataBufferIndex;
  
  id <MTLDevice>              _device;
  id <MTLCommandQueue>        _commandQueue;
  id <MTLDepthStencilState>   _depthStencilState;
  id <MTLRenderPipelineState> _texturePipelineState;
  
  id <MTLTexture> _meshModelTexture;
  
  // Matrices
  matrix_float4x4 _projectionMatrix;
  matrix_float4x4 _viewMatrix;
  
  CGSize          _cameraReferenceFrameDimensions;
  float           _cameraFocalLength;
  
  WMCamera*         _camera;
  
  WMMeshModel*      _meshModel;
  float             _meshModelOrientationRadAngle;
  
  dispatch_queue_t  _rendererQueue;
}

@synthesize focalMagnificationFactor = _focalMagnificationFactor;

#pragma mark Public Methods

- (nullable instancetype)initWithView:(nonnull MTKView *)view
{
  if ((self = [super init]))
    {
    _cameraReferenceFrameDimensions = CGSizeMake(4032, 3024);
    _cameraFocalLength = 6600.0f; // Initialize with a reasonable value (units: pixels)
    _focalMagnificationFactor = 0.90f; // Avoid cropping the image in case the calibration data is off
    
    _rendererQueue = dispatch_queue_create("com.WiggleMe.RendererQueue", NULL);
    
    _constantDataBufferIndex = 0;
    _inflight_semaphore = dispatch_semaphore_create(kMaxInflightBuffers);
    
    [self _setupMetal];
    if (! _device) {
      @throw [NSException exceptionWithName:@"Cannot create WMRenderer."
                                     reason:@"Metal is not supported on this device."
                                   userInfo:nil];
    }
    
    dispatch_sync(_rendererQueue, ^{
      [self _setupView:view withDevice:_device];
      [self _setupUniformBuffers];
      
      [self _loadMeshes];
      [self _setupPipeline];
      [self _setupCamera];
      
      [self reshape];
    });
    }
  return self;
}

- (void)reshape
{
  const float fov = [WMUtilities fieldOfViewFromViewport:self.view.bounds.size
                                        depthOrientation:_meshModelOrientationRadAngle
                                             focalLength:_cameraFocalLength
                                referenceFrameDimensions:_cameraReferenceFrameDimensions
                                     magnificationFactor:_focalMagnificationFactor];
  
  const float aspect = self.view.bounds.size.width / self.view.bounds.size.height;
  _projectionMatrix = matrix_from_perspective(fov, aspect, 0.1f, 1000.0f);
}

- (void)update
{
  [self updateUniforms];
}

- (void)render
{
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
  
  dispatch_sync(_rendererQueue, ^{
    [self update];
    
    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"WiggleMe.Command";
    
    // Call the view's completion handler which is required by the view since it will signal its semaphore and set up the next buffer
    __block dispatch_semaphore_t block_sema = _inflight_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
      dispatch_semaphore_signal(block_sema);
    }];
    
    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor* renderPassDescriptor = _view.currentRenderPassDescriptor;
    
    if (renderPassDescriptor != nil) // If we have a valid drawable, begin the commands to render into it
      {
      // Create a render command encoder so we can render into something
      id <MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
      commandEncoder.label = @"WiggleMe.CommandEncoder";
      [commandEncoder setDepthStencilState:_depthStencilState];
      [commandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
      [commandEncoder setCullMode:MTLCullModeBack];
      
      [self drawMeshModelWithCommandEncoder:commandEncoder];
      
      // We're done encoding commands
      [commandEncoder endEncoding];
      
      // Schedule a present once the framebuffer is complete using the current drawable
      [commandBuffer presentDrawable:_view.currentDrawable];
      }
    
    // The render assumes it can now increment the buffer index and that the previous index won't be touched until we cycle back around to the same index
    _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kMaxInflightBuffers;
    
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
  });
}

- (void)setDepthMap:(nonnull CVPixelBufferRef)depthMap
    intrinsicMatrix:(matrix_float3x3)intrinsicMatrix
intrinsicMatrixReferenceDimensions:(CGSize)intrinsicMatrixReferenceDimensions;
{
  dispatch_sync(_rendererQueue, ^{
    _cameraFocalLength = intrinsicMatrix.columns[0].x;
    _cameraReferenceFrameDimensions = intrinsicMatrixReferenceDimensions;
    
    [_meshModel setDepthMap:depthMap
            intrinsicMatrix:intrinsicMatrix
intrinsicMatrixReferenceDimensions:intrinsicMatrixReferenceDimensions];
    
    [self reshape];
  });
}

- (void)setDepthMapOrientation:(float)angleRad
{
  dispatch_sync(_rendererQueue, ^{
    _meshModelOrientationRadAngle = angleRad;
  });
}

- (void)setTextureOrientation:(float)angleRad
{
  dispatch_sync(_rendererQueue, ^{
    [_meshModel setTextureOrientation:angleRad];
  });
}

- (void)setTexture:(nonnull UIImage*)image
{
  MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];
  id<MTLTexture> texture = [textureLoader newTextureWithCGImage:[image CGImage] options:nil error:nil];
  dispatch_sync(_rendererQueue, ^{
    _meshModelTexture = texture;
    _meshModelTexture.label = @"MeshModel Texture";
  });
}

- (void)setCamera:(nonnull WMCamera*)camera
{
  _camera = camera;
}

- (nonnull WMCamera*)copyCamera
{
  return [_camera copy];
}

-(void)setFocalMagnificationFactor:(float)focalMagnificationFactor
{
  _focalMagnificationFactor = focalMagnificationFactor;
  [self reshape];
}

#pragma mark Setup
- (void)_setupMetal
{
  // Set the view to use the default device
  _device = MTLCreateSystemDefaultDevice();
  
  // Create a new command queue
  _commandQueue = [_device newCommandQueue];
}

- (void)_setupView:(nonnull MTKView *)view withDevice:(nonnull id <MTLDevice>)device
{
  _view = view;
  _view.delegate = self;
  _view.device = device;
  _view.preferredFramesPerSecond = 60;
  
  _view.sampleCount = 4;
  _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
}

- (void)_setupUniformBuffers
{
  _sharedUniformBuffer = [_device newBufferWithLength:sizeof(WMSharedUniforms) * kMaxInflightBuffers
                                              options:MTLResourceCPUCacheModeDefaultCache];
  _sharedUniformBuffer.label = @"Shared Uniforms";
  
  _meshModelUniformBuffer = [_device newBufferWithLength:sizeof(WMPerInstanceUniforms) * 1 * kMaxInflightBuffers
                                                 options:MTLResourceCPUCacheModeDefaultCache];
  _meshModelUniformBuffer.label = @"MeshModel Uniforms";
}

- (void)_setupPipeline
{
  id<MTLLibrary> library = [_device newDefaultLibrary];
  
  [self _setupTexturePipelineWithLibrary:library];
  
  MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
  depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
  depthStateDesc.depthWriteEnabled = YES;
  _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];
}

- (void)_setupTexturePipelineWithLibrary:(nonnull id<MTLLibrary>)library
{
  // Create the vertex descriptor
  MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];
  vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
  vertexDescriptor.attributes[0].offset = 0;
  vertexDescriptor.attributes[0].bufferIndex = 0;
  vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
  vertexDescriptor.attributes[1].offset = offsetof(WMTextureVertex, tx);
  vertexDescriptor.attributes[1].bufferIndex = 0;
  vertexDescriptor.layouts[0].stride = sizeof(WMTextureVertex);
  vertexDescriptor.layouts[0].stepRate = 1;
  vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
  
  // Create a reusable pipeline state
  MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
  pipelineStateDescriptor.label = @"TexturePipeline";
  pipelineStateDescriptor.sampleCount = _view.sampleCount;
  pipelineStateDescriptor.vertexFunction = [library newFunctionWithName:@"texture_vertex_shader"];
  pipelineStateDescriptor.fragmentFunction = [library newFunctionWithName:@"texture_fragment_shader"];
  pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
  pipelineStateDescriptor.colorAttachments[0].pixelFormat = _view.colorPixelFormat;
  pipelineStateDescriptor.depthAttachmentPixelFormat = _view.depthStencilPixelFormat;
  pipelineStateDescriptor.stencilAttachmentPixelFormat = _view.depthStencilPixelFormat;
  
  NSError *error = NULL;
  _texturePipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
  if ( ! _texturePipelineState) {
    NSLog(@"Failed to created pipeline state, error %@", error);
  }
}

- (void)_setupCamera
{
  _camera = [[WMCamera alloc] initCameraWithPosition:(vector_float3){0.0f, 0.0f, 0.0f}
                                         andRotation:(vector_float3){0.0f, 0.0f, 0.0f}];
  
  _viewMatrix = [_camera lookAt];
}

- (void)_loadMeshes
{
  // MeshModel
  _meshModelOrientationRadAngle = 0.0f;
  _meshModel = [[WMMeshModel alloc] initWithColumns:768 rows:576
                                        modelMatrix:matrix_identity_float4x4
                                             device:_device];
}

#pragma mark Drawing

- (void)drawMeshModelWithCommandEncoder:(nonnull id<MTLRenderCommandEncoder>)commandEncoder
{
  // Set context state
  [commandEncoder pushDebugGroup:@"DrawMeshModel"];
  {
  [commandEncoder setRenderPipelineState:_texturePipelineState];
  [commandEncoder setVertexBuffer:_meshModel.vertexBuffer offset:0 atIndex:0];
  [commandEncoder setVertexBuffer:_sharedUniformBuffer offset:sizeof(WMSharedUniforms) * _constantDataBufferIndex atIndex:1];
  [commandEncoder setVertexBuffer:_meshModelUniformBuffer offset:sizeof(WMPerInstanceUniforms) * _constantDataBufferIndex atIndex:2];
  [commandEncoder setFragmentTexture:_meshModelTexture atIndex:0];
  
  //        [commandEncoder setTriangleFillMode:MTLTriangleFillModeLines];
  
  [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
                             indexCount:_meshModel.indexBuffer.length / sizeof(uint32_t)
                              indexType:MTLIndexTypeUInt32
                            indexBuffer:_meshModel.indexBuffer
                      indexBufferOffset:0];
  }
  [commandEncoder popDebugGroup];
}


#pragma mark Updates
- (void)_updateCamera
{
  _viewMatrix = [_camera lookAt];
}

- (void)_updateSharedUniforms
{
  WMSharedUniforms *uniforms = &((WMSharedUniforms *)[_sharedUniformBuffer contents])[_constantDataBufferIndex];
  uniforms->projectionMatrix = _projectionMatrix;
  uniforms->viewMatrix = _viewMatrix;
}

- (void)_updateMeshModelUniforms
{
  const matrix_float4x4 modelMatrix = matrix_from_rotation(_meshModelOrientationRadAngle, 0.0f, 0.0f, 1.0f);
  
  WMPerInstanceUniforms *uniforms = &((WMPerInstanceUniforms *)[_meshModelUniformBuffer contents])[_constantDataBufferIndex];
  uniforms->modelMatrix = modelMatrix;
}

- (void)updateUniforms
{
  [self _updateCamera];
  [self _updateSharedUniforms];
  [self _updateMeshModelUniforms];
}


#pragma mark MTKView Delegate

// Called whenever view changes orientation or layout is changed
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
  [self reshape];
}

// Called whenever the view needs to render
- (void)drawInMTKView:(nonnull MTKView *)view
{
  @autoreleasepool {
    [self render];
  }
}

@end
