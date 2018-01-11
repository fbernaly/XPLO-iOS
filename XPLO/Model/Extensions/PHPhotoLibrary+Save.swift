//
//  PHPhotoLibrary+Save.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 12/21/17.
//  Source: https://gist.github.com/kirillgorbushko/f090595f6207f6c93c24f30a30194aac
//  Copyright © 2017 Sean Fredrick, LLC. All rights reserved.
//

import AVFoundation
import Photos

extension PHPhotoLibrary {
  
  func savePhoto(photoData: Data,
                 albumName: String,
                 requestedPhotoSettings: AVCapturePhotoSettings,
                 completion: ((PHAsset?)->())? = nil) {
    PHPhotoLibrary.requestAuthorization { status in
      if status == .authorized {
        if let album = PHPhotoLibrary.shared().findAlbum(albumName: albumName) {
          PHPhotoLibrary.shared().saveImage(photoData: photoData, album: album, requestedPhotoSettings: requestedPhotoSettings, completion: completion)
        } else {
          PHPhotoLibrary.shared().createAlbum(albumName: albumName, completion: { (collection) in
            if let collection = collection {
              PHPhotoLibrary.shared().saveImage(photoData: photoData, album: collection, requestedPhotoSettings: requestedPhotoSettings, completion: completion)
            } else {
              completion?(nil)
            }
          })
        }
      } else {
        completion?(nil)
      }
    }
  }
  
  func savePhoto(image: UIImage,
                 albumName: String,
                 completion: ((PHAsset?)->())? = nil) {
    PHPhotoLibrary.requestAuthorization { (status) in
      if status == .authorized {
        if let album = PHPhotoLibrary.shared().findAlbum(albumName: albumName) {
          PHPhotoLibrary.shared().saveImage(image: image, album: album, completion: completion)
        } else {
          PHPhotoLibrary.shared().createAlbum(albumName: albumName, completion: { (collection) in
            if let collection = collection {
              PHPhotoLibrary.shared().saveImage(image: image, album: collection, completion: completion)
            } else {
              completion?(nil)
            }
          })
        }
      } else {
        completion?(nil)
      }
    }
  }
  
  // MARK: - Private
  
  func findAlbum(albumName: String) -> PHAssetCollection? {
    let fetchOptions = PHFetchOptions()
    fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
    let fetchResult : PHFetchResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
    guard let photoAlbum = fetchResult.firstObject else {
      return nil
    }
    return photoAlbum
  }
  
  private func createAlbum(albumName: String,
                           completion: @escaping (PHAssetCollection?)->()) {
    var albumPlaceholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges({
      let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
      albumPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
    }, completionHandler: { success, error in
      if success {
        guard let placeholder = albumPlaceholder else {
          completion(nil)
          return
        }
        let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
        guard let album = fetchResult.firstObject else {
          completion(nil)
          return
        }
        completion(album)
      } else {
        completion(nil)
      }
    })
  }
  
  private func saveImage(photoData: Data,
                         album: PHAssetCollection,
                         requestedPhotoSettings: AVCapturePhotoSettings,
                         completion:((PHAsset?)->())? = nil) {
    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges({
      let options = PHAssetResourceCreationOptions()
      let creationRequest = PHAssetCreationRequest.forAsset()
      options.uniformTypeIdentifier = requestedPhotoSettings.processedFileType.map { $0.rawValue }
      creationRequest.addResource(with: .photo, data: photoData, options: options)
      
      // add image to album
      guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
        let photoPlaceholder = creationRequest.placeholderForCreatedAsset else {
          return
      }
      let fastEnumeration = NSArray(array: [photoPlaceholder] as [PHObjectPlaceholder])
      albumChangeRequest.addAssets(fastEnumeration)
      placeholder = photoPlaceholder
    }, completionHandler: { success, error in
      if let error = error {
        print("Error occurered while saving photo to photo library: \(error)")
      }
      guard let placeholder = placeholder else {
        completion?(nil)
        return
      }
      if success {
        let assets:PHFetchResult<PHAsset> =  PHAsset.fetchAssets(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
        let asset:PHAsset? = assets.firstObject
        completion?(asset)
      } else {
        completion?(nil)
      }
    })
  }
  
  private func saveImage(image: UIImage,
                         album: PHAssetCollection,
                         completion:((PHAsset?)->())? = nil) {
    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges({
      let createAssetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
      guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
        let photoPlaceholder = createAssetRequest.placeholderForCreatedAsset else { return }
      placeholder = photoPlaceholder
      let fastEnumeration = NSArray(array: [photoPlaceholder] as [PHObjectPlaceholder])
      albumChangeRequest.addAssets(fastEnumeration)
    }, completionHandler: { success, error in
      guard let placeholder = placeholder else {
        completion?(nil)
        return
      }
      if success {
        let assets:PHFetchResult<PHAsset> =  PHAsset.fetchAssets(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
        let asset:PHAsset? = assets.firstObject
        completion?(asset)
      } else {
        completion?(nil)
      }
    })
  }
  
}
