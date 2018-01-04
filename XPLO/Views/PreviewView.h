//
//  PreviewView.h
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/3/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

#import <MetalKit/MetalKit.h>

@interface PreviewView : MTKView

@property (nonatomic, assign) float focalMagnificationFactor;
@property (nonatomic, strong) WMCamera * _Nullable camera;

- (void)setDepthMap:(nonnull CVPixelBufferRef)depthMap intrinsicMatrix:(matrix_float3x3)intrinsicMatrix intrinsicMatrixReferenceDimensions:(CGSize)intrinsicMatrixReferenceDimensions;
- (void)setDepthMapOrientation:(float)angleRad;
- (void)setTextureOrientation:(float)angleRad;
- (void)setImageTexture:(nonnull UIImage*)image;
- (void)setTexture:(nonnull id<MTLTexture>)texture;

@end
