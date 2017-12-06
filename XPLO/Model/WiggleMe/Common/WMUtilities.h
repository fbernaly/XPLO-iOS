//
//  WMUtilities.h
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

@import Foundation;
@import CoreGraphics;
@import CoreVideo;
@import ImageIO;
@import AVFoundation;

@interface WMUtilities : NSObject

+ (float)radAngleFromImageOrientation:(CGImagePropertyOrientation)orientation;

// Maintain image contents regardless of the orientation of the device
+ (float)fieldOfViewFromViewport:(CGSize)viewport
                depthOrientation:(float)depthAngleRad
                     focalLength:(float)focalLength
        referenceFrameDimensions:(CGSize)referenceFrameDimensions
             magnificationFactor:(float)magFactor;

+ (nullable NSDictionary *)imagePropertiesFromImageData:(nonnull NSData*)imageData;

+ (nullable AVDepthData *)depthDataFromImageData:(nonnull NSData *)imageData;

@end
