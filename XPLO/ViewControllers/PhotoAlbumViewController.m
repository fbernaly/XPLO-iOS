//
//  PhotoAlbumViewController.m
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
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
#import "WMCamera.h"
#import "PreviewView.h"

@interface PhotoAlbumViewController()

@property (nonatomic, assign) BOOL requestPhotoLibrary;
@property (nonatomic, assign) BOOL isPhotoSelected;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, assign) BOOL manual;
@property (nonatomic, assign) float effectRotation;
@property (nonatomic, assign) matrix_float4x4 matrixDeviceOrientation;
@property (weak, nonatomic) IBOutlet PreviewView *previewView;
@property (weak, nonatomic) IBOutlet UIButton *wiggleButton;
@property (weak, nonatomic) IBOutlet UIButton *manualButton;

@end

@implementation PhotoAlbumViewController

static const float kEffectRotationRate = 5.0f;
static const float kEffectRotationRadius = 1.5f;
static const float kEffectMagnificationRate = 0.01f;
static const float kEffectMagnificationMinFactor = 0.90f;
static const float kEffectMagnificationRangeMin = 0.0f;
static const float kEffectMagnificationRangeMax = 30.0f;

- (void)viewDidLoad {
  _isPhotoSelected = NO;
  _requestPhotoLibrary = YES;
  _manual = NO;
  _effectRotation = 0.0f;
  _matrixDeviceOrientation = matrix_identity_float4x4;
  
  [super viewDidLoad];
  
  [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus phstatus) {
    NSLog(@"PHAuthorizationStatus = %d", (int)phstatus);
  }];
  
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
  
  UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(didPan:)];
  [panRecognizer setMinimumNumberOfTouches:1];
  [panRecognizer setMaximumNumberOfTouches:1];
  [self.view addGestureRecognizer:panRecognizer];
}

- (void)viewDidAppear:(BOOL)animated {
  if (_requestPhotoLibrary) {
    [self _selectPhotoFromLibrary];
    _requestPhotoLibrary = NO;
  }
}

#pragma mark Selectors

- (IBAction)backButtonTapped:(UIButton *)sender {
  [self dismissViewControllerAnimated:YES completion:NULL];
}

- (IBAction)shareButtonTapped:(UIButton *)sender {
}

- (IBAction)photoAlbumButtonTapped:(UIButton *)sender {
  [self _selectPhotoFromLibrary];
}

- (IBAction)manualButtonTapped:(UIButton *)sender {
  if (sender.isSelected) return;
  sender.selected = YES;
  sender.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
  _wiggleButton.backgroundColor = [UIColor clearColor];
  _wiggleButton.selected = NO;
  [self useManual];
}

- (IBAction)wiggleButtonTapped:(UIButton *)sender {
  if (sender.isSelected) return;
  sender.selected = YES;
  sender.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
  _manualButton.backgroundColor = [UIColor clearColor];
  _manualButton.selected = NO;
  [self useTimer];
}

- (void)didSingleTap:(UITapGestureRecognizer*)gestureRecognizer {
  if (!_manual) {
    [self useManual];
  } else {
    [self useTimer];
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
    
    WMCamera *camera = [_previewView.camera copy];
    const float zPosition = MIN(kEffectMagnificationRangeMax, MAX(kEffectMagnificationRangeMin, [camera zPosition] + newScale));
    const float mag = kEffectMagnificationMinFactor - zPosition * kEffectMagnificationRate;
    
    [camera setZPosition:zPosition];
    [_previewView setCamera:camera];
    _previewView.focalMagnificationFactor = mag;
    
    lastScale = gestureRecognizer.scale;
  }
}

- (void)didPan:(UIPanGestureRecognizer*)gestureRecognizer {
  CGPoint point = [gestureRecognizer translationInView: self.view];
  [gestureRecognizer setTranslation:CGPointZero inView: self.view];
  WMCamera *camera = [_previewView.camera copy];
  
  float pan = (float)point.x / 180.0f * M_PI;
  float tilt = (float)point.y / 180.0f * M_PI;
  
  [camera setPan: camera.pan + pan];
  [camera setTilt: camera.tilt + tilt];
  
  [_previewView setCamera:camera];
}

#pragma mark Animation

-(void)useManual {
  _manual = YES;
  [_updateTimer invalidate];
  _updateTimer = nil;
  _effectRotation = 0.0f;
}

-(void)useTimer {
  _manual = NO;
  _updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                  target:self
                                                selector:@selector(doTimerUpdate)
                                                userInfo:nil
                                                 repeats:YES];
}

-(void)doTimerUpdate {
  WMCamera *camera = [_previewView.camera copy];
  
  _effectRotation += kEffectRotationRate;
  _effectRotation = (float)((int)_effectRotation%360);
  
  const float theta = _effectRotation / 180.0f * M_PI;
  const float rx = cosf(-theta) * kEffectRotationRadius;
  const float ry = sinf(-theta) * kEffectRotationRadius;
  
  [camera setXPosition:rx];
  [camera setYPosition:ry];
  [_previewView setCamera:camera];
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
                                                                                           
                                                                                           [_previewView setTextureOrientation:imageOrientationRadAngle];
                                                                                           [_previewView setDepthMapOrientation:-imageOrientationRadAngle];
                                                                                           [_previewView setDepthMap:depthData.depthDataMap
                                                                                                     intrinsicMatrix:intrinsicMatrix
                                                                                  intrinsicMatrixReferenceDimensions:intrinsicMatrixReferenceDimensions];
                                                                                           [_previewView setImageTexture:image];
                                                                                           
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

