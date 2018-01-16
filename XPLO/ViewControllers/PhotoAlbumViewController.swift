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
  @IBOutlet weak var collectionView: UICollectionView!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  
  private var renderer:Renderer!
  private var lastScale: CGFloat = 0
  private var timer:Timer?
  private var angle: Float = 0
  private var images = [PHAsset : UIImage]()
  private var assets = [PHAsset]()
  
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
    
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
      self.fetchXploAssets()
    }
    
    wiggleButton.isSelected = true
    wiggleButtonTapped(wiggleButton)
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
    let offset = -mesh.offset - 80
    self.renderer.setVirtualCameraOffset(offset)
  }
  
  //MARK: assets
  
  func fetchXploAssets() {
    guard let album = PHPhotoLibrary.shared().findAlbum(albumName: kAlbumName) else {
      DispatchQueue.main.async {
        self.activityIndicator.stopAnimating()
        self.selectPhoto()
      }
      return
    }
    
    self.assets.removeAll()
    self.images.removeAll()
    
    let assets = PHAsset.fetchAssets(in: album, options: nil)
    assets.enumerateObjects { (asset, _, _) in
      self.assets.insert(asset, at: 0)
    }
    DispatchQueue.main.async {
      self.activityIndicator.stopAnimating()
      if self.assets.count > 1 {
        self.collectionView.reloadData()
      }
    }
    if let asset = self.assets.first {
      fetchDepth(asset: asset)
    }
  }
  
  func fetchImage(asset: PHAsset,
                  completion: @escaping (UIImage?) -> Void ) {
    if let image = self.images[asset] {
      DispatchQueue.main.async {
        completion(image)
      }
      return
    }
    
    DispatchQueue.global().async {
      let options = PHImageRequestOptions()
      options.isSynchronous = false
      options.version = .original
      options.isNetworkAccessAllowed = true
      let imageManager = PHCachingImageManager()
      let size = CGSize(width: asset.pixelWidth,
                        height: asset.pixelHeight)
      imageManager.requestImage(for: asset,
                                targetSize: size,
                                contentMode: .aspectFill,
                                options: options,
                                resultHandler: { (image, _) in
                                  if let image = image {
                                    self.images[asset] = image
                                  }
                                  DispatchQueue.main.async {
                                    completion(image)
                                  }
      })
    }
  }
  
  func fetchDepth(asset: PHAsset) {
    fetchImage(asset: asset) { (image) in
      guard let image = image else {
        return
      }
      
      let options = PHImageRequestOptions()
      options.isSynchronous = false
      options.version = .original
      options.isNetworkAccessAllowed = true
      
      PHImageManager.default().requestImageData(for: asset,
                                                options: options) { (data, _, _, _) in
                                                  guard let data = data,
                                                    let source = CGImageSourceCreateWithData(data as CFData, nil),
                                                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String : Any],
                                                    let rawValue = properties[kCGImagePropertyOrientation as String] as? UInt32,
                                                    let orientation = CGImagePropertyOrientation(rawValue: rawValue),
                                                    let depthData = AVDepthData(fromSource: source) else {
                                                      return
                                                  }
                                                  
                                                  var radians: Float = 0
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
  
}

extension PhotoAlbumViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
  
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true, completion: nil)
    if self.assets.count == 0,
      self.renderer.texture == nil {
      self.dismiss(animated: true, completion: nil)
    }
  }
  
  func imagePickerController(_ picker: UIImagePickerController,
                             didFinishPickingMediaWithInfo info: [String : Any]) {
    picker.dismiss(animated: true, completion: nil)
    guard let asset = info[UIImagePickerControllerPHAsset] as? PHAsset else {
      return
    }
    fetchDepth(asset: asset)
  }
  
}

extension PhotoAlbumViewController: UICollectionViewDataSource {
  
  func collectionView(_ collectionView: UICollectionView,
                      numberOfItemsInSection section: Int) -> Int {
    return self.assets.count
  }
  
  func collectionView(_ collectionView: UICollectionView,
                      cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    cell.layer.cornerRadius = 5
    let imageView = cell.viewWithTag(1) as? UIImageView
    self.fetchImage(asset: self.assets[indexPath.row]) { (image) in
      imageView?.image = image
    }
    return cell
  }
  
}

extension PhotoAlbumViewController: UICollectionViewDelegate {
  
  func collectionView(_ collectionView: UICollectionView,
                      didSelectItemAt indexPath: IndexPath) {
    let asset = self.assets[indexPath.row]
    fetchDepth(asset: asset)
  }
  
}
