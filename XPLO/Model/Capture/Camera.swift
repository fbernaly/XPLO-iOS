//
//  Camera.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
//

import AVFoundation
import Photos

let kAlbumName = "XPLO"

enum CameraError: Error {
  case notAuthorized
  case configurationFailed
  case resumeSessionFailed
  case unsupportedDevice
}

protocol CameraDelegate: NSObjectProtocol {
  func cameraDidStartRunning(_ camera: Camera)
  func camera(_ camera: Camera, sessionInterrupted reason: AVCaptureSession.InterruptionReason)
  func cameraDidEndInterruption(_ camera: Camera)
  func cameraDidRotate(_ camera: Camera)
  func camera(_ camera: Camera, sampleBuffer: CMSampleBuffer?, depthData: AVDepthData?)
  func camera(_ camera: Camera, error: CameraError)
  func cameraDidToggle(_ camera: Camera)
}

class Camera : NSObject {
  
  let session = AVCaptureSession()
  let photoOutput = AVCapturePhotoOutput()
  let videoDataOutput = AVCaptureVideoDataOutput()
  let depthDataOutput = AVCaptureDepthDataOutput()
  weak var delegate: CameraDelegate?
  
  private(set) var movieFileOutput: AVCaptureMovieFileOutput?
  private(set) var outputSynchronizer: AVCaptureDataOutputSynchronizer?
  private(set) var videoDeviceInput: AVCaptureDeviceInput?
  
  var flashMode: AVCaptureDevice.FlashMode = .auto
  var isSessionRunning: Bool { return self.session.isRunning }
  var isCapturingPhoto: Bool { return self.capturingLivePhotoCount > 0 || self.inProgressPhotoCaptureDelegates.count > 0 }
  var canToggleCaptureDevice: Bool {
    var uniqueDevicePositions: [AVCaptureDevice.Position] = []
    for device in self.videoDeviceDiscoverySession.devices {
      if !uniqueDevicePositions.contains(device.position) {
        uniqueDevicePositions.append(device.position)
      }
    }
    return uniqueDevicePositions.count > 1
  }
  
  private var capturingLivePhotoCount: Int = 0
  private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
  private var videoRecordingProcessor: VideoRecordingProcessor?
  private let sessionQueue = DispatchQueue(label: "session queue")
  private let outputQueue = DispatchQueue(label: "output queue")
  private let captureQueue = DispatchQueue(label: "capture queue",
                                           qos: .userInitiated,
                                           attributes: [],
                                           autoreleaseFrequency: .workItem)
  private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera,
                                                                                           .builtInTrueDepthCamera],
                                                                             mediaType: .video,
                                                                             position: .unspecified)
  
  // MARK: Error
  
  func sendError(_ error: CameraError?) {
    guard let error = error else {
      return
    }
    DispatchQueue.main.async {
      self.delegate?.camera(self, error: error)
    }
  }
  
  // MARK: Setup
  
  func setup() {
    /*
     Check video authorization status. Video access is required and audio
     access is optional. If audio access is denied, audio is not recorded
     during movie recording.
     */
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      // The user has previously granted access to the camera.
      configureDevice()
      
    case .notDetermined:
      /*
       The user has not yet been presented with the option to grant
       video access. We suspend the session queue to delay session
       setup until the access request has completed.
       
       Note that audio access will be implicitly requested when we
       create an AVCaptureDeviceInput for audio during session setup.
       */
      AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
        if granted {
          self.configureDevice()
        } else {
          self.sendError(.notAuthorized)
        }
      })
      
    default:
      // The user has previously denied access.
      sendError(.notAuthorized)
    }
  }
  
  private func configureDevice() {
    /*
     Setup the capture session.
     In general it is not safe to mutate an AVCaptureSession or any of its
     inputs, outputs, or connections from multiple threads at the same time.
     
     Why not do all of this on the main queue?
     Because AVCaptureSession.startRunning() is a blocking call which can
     take a long time. We dispatch session setup to the sessionQueue so
     that the main queue isn't blocked, which keeps the UI responsive.
     */
    sessionQueue.async {
      var captureDevice: AVCaptureDevice?
      // Choose the front true depth camera if available, otherwise back dual camera.
      if let trueDepthCameraDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
        captureDevice = trueDepthCameraDevice
      } else if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
        captureDevice = dualCameraDevice
      }
      
      guard let device = captureDevice else {
        print("Could not find any video device")
        self.sendError(.unsupportedDevice)
        return
      }
      
      self.configureSession(with: device) { (error) in
        self.sendError(error)
      }
    }
  }
  
  // MARK: Controls
  
  func start() {
    sessionQueue.async {
      guard let _ = self.outputSynchronizer else {
        return
      }
      self.addObservers()
      self.rotate()
      self.session.startRunning()
    }
  }
  
  func stop() {
    sessionQueue.async {
      guard let _ = self.outputSynchronizer else {
        return
      }
      self.session.stopRunning()
      self.removeObservers()
    }
  }
  
  func resume() {
    sessionQueue.async {
      /*
       The session might fail to start running, e.g., if a phone or FaceTime call is still
       using audio or video. A failure to start the session running will be communicated via
       a session runtime error notification. To avoid repeatedly failing to start the session
       running, we only try to restart the session running in the session runtime error handler
       if we aren't trying to resume the session running.
       */
      self.session.startRunning()
      if !self.isSessionRunning {
        self.sendError(.resumeSessionFailed)
      }
    }
  }
  
  // MARK: Rotation
  
  func rotate() {
    DispatchQueue.main.async {
      let interfaceOrientation = UIApplication.shared.statusBarOrientation
      if let photoOrientation = AVCaptureVideoOrientation(rawValue: interfaceOrientation.rawValue) {
        self.photoOutput.connection(with: .video)?.videoOrientation = photoOrientation
      }
      self.delegate?.cameraDidRotate(self)
    }
  }
  
  // MARK: Session
  
  private func configureSession(with device: AVCaptureDevice,
                                completion: @escaping (CameraError?) -> Void) {
    sessionQueue.async {
      self.session.beginConfiguration()
      self.session.sessionPreset = .photo
      
      // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
      if let videoDeviceInput = self.videoDeviceInput {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVCaptureDeviceSubjectAreaDidChange,
                                                  object: videoDeviceInput)
        self.session.removeInput(videoDeviceInput)
      }
      
      // Add video input.
      do {
        self.videoDeviceInput = try AVCaptureDeviceInput(device: device)
      } catch {
        print("Could not create video device input: \(error)")
        self.session.commitConfiguration()
        completion(CameraError.configurationFailed)
        return
      }
      
      guard let videoDeviceInput = self.videoDeviceInput else {
        return
      }
      
      // Add a video input
      guard self.session.canAddInput(videoDeviceInput) else {
        print("Could not add video device input to the session")
        self.session.commitConfiguration()
        completion(CameraError.configurationFailed)
        return
      }
      self.session.addInput(videoDeviceInput)
      NotificationCenter.default.addObserver(self,
                                             selector: #selector(self.subjectAreaDidChange),
                                             name: .AVCaptureDeviceSubjectAreaDidChange,
                                             object: videoDeviceInput.device)
      
      // Add audio input.
      do {
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
          let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
          if self.session.canAddInput(audioDeviceInput) {
            self.session.addInput(audioDeviceInput)
          }
        }
      } catch {
        print("Could not create audio device input: \(error)")
      }
      
      // Add photo output.
      if !self.session.outputs.contains(self.photoOutput) {
        guard self.session.canAddOutput(self.photoOutput) else {
          print("Could not add photo output to the session")
          self.session.commitConfiguration()
          completion(CameraError.configurationFailed)
          return
        }
        self.session.addOutput(self.photoOutput)
      }
      self.photoOutput.isHighResolutionCaptureEnabled = true
      self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
      
      // Add a video data output
      if !self.session.outputs.contains(self.videoDataOutput) {
        guard self.session.canAddOutput(self.videoDataOutput) else {
          print("Could not add video data output to the session")
          self.session.commitConfiguration()
          completion(CameraError.configurationFailed)
          return
        }
        self.session.addOutput(self.videoDataOutput)
      }
      self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
      
      // Add a depth data output
      if !self.session.outputs.contains(self.depthDataOutput) {
        guard self.session.canAddOutput(self.depthDataOutput) else {
          print("Could not add depth data output to the session")
          self.session.commitConfiguration()
          completion(CameraError.configurationFailed)
          return
        }
        self.session.addOutput(self.depthDataOutput)
      }
      self.depthDataOutput.isFilteringEnabled = true
      if let connection = self.depthDataOutput.connection(with: .depthData) {
        connection.isEnabled = self.photoOutput.isDepthDataDeliverySupported
      } else {
        print("No AVCaptureConnection")
      }
      
      if self.photoOutput.isDepthDataDeliverySupported {
        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        self.outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoDataOutput, self.depthDataOutput])
        self.outputSynchronizer?.setDelegate(self, queue: self.captureQueue)
      } else {
        self.outputSynchronizer = nil
      }
      
      // Cap the video framerate at the max depth framerate
      if self.photoOutput.isDepthDataDeliverySupported,
        let frameDuration = device.activeDepthDataFormat?.videoSupportedFrameRateRanges.first?.minFrameDuration {
        do {
          try device.lockForConfiguration()
          device.activeVideoMinFrameDuration = frameDuration
          device.unlockForConfiguration()
        } catch {
          print("Could not lock device for configuration: \(error)")
        }
      }
      
      self.session.commitConfiguration()
      
      self.rotate()
      
      completion(nil)
    }
  }
  
  @objc
  private func sessionWasInterrupted(notification: Notification) {
    /*
     In some scenarios we want to enable the user to resume the session running.
     For example, if music playback is initiated via control center while
     using XPLO, then the user can let XPLO resume
     the session running, which will stop music playback. Note that stopping
     music playback in control center will not automatically resume the session
     running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
     */
    if let reasonIntegerValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
      let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
      print("Capture session was interrupted with reason \(reason) - \(reason.rawValue)")
      DispatchQueue.main.async {
        self.delegate?.camera(self, sessionInterrupted: reason)
      }
    }
  }
  
  @objc
  private func sessionInterruptionEnded(notification: Notification) {
    print("Capture session interruption ended")
    DispatchQueue.main.async {
      self.delegate?.cameraDidEndInterruption(self)
    }
  }
  
  // MARK: KVO
  
  private func addObservers() {
    session.addObserver(self,
                        forKeyPath: "running",
                        options: NSKeyValueObservingOptions.new,
                        context: nil)
    
    /*
     A session can only run when the app is full screen. It will be interrupted
     in a multi-app layout, introduced in iOS 9, see also the documentation of
     AVCaptureSessionInterruptionReason. Add observers to handle these session
     interruptions and show a preview is paused message. See the documentation
     of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
     */
    
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(sessionWasInterrupted),
                                           name: .AVCaptureSessionWasInterrupted,
                                           object: session)
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(sessionInterruptionEnded),
                                           name: .AVCaptureSessionInterruptionEnded,
                                           object: session)
  }
  
  private func removeObservers() {
    NotificationCenter.default.removeObserver(self)
    session.removeObserver(self, forKeyPath: "running", context: nil)
  }
  
  override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey: Any]?,
                             context: UnsafeMutableRawPointer?) {
    if keyPath == "running" {
      DispatchQueue.main.async {
        self.delegate?.cameraDidStartRunning(self)
      }
    } else {
      super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
  }
  
  // MARK: Focus
  
  @objc
  private func subjectAreaDidChange(notification: NSNotification) {
    let devicePoint = CGPoint(x: 0.5, y: 0.5)
    focus(with: .continuousAutoFocus,
          exposureMode: .continuousAutoExposure,
          at: devicePoint,
          monitorSubjectAreaChange: false)
  }
  
  private func focus(with focusMode: AVCaptureDevice.FocusMode,
                     exposureMode: AVCaptureDevice.ExposureMode,
                     at devicePoint: CGPoint,
                     monitorSubjectAreaChange: Bool) {
    sessionQueue.async {
      guard let device = self.videoDeviceInput?.device else { return }
      do {
        try device.lockForConfiguration()
      } catch {
        print("Could not lock device for configuration: \(error)")
        return
      }
      
      /*
       Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
       Call set(Focus/Exposure)Mode() to apply the new point of interest.
       */
      if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
        device.focusPointOfInterest = devicePoint
        device.focusMode = focusMode
      }
      
      if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
        device.exposurePointOfInterest = devicePoint
        device.exposureMode = exposureMode
      }
      
      device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
      device.unlockForConfiguration()
    }
  }
  
  // MARK: Toggle Capture Device
  
  func toggleCaptureDevice() {
    guard canToggleCaptureDevice,
      let videoDeviceInput = self.videoDeviceInput else {
        return
    }
    
    let currentVideoDevice = videoDeviceInput.device
    let currentPosition = currentVideoDevice.position
    let preferredPosition: AVCaptureDevice.Position
    let preferredDeviceType: AVCaptureDevice.DeviceType
    
    switch currentPosition {
    case .unspecified, .front:
      preferredPosition = .back
      preferredDeviceType = .builtInDualCamera
      
    case .back:
      preferredPosition = .front
      preferredDeviceType = .builtInTrueDepthCamera
    }
    
    // Look for a device with both the preferred position and device type.
    guard let device = self.videoDeviceDiscoverySession
      .devices
      .first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) else {
        print("Error occured while creating video device input")
        self.sendError(.unsupportedDevice)
        return
    }
    
    self.configureSession(with: device) { (error) in
      if let error = error {
        self.sendError(error)
      } else {
        DispatchQueue.main.async {
          self.delegate?.cameraDidToggle(self)
        }
      }
    }
  }
  
  // MARK: Capture Photo
  
  func capturePhoto(willCapturePhoto: (() -> Void)? = nil,
                    completion: (() -> Void)? = nil) {
    sessionQueue.async {
      var photoSettings = AVCapturePhotoSettings()
      // Capture HEIF photo when supported, with flash set to auto and high resolution photo enabled.
      if  self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
        photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      }
      
      if let videoDeviceInput = self.videoDeviceInput,
        videoDeviceInput.device.isFlashAvailable {
        photoSettings.flashMode = self.flashMode
      }
      
      photoSettings.isHighResolutionPhotoEnabled = true
      if let formatType = photoSettings.__availablePreviewPhotoPixelFormatTypes.first {
        photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: formatType]
      }
      
      photoSettings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
      photoSettings.embedsDepthDataInPhoto = self.photoOutput.isDepthDataDeliverySupported
      
      // Use a separate object for the photo capture delegate to isolate each capture life cycle.
      let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
        DispatchQueue.main.async {
          willCapturePhoto?()
        }
      }, livePhotoCaptureHandler: { capturing in
        /*
         Because Live Photo captures can overlap, we need to keep track of the
         number of in progress Live Photo captures to ensure that the
         Live Photo label stays visible during these captures.
         */
        self.sessionQueue.async {
          if capturing {
            self.capturingLivePhotoCount += 1
          } else {
            self.capturingLivePhotoCount -= 1
          }
          
          self.capturingLivePhotoCount = max(0, self.capturingLivePhotoCount)
        }
      }, completionHandler: { photoCaptureProcessor in
        // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
        self.sessionQueue.async {
          self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
          
          if self.inProgressPhotoCaptureDelegates.count == 0 {
            DispatchQueue.main.async {
              completion?()
            }
          }
        }
      })
      
      /*
       The Photo Output keeps a weak reference to the photo capture delegate so
       we store it in an array to maintain a strong reference to this object
       until the capture is completed.
       */
      self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
      self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
    }
  }
  
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension Camera: AVCaptureDataOutputSynchronizerDelegate {
  
  func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                              didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
    var depthData: AVDepthData? = nil
    var sampleBuffer: CMSampleBuffer? = nil
    
    if let syncedDepthData: AVCaptureSynchronizedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData {
      if !syncedDepthData.depthDataWasDropped {
        depthData = syncedDepthData.depthData
      }
    }
    
    if let syncedVideoData: AVCaptureSynchronizedSampleBufferData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData {
      if !syncedVideoData.sampleBufferWasDropped {
        sampleBuffer = syncedVideoData.sampleBuffer
      }
    }
    outputQueue.async {
      self.delegate?.camera(self, sampleBuffer: sampleBuffer, depthData: depthData)
    }
  }
  
}
