//
//  VideoRecordingProcessor.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
//

import AVFoundation
import Photos

class VideoRecordingProcessor: NSObject {
  
  var onStartRecording: () -> Void
  var onFinishRecording: () -> Void
  private var backgroundRecordingID: UIBackgroundTaskIdentifier?
  
  init(withID backgroundRecordingID: UIBackgroundTaskIdentifier?,
       onStartRecording: @escaping () -> Void,
       onFinishRecording: @escaping () -> Void) {
    self.backgroundRecordingID = backgroundRecordingID
    self.onStartRecording = onStartRecording
    self.onFinishRecording = onFinishRecording
    super.init()
  }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecordingProcessor: AVCaptureFileOutputRecordingDelegate {
  
  func fileOutput(_ output: AVCaptureFileOutput,
                  didStartRecordingTo fileURL: URL,
                  from connections: [AVCaptureConnection]) {
    DispatchQueue.main.async {
      self.onStartRecording()
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
        self.onFinishRecording()
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
