//
//  CameraViewController.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
//

import UIKit
import MetalKit
import AVFoundation

class CameraViewController: UIViewController {
  
  @IBOutlet weak var metalView: MTKView!
  @IBOutlet weak var cameraUnavailableLabel: UILabel!
  @IBOutlet weak var albumButton: UIButton!
  @IBOutlet weak var photoButton: UIButton!
  @IBOutlet weak var cameraButton: UIButton!
  @IBOutlet weak var resumeButton: UIButton!
  @IBOutlet weak var flashButton: UIButton!
  
  let camera = Camera()
  var renderer:Renderer!
  var lastScale: CGFloat = 0
  
  // MARK: View Controller Life Cycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Disable UI. The UI is enabled if and only if the session starts running.
    albumButton.isEnabled = false
    cameraButton.isEnabled = false
    photoButton.isEnabled = false
    flashButton.isEnabled = false
    
    camera.delegate = self
    camera.setup()
    
    renderer = Renderer(withView: metalView)
    
    let panGestureRecognizer = UIPanGestureRecognizer(target: self,
                                                      action: #selector(CameraViewController.panGestureRecognized(_:)))
    view.addGestureRecognizer(panGestureRecognizer)
    
    let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self,
                                                          action: #selector(CameraViewController.pinchGestureRecognizer(_:)))
    view.addGestureRecognizer(pinchGestureRecognizer)
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    setVirtualCameraOffset()
    camera.start()
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    camera.stop()
    super.viewWillDisappear(animated)
  }
  
  // MARK: UIGestureRecognizer
  
  @objc func panGestureRecognized(_ panGestureRecognizer: UIPanGestureRecognizer) {
    let velocity = panGestureRecognizer.velocity(in: panGestureRecognizer.view)
    renderer.setRotationVelocity(velocity)
  }
  
  @objc func pinchGestureRecognizer(_ pinchGestureRecognizer: UIPinchGestureRecognizer) {
    if pinchGestureRecognizer.state == .changed {
      let scale = pinchGestureRecognizer.scale - lastScale
      renderer.position.z += Float(scale) * 100
    }
    lastScale = pinchGestureRecognizer.scale
  }
  
  // MARK: Device Configuration
  
  @IBAction func toggleCamera(_ sender: UIButton) {
    guard camera.canToggleCaptureDevice else {
      return
    }
    albumButton.isEnabled = false
    flashButton.isEnabled = false
    cameraButton.isEnabled = false
    photoButton.isEnabled = false
    camera.toggleCaptureDevice()
  }
  
  func setVirtualCameraOffset() {
    var offset: Float = -150.0
    if let videoDeviceInput = self.camera.videoDeviceInput {
      offset = videoDeviceInput.device.position == .front ? -150 : -50
    }
    renderer.setVirtualCameraOffset(offset)
  }
  
  // MARK: Capturing Photos
  
  @IBAction func capturePhoto(_ sender: UIButton) {
    camera.capturePhoto(willCapturePhoto: {
      self.albumButton.isEnabled = false
      self.metalView.alpha = 1.0
      UIView.animate(withDuration: 0.25,
                     animations: {
                      self.metalView.alpha = 0.35
      }, completion: { finished in
        if finished {
          self.metalView.alpha = 1.0
        }
      })
    }, completion: {
      self.albumButton.isEnabled = true
    })
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
  
  // MARK: Session
  
  @IBAction func resumeInterruptedSession(_ sender: UIButton) {
    camera.resume()
    self.resumeButton.isHidden = true
  }
  
}

// MARK: CameraDelegate

extension CameraViewController: CameraDelegate {
  
  func camera(_ camera: Camera, error: CameraError) {
    let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "XPLO"
    switch error {
    case .notAuthorized:
      let message = "\(appName) doesn't have permission to use the camera, please change privacy settings"
      let alertController = UIAlertController(title: appName,
                                              message: message,
                                              preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""),
                                              style: .`default`,
                                              handler: { _ in
                                                UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!,
                                                                          options: [:],
                                                                          completionHandler: nil)
      }))
      self.present(alertController, animated: true, completion: nil)
      
    case .configurationFailed:
      let message = "Unable to capture media"
      let alertController = UIAlertController(title: appName,
                                              message: message,
                                              preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                              style: .cancel,
                                              handler: nil))
      self.present(alertController, animated: true, completion: nil)
      
    case .resumeSessionFailed:
      let message = "Unable to resume"
      let alertController = UIAlertController(title: appName,
                                              message: message,
                                              preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                              style: .cancel,
                                              handler: nil))
      self.present(alertController, animated: true, completion: nil)
      
    case .unsupportedDevice:
      let message = "\(appName) doesn't support your device"
      let alertController = UIAlertController(title: appName,
                                              message: message,
                                              preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                              style: .`default`,
                                              handler: { _ in
                                                self.albumButton.isEnabled = true
                                                self.performSegue(withIdentifier: "photoAlbum", sender: self)
      }))
      self.present(alertController, animated: true, completion: nil)
    }
  }
  
  func cameraDidStartRunning(_ camera: Camera) {
    let isSessionRunning = camera.isSessionRunning
    self.albumButton.isEnabled = isSessionRunning
    self.flashButton.isEnabled = isSessionRunning
    // Only enable the ability to change camera if the device has more than one camera.
    self.cameraButton.isEnabled = isSessionRunning && self.camera.canToggleCaptureDevice
    self.photoButton.isEnabled = isSessionRunning
  }
  
  func camera(_ camera: Camera, sessionInterrupted reason: AVCaptureSession.InterruptionReason) {
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
  
  func cameraDidEndInterruption(_ camera: Camera) {
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
  
  func cameraDidRotate(_ camera: Camera) {
  }
  
  func cameraDidToggle(_ camera: Camera) {
    self.albumButton.isEnabled = true
    self.flashButton.isEnabled = true
    self.cameraButton.isEnabled = true
    self.photoButton.isEnabled = true
    self.setVirtualCameraOffset()
  }
  
  func camera(_ camera: Camera, sampleBuffer: CMSampleBuffer?, depthData: AVDepthData?) {
    if let sampleBuffer = sampleBuffer,
      let depthData = depthData,
      let image = UIImage(sampleBuffer: sampleBuffer) {
      let orientation: CGImagePropertyOrientation = .right
      var mirroring = false
      if let videoDeviceInput = self.camera.videoDeviceInput {
        mirroring = videoDeviceInput.device.position == .front
      }
      self.renderer.update(depthData: depthData,
                           image: image,
                           orientation: orientation,
                           radians: 0,
                           mirroring: mirroring,
                           maxDepth: 350.0)
    }
  }
  
}
