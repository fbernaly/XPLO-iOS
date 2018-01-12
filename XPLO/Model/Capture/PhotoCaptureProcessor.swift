//
//  PhotoCaptureProcessor.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
//

import AVFoundation
import Photos

class PhotoCaptureProcessor: NSObject {
  private(set) var requestedPhotoSettings: AVCapturePhotoSettings
  
  private let willCapturePhotoAnimation: () -> Void
  
  private let livePhotoCaptureHandler: (Bool) -> Void
  
  private let completionHandler: (PhotoCaptureProcessor) -> Void
  
  private var photoData: Data?
  
  private var livePhotoCompanionMovieURL: URL?
  
  init(with requestedPhotoSettings: AVCapturePhotoSettings,
       willCapturePhotoAnimation: @escaping () -> Void,
       livePhotoCaptureHandler: @escaping (Bool) -> Void,
       completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
    self.requestedPhotoSettings = requestedPhotoSettings
    self.willCapturePhotoAnimation = willCapturePhotoAnimation
    self.livePhotoCaptureHandler = livePhotoCaptureHandler
    self.completionHandler = completionHandler
  }
  
  private func didFinish() {
    if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
      if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
        do {
          try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
        } catch {
          print("Could not remove file at url: \(livePhotoCompanionMoviePath)")
        }
      }
    }
    completionHandler(self)
  }
  
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
  
  /*
   This extension includes all the delegate callbacks for AVCapturePhotoCaptureDelegate protocol
   */
  
  func photoOutput(_ output: AVCapturePhotoOutput,
                   willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    willCapturePhotoAnimation()
  }
  
  func photoOutput(_ output: AVCapturePhotoOutput,
                   willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    if resolvedSettings.livePhotoMovieDimensions.width > 0,
      resolvedSettings.livePhotoMovieDimensions.height > 0 {
      livePhotoCaptureHandler(true)
    }
  }
  
  func photoOutput(_ output: AVCapturePhotoOutput,
                   didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL,
                   resolvedSettings: AVCaptureResolvedPhotoSettings) {
    livePhotoCaptureHandler(false)
  }
  
  func photoOutput(_ output: AVCapturePhotoOutput,
                   didFinishProcessingPhoto photo: AVCapturePhoto,
                   error: Error?) {
    if let error = error {
      print("Error capturing photo: \(error)")
    } else {
      photoData = photo.fileDataRepresentation()
    }
  }
  
  func photoOutput(_ output: AVCapturePhotoOutput,
                   didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                   duration: CMTime,
                   photoDisplayTime: CMTime,
                   resolvedSettings: AVCaptureResolvedPhotoSettings,
                   error: Error?) {
    if error != nil {
      print("Error processing live photo companion movie: \(String(describing: error))")
      return
    }
    livePhotoCompanionMovieURL = outputFileURL
  }
  
  func photoOutput(_ output: AVCapturePhotoOutput,
                   didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                   error: Error?) {
    if let error = error {
      print("Error capturing photo: \(error)")
      didFinish()
      return
    }
    
    guard let photoData = photoData else {
      print("No photo data resource")
      didFinish()
      return
    }
    
    PHPhotoLibrary.shared().savePhoto(photoData: photoData,
                                      albumName: kAlbumName,
                                      requestedPhotoSettings: self.requestedPhotoSettings) { (_) in
                                        self.didFinish()
    }
  }
  
}
