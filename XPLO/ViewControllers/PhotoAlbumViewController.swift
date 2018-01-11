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
  @IBOutlet weak var photoAlbumButton: UIButton!
  @IBOutlet weak var wiggleButton: UIButton!
  
  private var renderer:Renderer!
  private var lastScale: CGFloat = 0
  private var isPhotoSelected = false
  private var timer:Timer?
  private var angle: Float = 0
  
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
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    wiggleButton.isSelected = true
    wiggleButtonTapped(wiggleButton)
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
      renderer.position.z += Float(scale) * 100
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
  
  @IBAction func wiggleButtonTapped(_ sender: UIButton) {
    sender.isSelected = !sender.isSelected
    sender.backgroundColor = sender.isSelected ? UIColor.white.withAlphaComponent(0.5) : UIColor.clear
    self.timer?.invalidate()
    self.setDefaultOffset()
    if sender.isSelected {
      angle = 0
      timer = Timer.scheduledTimer(timeInterval: 1.0 / 60,
                                   target: self,
                                   selector: #selector(PhotoAlbumViewController.wiggleTimer(_:)),
                                   userInfo: nil,
                                   repeats: true)
    }
  }
  
  //MARK: Timer
  
  @objc private func wiggleTimer(_ timer: Timer) {
    let kEffectRotationRate: Float = 5.0
    let kEffectRotationRadius: Float = 10
    
    angle += kEffectRotationRate;
    angle = Float(Int(angle) % 360)
    
    let theta = angle / 180.0 * .pi;
    let rx = cosf(-theta) * kEffectRotationRadius;
    let ry = sinf(-theta) * kEffectRotationRadius;
    
    renderer.position.x = rx
    renderer.position.y = ry
  }
  
  //MARK: UIImagePickerControllerDelegate
  
  func selectPhoto() {
    let imagePicker = UIImagePickerController()
    imagePicker.sourceType = .photoLibrary
    imagePicker.delegate = self
    self.present(imagePicker, animated: true, completion: nil)
  }
  
  //MARK: Update
  
  func setDefaultOffset() {
    let mesh = self.renderer.mesh
    let offset = mesh.zMin - mesh.offset - 100
    self.renderer.setVirtualCameraOffset(offset)
  }
  
}

extension PhotoAlbumViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
  
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true, completion: nil)
    if !isPhotoSelected {
      self.dismiss(animated: true, completion: nil)
    }
  }
  
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
                                                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String : Any],
                                                  let rawValue = properties[kCGImagePropertyOrientation as String] as? UInt32,
                                                  let orientation = CGImagePropertyOrientation(rawValue: rawValue),
                                                  let depthData = AVDepthData(fromSource: source) else {
                                                    return
                                                }
                                                
                                                var xplo = false
                                                PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
                                                  .enumerateObjects({ (album, _, _) in
                                                    if let title = album.localizedTitle,
                                                      title == "XPLO" {
                                                      xplo = true
                                                    }
                                                  })
                                                
                                                var radians: Float = 0
                                                if !xplo {
                                                  switch orientation {
                                                  case .down:
                                                    radians = .pi
                                                  case .right:
                                                    radians = .pi / 2
                                                  case .left:
                                                    radians = -.pi / 2
                                                  default:
                                                    radians = 0
                                                  }
                                                }
                                                
                                                self.isPhotoSelected = true
                                                self.renderer.update(depthData: depthData,
                                                                     image: image,
                                                                     orientation: orientation,
                                                                     radians: radians,
                                                                     mirroring: false,
                                                                     maxDepth: 200)
                                                self.setDefaultOffset()
    }
  }
  
}
