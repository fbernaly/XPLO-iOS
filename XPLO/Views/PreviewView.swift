//
//  PreviewView.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/5/17.
//  Copyright © 2017 Sean Keane. All rights reserved.
//

import UIKit
import AVFoundation

class PreviewView: UIView {
  var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    guard let layer = layer as? AVCaptureVideoPreviewLayer else {
      fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
    }
    
    return layer
  }
  
  var session: AVCaptureSession? {
    get {
      return videoPreviewLayer.session
    }
    set {
      videoPreviewLayer.session = newValue
    }
  }
  
  // MARK: UIView
  
  override class var layerClass: AnyClass {
    return AVCaptureVideoPreviewLayer.self
  }
}
