//
//  Xplo.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Keane. All rights reserved.
//

import Foundation
import AVFoundation
import Photos

enum LivePhotoMode {
  case on
  case off
}

enum CaptureMode: Int {
  case photo = 0
  case movie = 1
}

enum DepthDataDeliveryMode {
  case on
  case off
}

enum SessionSetupResult {
  case success
  case notAuthorized
  case configurationFailed
}

class Capture : NSObject {
  
  weak var previewView: PreviewView? {
    didSet {
      previewView?.session = self.session
    }
  }
  var onMovieStartRecording: (() -> Void)?
  var onMovieFinishRecording: (() -> Void)?
  var onStartRunning: (() -> Void)?
  var onSessionInterrupted: ((AVCaptureSession.InterruptionReason) -> Void)?
  var onSessionInterruptionEnded: (() -> Void)?
  let session = AVCaptureSession()
  let photoOutput = AVCapturePhotoOutput()
  private(set) var setupResult: SessionSetupResult = .success
  private(set) var movieFileOutput: AVCaptureMovieFileOutput?
  private(set) var captureMode: CaptureMode = .photo
  private(set) var livePhotoMode: LivePhotoMode = .off
  private(set) var depthDataDeliveryMode: DepthDataDeliveryMode = .off
  var isSessionRunning: Bool { return self.session.isRunning }
  var isCapturingPhoto: Bool { return self.capturingPhotoCount > 0 }
  var canToggleCamera: Bool { return self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1 }
  
  private var capturingPhotoCount: Int = 0
  private var backgroundRecordingID: UIBackgroundTaskIdentifier?
  private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
  private var videoDeviceInput: AVCaptureDeviceInput!
  private let sessionQueue = DispatchQueue(label: "session queue") // Communicate with the session and other session objects on this queue.
  private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
                                                                             mediaType: .video,
                                                                             position: .unspecified)
  
  override init() {
    super.init()
    
    /*
     Check video authorization status. Video access is required and audio
     access is optional. If audio access is denied, audio is not recorded
     during movie recording.
     */
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      // The user has previously granted access to the camera.
      break
      
    case .notDetermined:
      /*
       The user has not yet been presented with the option to grant
       video access. We suspend the session queue to delay session
       setup until the access request has completed.
       
       Note that audio access will be implicitly requested when we
       create an AVCaptureDeviceInput for audio during session setup.
       */
      sessionQueue.suspend()
      AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
        if !granted {
          self.setupResult = .notAuthorized
        }
        self.sessionQueue.resume()
      })
      
    default:
      // The user has previously denied access.
      setupResult = .notAuthorized
    }
    
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
      self.configureSession()
    }
  }
  
  func start(completion: @escaping (SessionSetupResult) -> Void) {
    sessionQueue.async {
      switch self.setupResult {
      case .success:
        // Only setup observers and start the session running if setup succeeded.
        self.addObservers()
        self.session.startRunning()
        
      default:
        break
      }
      
      DispatchQueue.main.async {
        completion(self.setupResult)
      }
    }
  }
  
  func stop() {
    sessionQueue.async {
      if self.setupResult == .success {
        self.session.stopRunning()
        self.removeObservers()
      }
    }
  }
  
  func resume(completion: @escaping () -> Void) {
    sessionQueue.async {
      /*
       The session might fail to start running, e.g., if a phone or FaceTime call is still
       using audio or video. A failure to start the session running will be communicated via
       a session runtime error notification. To avoid repeatedly failing to start the session
       running, we only try to restart the session running in the session runtime error handler
       if we aren't trying to resume the session running.
       */
      self.session.startRunning()
      DispatchQueue.main.async {
        completion()
      }
    }
  }
  
  // MARK: Rotation
  
  func rotate() {
    if let videoPreviewLayerConnection = previewView?.videoPreviewLayer.connection {
      let deviceOrientation = UIDevice.current.orientation
      guard let videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue) else {
        return
      }
      videoPreviewLayerConnection.videoOrientation = videoOrientation
    }
  }
  
  // MARK: Session
  
  private func configureSession() {
    if setupResult != .success {
      return
    }
    
    session.beginConfiguration()
    
    /*
     We do not create an AVCaptureMovieFileOutput when setting up the session because the
     AVCaptureMovieFileOutput does not support movie recording with AVCaptureSession.Preset.Photo.
     */
    session.sessionPreset = .photo
    
    // Add video input.
    do {
      var defaultVideoDevice: AVCaptureDevice?
      
      // Choose the back dual camera if available, otherwise default to a wide angle camera.
      if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
        defaultVideoDevice = dualCameraDevice
      } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
        // If the back dual camera is not available, default to the back wide angle camera.
        defaultVideoDevice = backCameraDevice
      } else if let trueDepthCameraDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
        // If front camera is not available, default to true depth camera.
        defaultVideoDevice = trueDepthCameraDevice
      } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
        /*
         In some cases where users break their phones, the back wide angle camera is not available.
         In this case, we should default to the front wide angle camera.
         */
        defaultVideoDevice = frontCameraDevice
      }
      
      let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)
      
      if session.canAddInput(videoDeviceInput) {
        session.addInput(videoDeviceInput)
        self.videoDeviceInput = videoDeviceInput
        
        DispatchQueue.main.async {
          /*
           Why are we dispatching this to the main queue?
           Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
           can only be manipulated on the main thread.
           Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
           on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
           
           Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
           handled by CameraViewController.viewWillTransition(to:with:).
           */
          let statusBarOrientation = UIApplication.shared.statusBarOrientation
          let videoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue) ?? .portrait
          self.previewView?.videoPreviewLayer.connection?.videoOrientation = videoOrientation
        }
      } else {
        print("Could not add video device input to the session")
        setupResult = .configurationFailed
        session.commitConfiguration()
        return
      }
    } catch {
      print("Could not create video device input: \(error)")
      setupResult = .configurationFailed
      session.commitConfiguration()
      return
    }
    
    // Add audio input.
    do {
      let audioDevice = AVCaptureDevice.default(for: .audio)
      let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
      
      if session.canAddInput(audioDeviceInput) {
        session.addInput(audioDeviceInput)
      } else {
        print("Could not add audio device input to the session")
      }
    } catch {
      print("Could not create audio device input: \(error)")
    }
    
    // Add photo output.
    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
      
      photoOutput.isHighResolutionCaptureEnabled = true
      photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
      photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
      livePhotoMode = photoOutput.isLivePhotoCaptureSupported ? .on : .off
      depthDataDeliveryMode = photoOutput.isDepthDataDeliverySupported ? .on : .off
      
    } else {
      print("Could not add photo output to the session")
      setupResult = .configurationFailed
      session.commitConfiguration()
      return
    }
    
    session.commitConfiguration()
  }
  
  @objc
  private func sessionWasInterrupted(notification: Notification) {
    /*
     In some scenarios we want to enable the user to resume the session running.
     For example, if music playback is initiated via control center while
     using AVCam, then the user can let AVCam resume
     the session running, which will stop music playback. Note that stopping
     music playback in control center will not automatically resume the session
     running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
     */
    if let reasonIntegerValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
      let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
      print("Capture session was interrupted with reason \(reason)")
      DispatchQueue.main.async {
        self.onSessionInterrupted?(reason)
      }
    }
  }
  
  @objc
  private func sessionInterruptionEnded(notification: Notification) {
    print("Capture session interruption ended")
    DispatchQueue.main.async {
      self.onSessionInterruptionEnded?()
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
                                           selector: #selector(subjectAreaDidChange),
                                           name: Notification.Name.AVCaptureDeviceSubjectAreaDidChange,
                                           object: videoDeviceInput.device)
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
        self.onStartRunning?()
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
  
  func focus(with focusMode: AVCaptureDevice.FocusMode,
             exposureMode: AVCaptureDevice.ExposureMode,
             at devicePoint: CGPoint,
             monitorSubjectAreaChange: Bool) {
    sessionQueue.async {
      let device = self.videoDeviceInput.device
      do {
        try device.lockForConfiguration()
        
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
      } catch {
        print("Could not lock device for configuration: \(error)")
      }
    }
  }
  
  // MARK: Configure Capture
  
  func setCaptureMode(_ captureMode: CaptureMode,
                      completion: @escaping () -> Void) {
    switch captureMode {
    case .photo:
      sessionQueue.async {
        /*
         Remove the AVCaptureMovieFileOutput from the session because movie recording is
         not supported with AVCaptureSession.Preset.Photo. Additionally, Live Photo
         capture is not supported when an AVCaptureMovieFileOutput is connected to the session.
         */
        self.session.beginConfiguration()
        if let movieFileOutput = self.movieFileOutput {
          self.session.removeOutput(movieFileOutput)
        }
        self.session.sessionPreset = .photo
        self.movieFileOutput = nil
        self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
        self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
        self.session.commitConfiguration()
        self.captureMode = .photo
        DispatchQueue.main.async {
          completion()
        }
      }
      
    case .movie:
      sessionQueue.async {
        let movieFileOutput = AVCaptureMovieFileOutput()
        if self.session.canAddOutput(movieFileOutput) {
          self.session.beginConfiguration()
          self.session.addOutput(movieFileOutput)
          self.session.sessionPreset = .high
          if let connection = movieFileOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
              connection.preferredVideoStabilizationMode = .auto
            }
          }
          self.session.commitConfiguration()
          self.movieFileOutput = movieFileOutput
          self.captureMode = .movie
          DispatchQueue.main.async {
            completion()
          }
        }
      }
    }
  }
  
  func toggleCamera(completion: @escaping () -> Void) {
    sessionQueue.async {
      let currentVideoDevice = self.videoDeviceInput.device
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
      
      let devices = self.videoDeviceDiscoverySession.devices
      var newVideoDevice: AVCaptureDevice? = nil
      
      // First, look for a device with both the preferred position and device type. Otherwise, look for a device with only the preferred position.
      if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
        newVideoDevice = device
      } else if let device = devices.first(where: { $0.position == preferredPosition }) {
        newVideoDevice = device
      }
      
      if let videoDevice = newVideoDevice {
        do {
          let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
          
          self.session.beginConfiguration()
          
          // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
          self.session.removeInput(self.videoDeviceInput)
          
          if self.session.canAddInput(videoDeviceInput) {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
            NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
            
            self.session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
          } else {
            self.session.addInput(self.videoDeviceInput)
          }
          
          if let connection = self.movieFileOutput?.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
              connection.preferredVideoStabilizationMode = .auto
            }
          }
          
          /*
           Set Live Photo capture and depth data delivery if it is supported. When changing cameras, the
           `livePhotoCaptureEnabled and depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput gets set to NO when
           a video device is disconnected from the session. After the new video device is
           added to the session, re-enable them on the AVCapturePhotoOutput if it is supported.
           */
          self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
          self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
          
          self.session.commitConfiguration()
        } catch {
          print("Error occured while creating video device input: \(error)")
        }
      }
      
      DispatchQueue.main.async {
        completion()
      }
    }
  }
  
  func toggleLivePhotoMode(completion: @escaping () -> Void) {
    sessionQueue.async {
      self.livePhotoMode = (self.livePhotoMode == .on) ? .off : .on
      DispatchQueue.main.async {
        completion()
      }
    }
  }
  
  func toggleDepthDataDeliveryMode(completion: @escaping () -> Void) {
    sessionQueue.async {
      self.depthDataDeliveryMode = (self.depthDataDeliveryMode == .on) ? .off : .on
      DispatchQueue.main.async {
        completion()
      }
    }
  }
  
  // MARK: Capture Photo
  
  func capturePhoto(completion: @escaping () -> Void) {
    /*
     Retrieve the video preview layer's video orientation on the main queue before
     entering the session queue. We do this to ensure UI elements are accessed on
     the main thread and session configuration is done on the session queue.
     */
    let videoOrientation = previewView?.videoPreviewLayer.connection?.videoOrientation
    
    sessionQueue.async {
      // Update the photo output's connection to match the video orientation of the video preview layer.
      if let photoOutputConnection = self.photoOutput.connection(with: .video) {
        photoOutputConnection.videoOrientation = videoOrientation!
      }
      
      var photoSettings = AVCapturePhotoSettings()
      // Capture HEIF photo when supported, with flash set to auto and high resolution photo enabled.
      if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
        photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
      }
      
      if self.videoDeviceInput.device.isFlashAvailable {
        photoSettings.flashMode = .auto
      }
      
      photoSettings.isHighResolutionPhotoEnabled = true
      if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
        photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
      }
      if self.livePhotoMode == .on && self.photoOutput.isLivePhotoCaptureSupported { // Live Photo capture is not supported in movie mode.
        let livePhotoMovieFileName = NSUUID().uuidString
        let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
        photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
      }
      
      if self.depthDataDeliveryMode == .on && self.photoOutput.isDepthDataDeliverySupported {
        photoSettings.isDepthDataDeliveryEnabled = true
      } else {
        photoSettings.isDepthDataDeliveryEnabled = false
      }
      
      // Use a separate object for the photo capture delegate to isolate each capture life cycle.
      let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
        DispatchQueue.main.async {
          self.previewView?.videoPreviewLayer.opacity = 0
          UIView.animate(withDuration: 0.25) {
            self.previewView?.videoPreviewLayer.opacity = 1
          }
        }
      }, livePhotoCaptureHandler: { capturing in
        /*
         Because Live Photo captures can overlap, we need to keep track of the
         number of in progress Live Photo captures to ensure that the
         Live Photo label stays visible during these captures.
         */
        self.sessionQueue.async {
          if capturing {
            self.capturingPhotoCount += 1
          } else {
            self.capturingPhotoCount -= 1
          }
          
          self.capturingPhotoCount = max(0, self.capturingPhotoCount)
          
          DispatchQueue.main.async {
            completion()
          }
        }
      }, completionHandler: { photoCaptureProcessor in
        // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
        self.sessionQueue.async {
          self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
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
  
  // MARK: Capture Video
  
  func toggleMovieRecording() {
    guard let movieFileOutput = self.movieFileOutput else {
      return
    }
    
    /*
     Retrieve the video preview layer's video orientation on the main queue
     before entering the session queue. We do this to ensure UI elements are
     accessed on the main thread and session configuration is done on the session queue.
     */
    let videoOrientation = previewView?.videoPreviewLayer.connection?.videoOrientation
    
    sessionQueue.async {
      if !movieFileOutput.isRecording {
        if UIDevice.current.isMultitaskingSupported {
          /*
           Setup background task.
           This is needed because the `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)`
           callback is not received until AVCam returns to the foreground unless you request background execution time.
           This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
           To conclude this background execution, endBackgroundTask(_:) is called in
           `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)` after the recorded file has been saved.
           */
          self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        }
        
        // Update the orientation on the movie file output video connection before starting recording.
        let movieFileOutputConnection = movieFileOutput.connection(with: .video)
        movieFileOutputConnection?.videoOrientation = videoOrientation!
        
        let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
        
        if availableVideoCodecTypes.contains(.hevc) {
          movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
        }
        
        // Start recording to a temporary file.
        let outputFileName = NSUUID().uuidString
        let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
      } else {
        movieFileOutput.stopRecording()
      }
    }
  }
  
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension Capture: AVCaptureFileOutputRecordingDelegate {
  
  func fileOutput(_ output: AVCaptureFileOutput,
                  didStartRecordingTo fileURL: URL,
                  from connections: [AVCaptureConnection]) {
    DispatchQueue.main.async {
      self.onMovieStartRecording?()
    }
  }
  
  func fileOutput(_ output: AVCaptureFileOutput,
                  didFinishRecordingTo outputFileURL: URL,
                  from connections: [AVCaptureConnection],
                  error: Error?) {
    /*
     Note that currentBackgroundRecordingID is used to end the background task
     associated with this recording. This allows a new recording to be started,
     associated with a new UIBackgroundTaskIdentifier, once the movie file output's
     `isRecording` property is back to false — which happens sometime after this method
     returns.
     
     Note: Since we use a unique file path for each recording, a new recording will
     not overwrite a recording currently being saved.
     */
    func cleanUp() {
      let path = outputFileURL.path
      if FileManager.default.fileExists(atPath: path) {
        do {
          try FileManager.default.removeItem(atPath: path)
        } catch {
          print("Could not remove file at url: \(outputFileURL)")
        }
      }
      
      if let currentBackgroundRecordingID = backgroundRecordingID {
        backgroundRecordingID = UIBackgroundTaskInvalid
        
        if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
          UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
        }
      }
      DispatchQueue.main.async {
        self.onMovieFinishRecording?()
      }
    }
    
    var success = true
    
    if error != nil {
      print("Movie file finishing error: \(String(describing: error))")
      success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
    }
    
    if success {
      // Check authorization status.
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
          // Save the movie file to the photo library and cleanup.
          PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
          }, completionHandler: { success, error in
            if !success {
              print("Could not save movie to photo library: \(String(describing: error))")
            }
            cleanUp()
          }
          )
        } else {
          cleanUp()
        }
      }
    } else {
      cleanUp()
    }
  }
  
}

// MARK: - AVCaptureDevice.DiscoverySession

private extension AVCaptureDevice.DiscoverySession {
  
  var uniqueDevicePositionsCount: Int {
    var uniqueDevicePositions: [AVCaptureDevice.Position] = []
    
    for device in devices {
      if !uniqueDevicePositions.contains(device.position) {
        uniqueDevicePositions.append(device.position)
      }
    }
    return uniqueDevicePositions.count
  }
  
}
