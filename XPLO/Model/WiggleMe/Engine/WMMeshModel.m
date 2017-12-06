//
//  WMMeshModel.m
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

#import "WMTypes.h"

#import "WMMeshModel.h"
#import "WMMatrixUtilities.h"

#define lerp(a, b, t) ((a) * ( 1 - (t) ) + (b) * (t))

@interface WMMeshModel()

@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> indexBuffer;
@property (nonatomic, assign) int numColumns;
@property (nonatomic, assign) int numRows;
@property (nonatomic, assign) int vertexCount;
@property (nonatomic, assign) int indexCount;
@property (nonatomic, assign) matrix_float4x4 matTextureRot;

@end

@implementation WMMeshModel

@synthesize indexBuffer  = _indexBuffer;
@synthesize vertexBuffer = _vertexBuffer;
@synthesize modelMatrix  = _modelMatrix;

- (nonnull instancetype)initWithColumns:(int)numColumns
                                   rows:(int)numRows
                            modelMatrix:(matrix_float4x4)modelMatrix
                                 device:(nonnull id<MTLDevice>)device
{
  if (self = [super init]) {
    _numColumns = numColumns;
    _numRows = numRows;
    _modelMatrix = modelMatrix;
    _matTextureRot = matrix_identity_float4x4;
    
    [self _createVertexAndIndexBufferWithDevice:device];
    [self _createMeshIndices];
  }
  
  return self;
}

- (void)setTextureOrientation:(float)radAngle
{
  _matTextureRot = matrix_from_rotation(radAngle, 0.0f, 0.0f, 1.0f);
}

- (void)setDepthMap:(nonnull CVPixelBufferRef)depthMap
    intrinsicMatrix:(matrix_float3x3)intrinsicMatrix
intrinsicMatrixReferenceDimensions:(CGSize)intrinsicMatrixReferenceDimensions
{
  [self _createMeshCoordinatesWithDepthMap:depthMap
                           intrinsicMatrix:intrinsicMatrix
        intrinsicMatrixReferenceDimensions:intrinsicMatrixReferenceDimensions];
}

#pragma mark Private Methods

- (void)_createVertexAndIndexBufferWithDevice:(nonnull id<MTLDevice>)device
{
  _vertexCount = _numColumns * _numRows;
  
  _vertexBuffer = [device newBufferWithLength:_vertexCount * sizeof(WMTextureVertex)
                                      options:MTLResourceOptionCPUCacheModeDefault];
  _vertexBuffer.label = [NSString stringWithFormat:@"Vertices (%@)", @"MeshModel"];
  
  const int numStrip = (_numRows - 1);
  const int nDegens = 2 * (numStrip - 1);
  const int verticesPerStrip = 2 * _numColumns;
  
  _indexCount = verticesPerStrip * numStrip + nDegens;
  
  _indexBuffer = [device newBufferWithLength:_indexCount * sizeof(uint32_t)
                                     options:MTLResourceOptionCPUCacheModeDefault];
  _indexBuffer.label = [NSString stringWithFormat:@"Indices (%@)", @"MeshModel"];
}

- (void)_createMeshCoordinatesWithDepthMap:(nonnull CVPixelBufferRef)depthMapPixelBuffer
                           intrinsicMatrix:(matrix_float3x3)intrinsicMatrix
        intrinsicMatrixReferenceDimensions:(CGSize)intrinsicMatrixReferenceDimensions
{
  const matrix_float4x4 matOrig = matrix_from_scale(1.0f, -1.0f, 1.0f);
  
  CVPixelBufferLockBaseAddress(depthMapPixelBuffer, 0);
  
  const int depthMapWidth  = (int)CVPixelBufferGetWidth(depthMapPixelBuffer);
  const int depthMapHeight = (int)CVPixelBufferGetHeight(depthMapPixelBuffer);
  const uint8_t *pin = CVPixelBufferGetBaseAddress(depthMapPixelBuffer);
  const size_t rowBytesSize = CVPixelBufferGetBytesPerRow(depthMapPixelBuffer);
  
  WMTextureVertex* pvertex = (WMTextureVertex*)[_vertexBuffer contents];
  
  const float cx = intrinsicMatrix.columns[0].z / intrinsicMatrixReferenceDimensions.width * _numColumns;
  const float cy = intrinsicMatrix.columns[1].z / intrinsicMatrixReferenceDimensions.height * _numRows;
  const float focalLength = intrinsicMatrix.columns[0].x / intrinsicMatrixReferenceDimensions.width * _numColumns;
  
  float xMin = FLT_MAX;
  float xMax = FLT_MIN;
  float yMin = FLT_MAX;
  float yMax = FLT_MIN;
  float zMin = FLT_MAX;
  float zMax = FLT_MIN;
  
  // Computes vertex coordinates
  WMTextureVertex* pvertex__ = pvertex;
  for (int y = 0; y < _numRows; ++y) {
    for (int x = 0; x < _numColumns; ++x) {
      // Interpolated disparity
      const float xs = (x / (float)(_numColumns - 1));
      const float ys = (y / (float)(_numRows - 1));
      
      const int xsi = (int)(xs * (depthMapWidth - 1));
      const int ysi = (int)(ys * (depthMapHeight - 1));
      
      const int xsip = MIN(xsi + 1, depthMapWidth - 1);
      const int ysip = MIN(ysi + 1, depthMapHeight - 1);
      
      const float c00 = *(float*)(&pin[ysi  * rowBytesSize + xsi  * sizeof(float)]);
      const float c10 = *(float*)(&pin[ysi  * rowBytesSize + xsip * sizeof(float)]);
      const float c01 = *(float*)(&pin[ysip * rowBytesSize + xsi  * sizeof(float)]);
      const float c11 = *(float*)(&pin[ysip * rowBytesSize + xsip * sizeof(float)]);
      
      const float dxs = (xs - (int)xs);
      const float dys = (ys - (int)ys);
      const float dout = lerp(lerp(c00, c10, dxs), lerp(c01, c11, dxs), dys);
      
      // Creates the vertex from the top down, so that our triangles are
      // counter-clockwise.
      float zz = 1.0f / dout;
      float xx = (x - cx) * zz / focalLength;
      float yy = (y - cy) * zz / focalLength;
      
      // We work in centimeters
      xx = xx * 100.0f;
      yy = yy * 100.0f;
      zz = zz * 100.0f;
      
      xMin = MIN(xMin, xx);
      xMax = MAX(xMax, xx);
      yMin = MIN(yMin, yy);
      yMax = MAX(yMax, yy);
      zMin = MIN(zMin, zz);
      zMax = MAX(zMax, zz);
      
      const vector_float4 pver = matrix_multiply(matrix_multiply(matOrig, _modelMatrix), (vector_float4){xx, yy, zz, 1.0f});
      pvertex__->vx = pver.x / pver.w;
      pvertex__->vy = pver.y / pver.w;
      pvertex__->vz = pver.z / pver.w;
      
      const vector_float4 ptex = matrix_multiply(_matTextureRot, (vector_float4){xs - 0.5f, ys - 0.5f, 0.0f, 1.0f});
      pvertex__->tx = (ptex.x / ptex.w) + 0.5f;
      pvertex__->ty = (ptex.y / ptex.w) + 0.5f;
      
      pvertex__++;
    }
  }
  
  CVPixelBufferUnlockBaseAddress(depthMapPixelBuffer, 0);
  
  NSLog(@"Depth::X = [%.2f, %.2f] cm, Y = [%.2f, %.2f] cm, Z = [%.2f, %.2f] cm", xMin, xMax, yMin, yMax, zMin, zMax);
}

- (void)_createMeshIndices
{
  // A complete object can be described as a degenerate strip,
  // which contains zero-area triangles that the processing software
  // or hardware will discard.
  //
  //     1 ---- 2 ---- 3 ---- 4 ---- 5
  //     |    /^|    /^|    /^|    /^|
  //     |  /   |  /   |  /   |  /   |
  //     v/     v/     v/     v/     |
  // deg 6 ---- 7 ---- 8 ---- 9 ----10 deg
  //     |    /^|    /^|    /^|    /^|
  //     |  /   |  /   |  /   |  /   |
  //     v/     v/     v/     v/     |
  //     11----12 ----13 ----14 ----15
  //
  // Indices:
  // 1, 6, 2, 7, 3, 8, 4, 9, 5, 10, (10, 6), 6, 11, 7, 12, 8, 13, 9, 14, 10, 15
  
  uint32_t* pind = (uint32_t*)[_indexBuffer contents];
  
  for (int y = 0; y < (_numRows - 1); ++y) {
    // Degenerate index on non-first row
    if (y > 0) {
      *pind++ = (uint32_t)(y * _numColumns);
    }
    
    // Current strip
    for (int x = 0; x < _numColumns; ++x) {
      *pind++ = (uint32_t)((y    ) * _numColumns + x);
      *pind++ = (uint32_t)((y + 1) * _numColumns + x);
    }
    
    // Degenerate index on non-last row
    if (y < (_numRows - 2)) {
      *pind++ = (uint32_t)((y + 1) * _numColumns + (_numColumns - 1));
    }
  }
}

@end
