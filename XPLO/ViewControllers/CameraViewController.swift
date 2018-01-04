//
//  CameraViewController.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
//

import UIKit
import AVFoundation

class CameraViewController: UIViewController {
  
  @IBOutlet weak var previewView: PreviewView!
  @IBOutlet weak var cameraUnavailableLabel: UILabel!
  @IBOutlet weak var albumButton: UIButton!
  @IBOutlet weak var photoButton: UIButton!
  @IBOutlet weak var cameraButton: UIButton!
  @IBOutlet weak var resumeButton: UIButton!
  @IBOutlet weak var flashButton: UIButton!
  @IBOutlet weak var filterButton: UIButton!
  
  let camera = Camera()
  private var textureCache: CVMetalTextureCache?
  
  // MARK: View Controller Life Cycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Disable UI. The UI is enabled if and only if the session starts running.
    albumButton.isEnabled = false
    cameraButton.isEnabled = false
    photoButton.isEnabled = false
    flashButton.isEnabled = false
    filterButton.isEnabled = false
    
    setupXplo()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    camera.start() { (result) in
      switch result {
      case .success:
        break
        
      case .notAuthorized:
        DispatchQueue.main.async {
          let changePrivacySetting = "XPLO doesn't have permission to use the camera, please change privacy settings"
          let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
          let alertController = UIAlertController(title: "XPLO", message: message, preferredStyle: .alert)
          
          alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                  style: .cancel,
                                                  handler: nil))
          
          alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                  style: .`default`,
                                                  handler: { _ in
                                                    UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
          }))
          
          self.present(alertController, animated: true, completion: nil)
        }
        
      case .configurationFailed:
        DispatchQueue.main.async {
          let alertMsg = "Alert message when something goes wrong during capture session configuration"
          let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
          let alertController = UIAlertController(title: "XPLO", message: message, preferredStyle: .alert)
          
          alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                  style: .cancel,
                                                  handler: nil))
          
          self.present(alertController, animated: true, completion: nil)
        }
      }
    }
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    camera.stop()
    super.viewWillDisappear(animated)
  }
  
  // MARK: Xplo Setup
  
  func setupXplo() {
    camera.onStartRunning = {
      let isSessionRunning = self.camera.isSessionRunning
      self.albumButton.isEnabled = isSessionRunning
      self.flashButton.isEnabled = isSessionRunning
      self.filterButton.isEnabled = isSessionRunning
      // Only enable the ability to change camera if the device has more than one camera.
      self.cameraButton.isEnabled = isSessionRunning && self.camera.canToggleCaptureDevice
      self.photoButton.isEnabled = isSessionRunning
    }
    camera.onSessionInterrupted = { (reason) in
      if reason == .audioDeviceInUseByAnotherClient
        || reason == .videoDeviceInUseByAnotherClient {
        // Simply fade-in a button to enable the user to try to resume the session running.
        self.resumeButton.alpha = 0
        self.resumeButton.isHidden = false
        UIView.animate(withDuration: 0.25) {
          self.resumeButton.alpha = 1
        }
      } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
        // Simply fade-in a label to inform the user that the camera is unavailable.
        self.cameraUnavailableLabel.alpha = 0
        self.cameraUnavailableLabel.isHidden = false
        UIView.animate(withDuration: 0.25) {
          self.cameraUnavailableLabel.alpha = 1
        }
      }
      
    }
    camera.onSessionInterruptionEnded = {
      if !self.resumeButton.isHidden {
        UIView.animate(withDuration: 0.25,
                       animations: {
                        self.resumeButton.alpha = 0
        }, completion: { _ in
          self.resumeButton.isHidden = true
        })
      }
      if !self.cameraUnavailableLabel.isHidden {
        UIView.animate(withDuration: 0.25,
                       animations: {
                        self.cameraUnavailableLabel.alpha = 0
        }, completion: { _ in
          self.cameraUnavailableLabel.isHidden = true
        })
      }
    }
    camera.onStream = { (videoSampleBuffer, depthData) in
      if let depthData = depthData,
        let cameraCalibrationData = depthData.cameraCalibrationData,
        let texture = self.texture(sampleBuffer: videoSampleBuffer) {
        let intrinsicMatrix = cameraCalibrationData.intrinsicMatrix.transpose
        let intrinsicMatrixReferenceDimensions = cameraCalibrationData.intrinsicMatrixReferenceDimensions
        let imageOrientationRadAngle: Float = Float(Double.pi)
        self.previewView.setTextureOrientation(imageOrientationRadAngle)
        self.previewView.setDepthMapOrientation(-imageOrientationRadAngle)
        self.previewView.setDepthMap(depthData.depthDataMap,
                                     intrinsicMatrix: intrinsicMatrix,
                                     intrinsicMatrixReferenceDimensions: intrinsicMatrixReferenceDimensions)
        self.previewView.setTexture(texture)
      }
    }
  }
  
  // MARK: Texture
  
  func createTextureCache() {
    guard let device = previewView.device else {
      fatalError("Unable to get device")
    }
    var newTextureCache: CVMetalTextureCache?
    if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &newTextureCache) == kCVReturnSuccess {
      textureCache = newTextureCache
    } else {
      assertionFailure("Unable to allocate texture cache")
    }
  }
  
  func texture(sampleBuffer: CMSampleBuffer?) -> MTLTexture? {
    if self.textureCache == nil {
      self.createTextureCache()
    }
    
    guard let sampleBuffer = sampleBuffer,
      let textureCache = self.textureCache,
      let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return nil
    }
    
    let planeIndex: Int = 0
    let pixelFormat: MTLPixelFormat = .bgra8Unorm
    let width = CVPixelBufferGetWidth(imageBuffer)
    let height = CVPixelBufferGetHeight(imageBuffer)
    var imageTexture: CVMetalTexture?
    let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           textureCache,
                                                           imageBuffer,
                                                           nil,
                                                           pixelFormat,
                                                           width,
                                                           height,
                                                           planeIndex,
                                                           &imageTexture)
    
    guard let unwrappedImageTexture = imageTexture,
      let texture = CVMetalTextureGetTexture(unwrappedImageTexture),
      result == kCVReturnSuccess else {
        return nil
    }
    
    return texture
  }
  
  // MARK: Device Configuration
  
  @IBAction func toggleCamera(_ sender: UIButton) {
    guard camera.canToggleCaptureDevice else {
      return
    }
    albumButton.isEnabled = false
    flashButton.isEnabled = false
    filterButton.isEnabled = false
    cameraButton.isEnabled = false
    photoButton.isEnabled = false
    camera.toggleCaptureDevice() {
      self.albumButton.isEnabled = true
      self.flashButton.isEnabled = true
      self.cameraButton.isEnabled = true
      self.photoButton.isEnabled = true
      self.filterButton.isEnabled = true
    }
  }
  
  // MARK: Capturing Photos
  
  @IBAction func capturePhoto(_ sender: UIButton) {
    camera.capturePhoto()
  }
  
  // MARK: Flash
  
  @IBAction func flashButtonTapped(_ sender: UIButton) {
    switch camera.flashMode {
    case .auto:
      camera.flashMode = .on
      flashButton.setImage(UIImage(named: "flash_on"), for: .normal)
      
    case .on:
      camera.flashMode = .off
      flashButton.setImage(UIImage(named: "flash_off"), for: .normal)
      
    case .off:
      camera.flashMode = .auto
      flashButton.setImage(UIImage(named: "flash_auto"), for: .normal)
    }
  }
  
  // MARK: Filter
  
  @IBAction func filterButtonTapped(_ sender: UIButton) {
    if camera.depthDataOutput.isFilteringEnabled {
      sender.setImage(UIImage(named: "no_filter"), for: .normal)
    } else {
      sender.setImage(UIImage(named: "filter"), for: .normal)
    }
    camera.depthDataOutput.isFilteringEnabled = !camera.depthDataOutput.isFilteringEnabled
  }
  
  // MARK: Session
  
  @IBAction func resumeInterruptedSession(_ sender: UIButton) {
    camera.resume() {
      if !self.camera.isSessionRunning {
        let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
        let alertController = UIAlertController(title: "XPLO", message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
      } else {
        self.resumeButton.isHidden = true
      }
    }
  }
  
}
