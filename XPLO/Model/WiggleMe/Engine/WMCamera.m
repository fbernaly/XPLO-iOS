//
//  WMCamera.m
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

@import GLKit;

#import "WMCamera.h"
#import "WMMatrixUtilities.h"

#define deg2rad(x) ((x) / 180.0 * M_PI)

@interface WMCamera()

@property (nonatomic, assign) vector_float3 init_position;
@property (nonatomic, assign) vector_float3 init_rotation;

@end

@implementation WMCamera

@synthesize position = _position;
@synthesize rotation = _rotation;

- (nonnull instancetype)initCameraWithPosition:(vector_float3)position
                                   andRotation:(vector_float3)rotation
{
  if (self = [super init]) {
    [self setDefaultCameraWithPosition:position andRotation:rotation];
    [self resetCamera];
  }
  
  return self;
}

-(id)copyWithZone:(NSZone*)zone
{
  WMCamera *cameraCopy = [[WMCamera allocWithZone:zone] init];
  
  cameraCopy.init_position = self.init_position;
  cameraCopy.init_rotation = self.init_rotation;
  cameraCopy.position = self.position;
  cameraCopy.rotation = self.rotation;
  
  return cameraCopy;
}

- (void)resetCamera
{
  _position = _init_position;
  _rotation = _init_rotation;
}

- (void)setDefaultCameraWithPosition:(vector_float3)position
                         andRotation:(vector_float3)rotation
{
  _init_position = position;
  _init_rotation = rotation;
}

- (matrix_float4x4)lookAt
{
  // Create rotation matrix from quaternions in order to avoid gimbal lock error
  const GLKQuaternion rotX = GLKQuaternionMakeWithAngleAndAxis(deg2rad([self tilt]), -1.0f,  0.0f,  0.0f);
  const GLKQuaternion rotY = GLKQuaternionMakeWithAngleAndAxis(deg2rad([self pan]),   0.0f, -1.0f,  0.0f);
  const GLKQuaternion rotZ = GLKQuaternionMakeWithAngleAndAxis(deg2rad([self roll]),  0.0f,  0.0f, -1.0f);
  const GLKQuaternion rotXYZ = GLKQuaternionNormalize(GLKQuaternionMultiply(rotX, GLKQuaternionMultiply(rotY, rotZ)));
  const GLKMatrix4 glkMatRotXYZ = GLKMatrix4MakeWithQuaternion(rotXYZ);
  
  matrix_float4x4 rotMat;
  memcpy(&rotMat, glkMatRotXYZ.m, sizeof(matrix_float4x4));
  
  return matrix_multiply(matrix_from_translation(-_position.x, -_position.y, -_position.z), rotMat);
}

- (float)tilt
{
  return _rotation[0];
}

- (void)setTilt:(float)degrees
{
  if (degrees < 0.0f)  { degrees = 360.0f + degrees; }
  if (degrees > 360.0) { degrees = degrees - 360.0f; }
  
  _rotation[0] = degrees;
}

- (float)pan
{
  return _rotation[1];
}

- (void)setPan:(float)degrees
{
  if (degrees < 0.0f)  { degrees = 360.0f + degrees; }
  if (degrees > 360.0) { degrees = degrees - 360.0f; }
  
  _rotation[1] = degrees;
}

- (float)roll
{
  return _rotation[2];
}

- (void)setRoll:(float)degrees
{
  if (degrees < 0.0f)  { degrees = 360.0f + degrees; }
  if (degrees > 360.0) { degrees = degrees - 360.0f; }
  
  _rotation[2] = degrees;
}

- (float)xPosition
{
  return _position[0];
}

- (void)setXPosition:(float)xPosition
{
  _position[0] = xPosition;
}

- (float)yPosition
{
  return _position[1];
}

- (void)setYPosition:(float)yPosition
{
  _position[1] = yPosition;
}

- (float)zPosition
{
  return _position[2];
}

- (void)setZPosition:(float)zPosition
{
  _position[2] = zPosition;
}

@end
