//
//  WMUtilities.m
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

#import "WMUtilities.h"

@implementation WMUtilities

+ (float)radAngleFromImageOrientation:(CGImagePropertyOrientation)orientation
{
  switch (orientation) {
    case kCGImagePropertyOrientationDown:  return M_PI;
    case kCGImagePropertyOrientationRight: return M_PI_2;
    case kCGImagePropertyOrientationLeft:  return -M_PI_2;
      
    default:
      return 0.0f;
  }
}

+ (float)fieldOfViewFromViewport:(CGSize)viewport
                depthOrientation:(float)depthAngleRad
                     focalLength:(float)focalLength
        referenceFrameDimensions:(CGSize)referenceFrameDimensions
             magnificationFactor:(float)magFactor
{
  const float referenceFrameAspectRatio = referenceFrameDimensions.width / referenceFrameDimensions.height;
  const bool isDepthLandscape = (fmod(fabs(depthAngleRad), M_PI) < 1e-4f);
  const bool isViewLandscape = isDepthLandscape
  ? (viewport.width / viewport.height) > referenceFrameAspectRatio
  : (viewport.height / viewport.width) < referenceFrameAspectRatio;
  
  // Field of view from the focal length of the camera (assume same orientation as camera, i.e. horizontal)
  float fov = 2.0f * atanf(referenceFrameDimensions.width / (2.0f * focalLength * magFactor));
  
  // The field of view is based on the vertical focal length of the depth
  if (isDepthLandscape != isViewLandscape) {
    fov *= referenceFrameAspectRatio;
  }
  
  // Compute the vertical field of view
  if ( ! isViewLandscape ) {
    fov = 2.0f * atanf(tanf(0.5f * fov) * (viewport.height / viewport.width));
  }
  
  return fov;
}

+ (nullable NSDictionary *)imagePropertiesFromImageData:(nonnull NSData*)imageData
{
  CGImageSourceRef cgImageSource = CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
  NSDictionary *cgImageProperties = (__bridge_transfer NSDictionary*)CGImageSourceCopyPropertiesAtIndex(cgImageSource, 0, NULL);
  if (cgImageSource) {
    CFRelease(cgImageSource);
  }
  
  return cgImageProperties;
}

+ (nullable AVDepthData *)depthDataFromImageData:(nonnull NSData *)imageData
{
  AVDepthData *depthData = nil;
  
  CGImageSourceRef imageSource = CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
  if (imageSource) {
    NSDictionary *auxDataDictionary = (__bridge NSDictionary *)CGImageSourceCopyAuxiliaryDataInfoAtIndex(imageSource, 0, kCGImageAuxiliaryDataTypeDisparity);
    if (auxDataDictionary) {
      depthData = [AVDepthData depthDataFromDictionaryRepresentation:auxDataDictionary error:NULL];
      depthData = [depthData depthDataByConvertingToDepthDataType:kCVPixelFormatType_DisparityFloat32]; // Convert to 32-bit disparity for use on the CPU
    }
    
    CFRelease(imageSource);
  }
  
  return depthData;
}

@end

