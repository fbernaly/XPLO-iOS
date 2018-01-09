//
//  PhotoAlbumViewController.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

import UIKit
import MetalKit
import Photos

class PhotoAlbumViewController: UIViewController {
  
  @IBOutlet weak var metalView: MTKView!
  
  var renderer:Renderer!
  var lastScale: CGFloat = 0
  var isPhotoSelected = false
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    renderer = Renderer(withView: metalView)
    
    PHPhotoLibrary.requestAuthorization { (_) in }
    
    let panGestureRecognizer = UIPanGestureRecognizer(target: self,
                                                      action: #selector(PhotoAlbumViewController.panGestureRecognized(_:)))
    view.addGestureRecognizer(panGestureRecognizer)
    
    let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self,
                                                          action: #selector(PhotoAlbumViewController.pinchGestureRecognizer(_:)))
    view.addGestureRecognizer(pinchGestureRecognizer)
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    
    if !isPhotoSelected {
      selectPhoto()
    }
  }
  
  override var prefersStatusBarHidden: Bool {
    return true
  }
  
  //MARK: UIGestureRecognizer
  
  @objc func panGestureRecognized(_ panGestureRecognizer: UIPanGestureRecognizer) {
    let velocity = panGestureRecognizer.velocity(in: panGestureRecognizer.view)
    renderer.setRotationVelocity(velocity)
  }
  
  @objc func pinchGestureRecognizer(_ pinchGestureRecognizer: UIPinchGestureRecognizer) {
    if pinchGestureRecognizer.state == .changed {
      let scale = pinchGestureRecognizer.scale - lastScale
      renderer.position.z += Float(scale) * 10
    }
    lastScale = pinchGestureRecognizer.scale
  }
  
  //MARK: Buttons
  
  @IBAction func backButtonTapper(_ sender: UIButton) {
    self.dismiss(animated: true, completion: nil)
  }
  
  @IBAction func photoAlbumButtonTapped(_ sender: UIButton) {
    self.selectPhoto()
  }
  
  //MARK: UIImagePickerControllerDelegate
  
  func selectPhoto() {
    let imagePicker = UIImagePickerController()
    imagePicker.sourceType = .photoLibrary
    imagePicker.delegate = self
    self.present(imagePicker, animated: true, completion: nil)
  }
  
}

extension PhotoAlbumViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
  
  func imagePickerController(_ picker: UIImagePickerController,
                             didFinishPickingMediaWithInfo info: [String : Any]) {
    picker.dismiss(animated: true, completion: nil)
    
    guard let asset = info[UIImagePickerControllerPHAsset] as? PHAsset,
      let image =  info[UIImagePickerControllerOriginalImage] as? UIImage else {
        return
    }
    
    let imageRequestOptions = PHImageRequestOptions()
    imageRequestOptions.isSynchronous = true
    imageRequestOptions.version = .original
    imageRequestOptions.isNetworkAccessAllowed = true
    
    PHImageManager.default().requestImageData(for: asset,
                                              options: imageRequestOptions) { (data, _, _, _) in
                                                guard let data = data,
                                                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                                                  let depthData = self.depthData(source: source) else {
                                                    return
                                                }
                                                self.isPhotoSelected = true
                                                self.renderer.update(depthData: depthData, image: image)
    }
  }
  
  func depthData(source: CGImageSource) -> AVDepthData? {
    guard let auxDataInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0,
                                                                      kCGImageAuxiliaryDataTypeDisparity) as? [AnyHashable : Any] else {
                                                                        return nil
    }
    
    var depthData: AVDepthData
    
    do {
      depthData = try AVDepthData(fromDictionaryRepresentation: auxDataInfo)
    } catch {
      return nil
    }
    
    if depthData.depthDataType != kCVPixelFormatType_DisparityFloat32 {
      depthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
    }
    
    return depthData
  }
  
}
