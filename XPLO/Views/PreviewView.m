//
//  PreviewView.m
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/3/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

#import "WMTypes.h"
#import "WMUtilities.h"
#import "WMMatrixUtilities.h"
#import "WMCamera.h"
#import "WMMeshModel.h"
#import "PreviewView.h"

// The max number of command buffers in flight
static const NSUInteger kMaxInflightBuffers = 3;

@implementation PreviewView
{
  dispatch_semaphore_t _inflight_semaphore;
  id <MTLBuffer>       _dynamicConstantBuffer;
  
  // Uniforms
  id <MTLBuffer>       _sharedUniformBuffer;
  id <MTLBuffer>       _meshModelUniformBuffer;
  uint8_t              _constantDataBufferIndex;
  
  id <MTLCommandQueue>        _commandQueue;
  id <MTLDepthStencilState>   _depthStencilState;
  id <MTLRenderPipelineState> _texturePipelineState;
  
  id <MTLTexture> _meshModelTexture;
  
  // Matrices
  matrix_float4x4 _projectionMatrix;
  matrix_float4x4 _viewMatrix;
  
  CGSize          _cameraReferenceFrameDimensions;
  float           _cameraFocalLength;
  
  WMMeshModel*      _meshModel;
  float             _meshModelOrientationRadAngle;
  
  dispatch_queue_t  _rendererQueue;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (self) {
    _cameraReferenceFrameDimensions = CGSizeMake(4032, 3024);
    _cameraFocalLength = 6600.0f; // Initialize with a reasonable value (units: pixels)
    _focalMagnificationFactor = 0.90f; // Avoid cropping the image in case the calibration data is off
    
    _rendererQueue = dispatch_queue_create("com.WiggleMe.RendererQueue", NULL);
    
    _constantDataBufferIndex = 0;
    _inflight_semaphore = dispatch_semaphore_create(kMaxInflightBuffers);
    
    [self setupMetal];
    if (! self.device) {
      @throw [NSException exceptionWithName:@"Cannot create WMRenderer."
                                     reason:@"Metal is not supported on this device."
                                   userInfo:nil];
    }
    
    dispatch_sync(_rendererQueue, ^{
      [self setupView];
      [self setupUniformBuffers];
      [self loadMeshes];
      [self setupPipeline];
      [self setupCamera];
      [self reshape];
    });
  }
  return self;
}

#pragma mark - Setup

- (void)setupMetal
{
  // Set the view to use the default device
  self.device = MTLCreateSystemDefaultDevice();
  
  // Create a new command queue
  _commandQueue = [self.device newCommandQueue];
}

- (void)setupView
{
  self.preferredFramesPerSecond = 60;
  
  self.sampleCount = 4;
  self.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
}

- (void)setupUniformBuffers
{
  _sharedUniformBuffer = [self.device newBufferWithLength:sizeof(WMSharedUniforms) * kMaxInflightBuffers
                                                  options:MTLResourceCPUCacheModeDefaultCache];
  _sharedUniformBuffer.label = @"Shared Uniforms";
  
  _meshModelUniformBuffer = [self.device newBufferWithLength:sizeof(WMPerInstanceUniforms) * 1 * kMaxInflightBuffers
                                                     options:MTLResourceCPUCacheModeDefaultCache];
  _meshModelUniformBuffer.label = @"MeshModel Uniforms";
}

- (void)loadMeshes
{
  // MeshModel
  _meshModelOrientationRadAngle = 0.0f;
  _meshModel = [[WMMeshModel alloc] initWithColumns:768 rows:576
                                        modelMatrix:matrix_identity_float4x4
                                             device:self.device];
}

- (void)setupPipeline
{
  id<MTLLibrary> library = [self.device newDefaultLibrary];
  
  [self setupTexturePipelineWithLibrary:library];
  
  MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
  depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
  depthStateDesc.depthWriteEnabled = YES;
  _depthStencilState = [self.device newDepthStencilStateWithDescriptor:depthStateDesc];
}

- (void)setupTexturePipelineWithLibrary:(nonnull id<MTLLibrary>)library
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
  pipelineStateDescriptor.sampleCount = self.sampleCount;
  pipelineStateDescriptor.vertexFunction = [library newFunctionWithName:@"texture_vertex_shader"];
  pipelineStateDescriptor.fragmentFunction = [library newFunctionWithName:@"texture_fragment_shader"];
  pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
  pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
  pipelineStateDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat;
  pipelineStateDescriptor.stencilAttachmentPixelFormat = self.depthStencilPixelFormat;
  
  NSError *error = NULL;
  _texturePipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
  if ( ! _texturePipelineState) {
    NSLog(@"Failed to created pipeline state, error %@", error);
  }
}

- (void)setupCamera
{
  _camera = [[WMCamera alloc] initCameraWithPosition:(vector_float3){0.0f, 0.0f, 0.0f}
                                         andRotation:(vector_float3){0.0f, 0.0f, 0.0f}];
  
  _viewMatrix = [_camera lookAt];
}

#pragma mark - Updates

- (void)updateCamera
{
  _viewMatrix = [_camera lookAt];
}

- (void)updateSharedUniforms
{
  WMSharedUniforms *uniforms = &((WMSharedUniforms *)[_sharedUniformBuffer contents])[_constantDataBufferIndex];
  uniforms->projectionMatrix = _projectionMatrix;
  uniforms->viewMatrix = _viewMatrix;
}

- (void)updateMeshModelUniforms
{
  const matrix_float4x4 modelMatrix = matrix_from_rotation(_meshModelOrientationRadAngle, 0.0f, 0.0f, 1.0f);
  
  WMPerInstanceUniforms *uniforms = &((WMPerInstanceUniforms *)[_meshModelUniformBuffer contents])[_constantDataBufferIndex];
  uniforms->modelMatrix = modelMatrix;
}

- (void)update
{
  [self updateCamera];
  [self updateSharedUniforms];
  [self updateMeshModelUniforms];
}

#pragma mark - Drawing

- (void)reshape
{
  const float fov = [WMUtilities fieldOfViewFromViewport:self.bounds.size
                                        depthOrientation:_meshModelOrientationRadAngle
                                             focalLength:_cameraFocalLength
                                referenceFrameDimensions:_cameraReferenceFrameDimensions
                                     magnificationFactor:_focalMagnificationFactor];
  
  const float aspect = self.bounds.size.width / self.bounds.size.height;
  _projectionMatrix = matrix_from_perspective(fov, aspect, 0.1f, 1000.0f);
}

-(void)drawRect:(CGRect)rect
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
    MTLRenderPassDescriptor* renderPassDescriptor = self.currentRenderPassDescriptor;
    
    if (renderPassDescriptor != nil) // If we have a valid drawable, begin the commands to render into it
      {
      // Create a render command encoder so we can render into something
      id <MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
      commandEncoder.label = @"WiggleMe.CommandEncoder";
      [commandEncoder setDepthStencilState:_depthStencilState];
      [commandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
      [commandEncoder setCullMode:MTLCullModeBack];
      
      // Set context state
      [commandEncoder pushDebugGroup:@"DrawMeshModel"];
      [commandEncoder setRenderPipelineState:_texturePipelineState];
      [commandEncoder setVertexBuffer:_meshModel.vertexBuffer offset:0 atIndex:0];
      [commandEncoder setVertexBuffer:_sharedUniformBuffer offset:sizeof(WMSharedUniforms) * _constantDataBufferIndex atIndex:1];
      [commandEncoder setVertexBuffer:_meshModelUniformBuffer offset:sizeof(WMPerInstanceUniforms) * _constantDataBufferIndex atIndex:2];
      [commandEncoder setFragmentTexture:_meshModelTexture atIndex:0];
      
      // [commandEncoder setTriangleFillMode:MTLTriangleFillModeLines];
      
      [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
                                 indexCount:_meshModel.indexBuffer.length / sizeof(uint32_t)
                                  indexType:MTLIndexTypeUInt32
                                indexBuffer:_meshModel.indexBuffer
                          indexBufferOffset:0];
      [commandEncoder popDebugGroup];
      
      // We're done encoding commands
      [commandEncoder endEncoding];
      
      // Schedule a present once the framebuffer is complete using the current drawable
      [commandBuffer presentDrawable:self.currentDrawable];
      }
    
    // The render assumes it can now increment the buffer index and that the previous index won't be touched until we cycle back around to the same index
    _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kMaxInflightBuffers;
    
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
  });
}

#pragma mark - Public Methods

-(void)setFocalMagnificationFactor:(float)focalMagnificationFactor
{
  _focalMagnificationFactor = focalMagnificationFactor;
  [self reshape];
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

- (void)setImageTexture:(nonnull UIImage*)image
{
  MTKTextureLoader *textureLoader = [[MTKTextureLoader alloc] initWithDevice:self.device];
  id<MTLTexture> texture = [textureLoader newTextureWithCGImage:[image CGImage] options:nil error:nil];
  [self setTexture:texture];
}

- (void)setTexture:(nonnull id<MTLTexture>)texture
{
  dispatch_sync(_rendererQueue, ^{
    _meshModelTexture = texture;
    _meshModelTexture.label = @"MeshModel Texture";
  });
}


@end
