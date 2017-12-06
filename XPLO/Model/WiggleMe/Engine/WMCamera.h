//
//  WMCamera.h
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

@import Foundation;

#import "WMTypes.h"

@interface WMCamera : NSObject<NSCopying>

@property (nonatomic, assign) vector_float3 position;
@property (nonatomic, assign) vector_float3 rotation;

- (nonnull instancetype)initCameraWithPosition:(vector_float3)position
                                   andRotation:(vector_float3)rotation;

- (void)resetCamera;
- (void)setDefaultCameraWithPosition:(vector_float3)position
                         andRotation:(vector_float3)rotation;

// Determine the transformation matrix that defines the viewer's position
- (matrix_float4x4)lookAt;

// Rotation on X
- (float)tilt;
- (void)setTilt:(float)degrees;

// Rotation on Y
- (float)pan;
- (void)setPan:(float)degrees;

// Rotation on Z
- (float)roll;
- (void)setRoll:(float)degrees;

// Position on X
- (float)xPosition;
- (void)setXPosition:(float)xPosition;

// Position on Y
- (float)yPosition;
- (void)setYPosition:(float)yPosition;

// Position on Z
- (float)zPosition;
- (void)setZPosition:(float)zPosition;

@end

