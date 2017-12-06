//
//  PhotoAlbumViewController.m
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Keane. All rights reserved.
//

@import CoreMotion;

@import simd;
@import AVFoundation;
@import ImageIO;
@import CoreVideo;
@import Photos;

#import "PhotoAlbumViewController.h"
#import "WMUtilities.h"
#import "WMMatrixUtilities.h"
#import "WMRenderer.h"
#import "WMCamera.h"

@interface PhotoAlbumViewController()

@property (nonatomic, strong) WMRenderer *renderer;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, assign) BOOL requestPhotoLibrary;
@property (nonatomic, assign) BOOL isPhotoSelected;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, assign) BOOL useGyroscope;
@property (nonatomic, assign) float effectRotation;
@property (nonatomic, strong) CMAttitude *referenceMotionAttitude;
@property (nonatomic, assign) float adjustedMotionPitch;
@property (nonatomic, assign) float adjustedMotionRoll;
@property (nonatomic, assign) matrix_float4x4 matrixDeviceOrientation;

@end

@implementation PhotoAlbumViewController

static const float kEffectRotationRate = 3.5f;
static const float kEffectRotationRadius = 1.5f;
static const float kEffectGyroRadius = 6.0f;
static const float kEffectGyroResetEpsilon = 0.01f;
static const float kEffectGyroResetRate = 0.005f;
static const float kEffectMagnificationRate = 0.01f;
static const float kEffectMagnificationMinFactor = 0.90f;
static const float kEffectMagnificationRangeMin = 0.0f;
static const float kEffectMagnificationRangeMax = 30.0f;

- (void)viewDidLoad {
  _isPhotoSelected = NO;
  _requestPhotoLibrary = YES;
  _useGyroscope = NO;
  _effectRotation = 0.0f;
  _referenceMotionAttitude = nil;
  _matrixDeviceOrientation = matrix_identity_float4x4;
  
  [super viewDidLoad];
  
  [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus phstatus) {
    NSLog(@"PHAuthorizationStatus = %d", (int)phstatus);
  }];
  
  _renderer = [[WMRenderer alloc] initWithView:(MTKView *)self.view];
  
  // Gyroscope
  _motionManager = [[CMMotionManager alloc] init];
  _motionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
  
  // Update timer
  _updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                  target:self
                                                selector:@selector(doTimerUpdate)
                                                userInfo:nil
                                                 repeats:YES];
  
  // Gestures
  UITapGestureRecognizer *singleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self  action:@selector(didSingleTap:)];
  singleTapRecognizer.numberOfTapsRequired = 1;
  [self.view addGestureRecognizer:singleTapRecognizer];
  
  UITapGestureRecognizer *doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self  action:@selector(didDoubleTap:)];
  doubleTapRecognizer.numberOfTapsRequired = 2;
  [self.view addGestureRecognizer:doubleTapRecognizer];
  
  UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(didPinch:)];
  [self.view addGestureRecognizer:pinchRecognizer];
}

- (void)viewDidAppear:(BOOL)animated {
  if (_requestPhotoLibrary) {
    [self _selectPhotoFromLibrary];
    _requestPhotoLibrary = NO;
  }
}

- (BOOL)shouldAutorotate {
  return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return UIInterfaceOrientationMaskAll;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  UIDeviceOrientation deviceOrientation = UIDevice.currentDevice.orientation;
  if ((deviceOrientation == UIDeviceOrientationFaceDown) || (deviceOrientation == UIDeviceOrientationFaceUp)) {
    return;
  }
  
  float deviceOrientationRadAngle = 0.0f;
  switch (deviceOrientation) {
    case UIDeviceOrientationPortraitUpsideDown:
      deviceOrientationRadAngle = M_PI;
      break;
      
    case UIDeviceOrientationLandscapeLeft:
      deviceOrientationRadAngle = M_PI_2;
      break;
      
    case UIDeviceOrientationLandscapeRight:
      deviceOrientationRadAngle = -M_PI_2;
      break;
      
    default:;
  }
  
  _matrixDeviceOrientation = matrix_from_rotation(deviceOrientationRadAngle, 0.0f, 0.0f, 1.0f);
  
  _referenceMotionAttitude = nil;
}

#pragma mark Selectors

- (IBAction)backButtonTapped:(UIButton *)sender {
  [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)didSingleTap:(UITapGestureRecognizer*)gestureRecognizer {
  _useGyroscope = ! _useGyroscope;
  
  if (_useGyroscope) {
    [_updateTimer invalidate];
    _updateTimer = nil;
    
    _referenceMotionAttitude = nil;
    [_motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue]
                                        withHandler:^(CMDeviceMotion *motion, NSError *error) {
                                          [self updateForDeviceMotion:motion];
                                        }];
  } else {
    [_motionManager stopDeviceMotionUpdates];
    
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                    target:self
                                                  selector:@selector(doTimerUpdate)
                                                  userInfo:nil
                                                   repeats:YES];
  }
}

- (void)didDoubleTap:(UITapGestureRecognizer*)gestureRecognizer {
  [self _selectPhotoFromLibrary];
}

- (void)didPinch:(UIPinchGestureRecognizer*)gestureRecognizer {
  static float lastScale = 0.0f;
  
  if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
    lastScale = [gestureRecognizer scale];
  }
  
  if ((gestureRecognizer.state == UIGestureRecognizerStateBegan) ||
      (gestureRecognizer.state == UIGestureRecognizerStateChanged)) {
    const float newScale = (gestureRecognizer.scale - lastScale) * 25.0f;
    
    WMCamera *camera = [_renderer copyCamera];
    const float zPosition = MIN(kEffectMagnificationRangeMax, MAX(kEffectMagnificationRangeMin, [camera zPosition] + newScale));
    const float mag = kEffectMagnificationMinFactor - zPosition * kEffectMagnificationRate;
    
    [camera setZPosition:zPosition];
    [_renderer setCamera:camera];
    _renderer.focalMagnificationFactor = mag;
    
    lastScale = gestureRecognizer.scale;
  }
}

-(void)updateForDeviceMotion:(CMDeviceMotion*)deviceMotion {
  WMCamera *camera = [_renderer copyCamera];
  
  if ( ! _referenceMotionAttitude) {
    _referenceMotionAttitude = [deviceMotion.attitude copy];
    _adjustedMotionPitch = 0.0f;
    _adjustedMotionRoll = 0.0f;
  }
  
  CMAttitude *attitude = _motionManager.deviceMotion.attitude;
  [attitude multiplyByInverseOfAttitude:_referenceMotionAttitude];
  
  float roll  = attitude.roll - _adjustedMotionRoll;
  float pitch = attitude.pitch - _adjustedMotionPitch;
  
  if (fabs(roll) > kEffectGyroResetEpsilon) {
    _adjustedMotionRoll += kEffectGyroResetRate * ((roll > 0.0f) ? 1.0f : -1.0f);
  }
  
  if (fabs(pitch) > kEffectGyroResetEpsilon) {
    _adjustedMotionPitch += kEffectGyroResetRate * ((pitch > 0.0f) ? 1.0f : -1.0f);
  }
  
  const float rx = sinf(roll) * kEffectGyroRadius;
  const float ry = sinf(-pitch) * kEffectGyroRadius;
  
  vector_float4 vrxy = matrix_multiply(_matrixDeviceOrientation, vector4(rx, ry, 0.0f, 1.0f));
  [camera setXPosition:vrxy.x / vrxy.w];
  [camera setYPosition:vrxy.y / vrxy.w];
  
  [_renderer setCamera:camera];
}

-(void)doTimerUpdate {
  WMCamera *camera = [_renderer copyCamera];
  
  _effectRotation += kEffectRotationRate;
  if (fabs(_effectRotation) >= 360.0f) {
    _effectRotation -= 360.0f;
  }
  
  const float theta = _effectRotation / 180.0f * M_PI;
  const float rx = cosf(-theta) * kEffectRotationRadius;
  const float ry = sinf(-theta) * kEffectRotationRadius;
  
  [camera setXPosition:rx];
  [camera setYPosition:ry];
  [_renderer setCamera:camera];
}

#pragma mark Image Picker Delegate

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary *)info {
  [picker dismissViewControllerAnimated:YES completion:^{ }];
  
  PHAsset *asset = [info objectForKey:UIImagePickerControllerPHAsset];
  
  PHImageRequestOptions *imageRequestOptions = [[PHImageRequestOptions alloc] init];
  imageRequestOptions.synchronous = YES;
  imageRequestOptions.version = PHImageRequestOptionsVersionOriginal;
  imageRequestOptions.networkAccessAllowed = YES;
  
  [[PHImageManager defaultManager]  requestImageDataForAsset:asset
                                                     options:imageRequestOptions
                                               resultHandler:^(NSData *imageData,
                                                               NSString *dataUTI,
                                                               UIImageOrientation orientation,
                                                               NSDictionary *info) {
                                                 NSDictionary *cgImageProperties = [WMUtilities imagePropertiesFromImageData:imageData];
                                                 NSNumber *cgImageOrientationNumber = [cgImageProperties valueForKey:(id)kCGImagePropertyOrientation];
                                                 CGImagePropertyOrientation cgImageOrientation = (cgImageOrientationNumber != nil) ? cgImageOrientationNumber.intValue : kCGImagePropertyOrientationUp;
                                                 const float imageOrientationRadAngle = [WMUtilities radAngleFromImageOrientation:cgImageOrientation];
                                                 
                                                 AVDepthData *depthData = [WMUtilities depthDataFromImageData:imageData];
                                                 if ( !depthData ) {
                                                   if (!_isPhotoSelected) {
                                                     [self dismissViewControllerAnimated:YES completion:NULL];
                                                   }
                                                   return;
                                                 }
                                                 
                                                 [[PHImageManager defaultManager] requestImageForAsset:asset
                                                                                            targetSize:PHImageManagerMaximumSize
                                                                                           contentMode:PHImageContentModeDefault
                                                                                               options:imageRequestOptions
                                                                                         resultHandler:^(UIImage *image, NSDictionary *info) {
                                                                                           AVCameraCalibrationData *cameraCalibrationData = depthData.cameraCalibrationData;
                                                                                           const matrix_float3x3 intrinsicMatrix = matrix_transpose(cameraCalibrationData.intrinsicMatrix); // Metal requires row-major order
                                                                                           const CGSize intrinsicMatrixReferenceDimensions = cameraCalibrationData.intrinsicMatrixReferenceDimensions;
                                                                                           
                                                                                           [_renderer setTextureOrientation:imageOrientationRadAngle];
                                                                                           [_renderer setDepthMapOrientation:-imageOrientationRadAngle];
                                                                                           [_renderer setDepthMap:depthData.depthDataMap
                                                                                                  intrinsicMatrix:intrinsicMatrix
                                                                               intrinsicMatrixReferenceDimensions:intrinsicMatrixReferenceDimensions];
                                                                                           [_renderer setTexture:image];
                                                                                           
                                                                                           _isPhotoSelected = YES;
                                                                                         }];
                                               }];
}

-(void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
  [picker dismissViewControllerAnimated:YES completion:NULL];
  if (!_isPhotoSelected) {
    [self dismissViewControllerAnimated:YES completion:NULL];
  }
}

#pragma mark Private Methods

- (void)_selectPhotoFromLibrary {
  UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
  imagePickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
  imagePickerController.delegate = self;
  [self presentViewController:imagePickerController animated:YES completion:nil];
}

@end

