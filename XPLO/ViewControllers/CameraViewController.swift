//
//  CameraViewController.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Keane. All rights reserved.
//

import UIKit

class CameraViewController: UIViewController {
  
  @IBOutlet weak var previewView: PreviewView!
  @IBOutlet weak var cameraUnavailableLabel: UILabel!
  @IBOutlet weak var capturingLivePhotoLabel: UILabel!
  @IBOutlet weak var photoButton: UIButton!
  @IBOutlet weak var cameraButton: UIButton!
  @IBOutlet weak var recordButton: UIButton!
  @IBOutlet weak var resumeButton: UIButton!
  @IBOutlet weak var livePhotoModeButton: UIButton!
  @IBOutlet weak var depthDataDeliveryButton: UIButton!
  @IBOutlet weak var captureModeControl: UISegmentedControl!
  
  let xplo = Capture()
  
  // MARK: View Controller Life Cycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Disable UI. The UI is enabled if and only if the session starts running.
    cameraButton.isEnabled = false
    recordButton.isEnabled = false
    recordButton.isHidden = true
    photoButton.isEnabled = false
    livePhotoModeButton.isEnabled = false
    depthDataDeliveryButton.isEnabled = false
    captureModeControl.isEnabled = false
    
    setupXplo()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    xplo.start() { (result) in
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
    xplo.stop()
    super.viewWillDisappear(animated)
  }
  
  override var shouldAutorotate: Bool {
    // Disable autorotation of the interface when recording is in progress.
    if let movieFileOutput = xplo.movieFileOutput {
      return !movieFileOutput.isRecording
    }
    return true
  }
  
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return .all
  }
  
  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    xplo.rotate()
  }
  
  // MARK: Xplo Setup
  
  func setupXplo() {
    xplo.previewView = previewView
    xplo.onStartRunning = {
      let isSessionRunning = self.xplo.isSessionRunning
      let isLivePhotoCaptureSupported = self.xplo.photoOutput.isLivePhotoCaptureSupported
      let isLivePhotoCaptureEnabled = self.xplo.photoOutput.isLivePhotoCaptureEnabled
      let isDepthDeliveryDataSupported = self.xplo.photoOutput.isDepthDataDeliverySupported
      let isDepthDeliveryDataEnabled = self.xplo.photoOutput.isDepthDataDeliveryEnabled
      
      // Only enable the ability to change camera if the device has more than one camera.
      self.cameraButton.isEnabled = isSessionRunning && self.xplo.canToggleCamera
      self.recordButton.isEnabled = isSessionRunning && self.xplo.movieFileOutput != nil
      self.photoButton.isEnabled = isSessionRunning
      self.captureModeControl.isEnabled = isSessionRunning
      self.livePhotoModeButton.isEnabled = isSessionRunning && isLivePhotoCaptureEnabled
      self.livePhotoModeButton.isHidden = !(isSessionRunning && isLivePhotoCaptureSupported)
      self.depthDataDeliveryButton.isEnabled = isSessionRunning && isDepthDeliveryDataEnabled
      self.depthDataDeliveryButton.isHidden = !(isSessionRunning && isDepthDeliveryDataSupported)
    }
    xplo.onSessionInterrupted = { (reason) in
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
    xplo.onSessionInterruptionEnded = {
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
  }
  
  // MARK: Device Configuration
  
  @IBAction func toggleCaptureMode(_ sender: UISegmentedControl) {
    guard let captureMode = CaptureMode(rawValue: captureModeControl.selectedSegmentIndex) else {
      return
    }
    captureModeControl.isEnabled = false
    xplo.setCaptureMode(captureMode) {
      self.captureModeControl.isEnabled = true
      switch captureMode {
      case .photo:
        self.depthDataDeliveryButton.isHidden = !self.xplo.photoOutput.isDepthDataDeliverySupported
        self.depthDataDeliveryButton.isEnabled = self.xplo.photoOutput.isDepthDataDeliveryEnabled
        self.livePhotoModeButton.isHidden = !self.xplo.photoOutput.isLivePhotoCaptureSupported
        self.livePhotoModeButton.isEnabled = self.xplo.photoOutput.isLivePhotoCaptureEnabled
        self.recordButton.isHidden = true
        
      case .movie:
        self.depthDataDeliveryButton.isHidden = true
        self.livePhotoModeButton.isHidden = true
        self.recordButton.isHidden = false
        self.recordButton.isEnabled = self.xplo.movieFileOutput != nil
      }
    }
  }
  
  @IBAction func toggleCamera(_ sender: UIButton) {
    cameraButton.isEnabled = false
    recordButton.isEnabled = false
    photoButton.isEnabled = false
    livePhotoModeButton.isEnabled = false
    captureModeControl.isEnabled = false
    xplo.toggleCamera() {
      self.cameraButton.isEnabled = true
      self.recordButton.isHidden = self.xplo.captureMode != .movie
      self.recordButton.isEnabled = self.xplo.movieFileOutput != nil
      self.photoButton.isEnabled = true
      self.livePhotoModeButton.isEnabled = true
      self.captureModeControl.isEnabled = true
      self.depthDataDeliveryButton.isHidden = !self.xplo.photoOutput.isDepthDataDeliverySupported
      self.depthDataDeliveryButton.isEnabled = self.xplo.photoOutput.isDepthDataDeliveryEnabled
    }
  }
  
  @IBAction func toggleLivePhotoMode(_ sender: UIButton) {
    xplo.toggleLivePhotoMode() {
      switch self.xplo.livePhotoMode {
      case .on:
        self.livePhotoModeButton.setTitle(NSLocalizedString("Live Photo Mode: On", comment: "Live photo mode button on title"), for: [])
        
      case .off:
        self.livePhotoModeButton.setTitle(NSLocalizedString("Live Photo Mode: Off", comment: "Live photo mode button off title"), for: [])
      }
    }
  }
  
  @IBAction func toggleDepthDataDeliveryMode(_ depthDataDeliveryButton: UIButton) {
    xplo.toggleDepthDataDeliveryMode() {
      switch self.xplo.depthDataDeliveryMode {
      case .on:
        self.depthDataDeliveryButton.setTitle(NSLocalizedString("Depth Data Delivery: On", comment: "Depth Data Delivery button on title"), for: [])
        
      case .off:
        self.depthDataDeliveryButton.setTitle(NSLocalizedString("Depth Data Delivery: Off", comment: "Depth Data Delivery button off title"), for: [])
      }
    }
  }
  
  @IBAction func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
    let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
    xplo.focus(with: .autoFocus,
               exposureMode: .autoExpose,
               at: devicePoint,
               monitorSubjectAreaChange: true)
  }
  
  // MARK: Capturing Photos
  
  @IBAction func capturePhoto(_ sender: UIButton) {
    xplo.capturePhoto() {
      self.capturingLivePhotoLabel.isHidden = !(self.xplo.livePhotoMode == .on && self.xplo.isCapturingPhoto)
    }
  }
  
  // MARK: Recording Movies
  
  @IBAction func toggleMovieRecording(_ sender: UIButton) {
    guard let _ = self.xplo.movieFileOutput else {
      return
    }
    
    // Disable the Camera button until recording finishes, and disable
    // the Record button until recording starts or finishes.
    cameraButton.isEnabled = false
    recordButton.isEnabled = false
    captureModeControl.isEnabled = false
    
    xplo.toggleMovieRecording(onStartRecording: {
      self.recordButton.isEnabled = true
      self.recordButton.setTitle(NSLocalizedString("Stop", comment: "Recording button stop title"), for: [])
    }, onFinishRecording: {
      // Enable the Camera and Record buttons to let the user switch camera and start another recording.
      // Only enable the ability to change camera if the device has more than one camera.
      self.cameraButton.isEnabled = self.xplo.canToggleCamera
      self.recordButton.isEnabled = true
      self.recordButton.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), for: [])
      self.captureModeControl.isEnabled = true
    })
  }
  
  // MARK: Session
  
  @IBAction func resumeInterruptedSession(_ sender: UIButton) {
    xplo.resume() {
      if !self.xplo.isSessionRunning {
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
