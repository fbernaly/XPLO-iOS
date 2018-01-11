//
//  VirtualCamera.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Source: https://github.com/roberthein/Metal-Point-Cloud
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

import Foundation
import UIKit

class VirtualCamera: NSObject {
  
  private var projectionMatrix: Matrix4?
  private var cameraMatrix: Matrix4?
  
  override init() {
    super.init()
    
    let fov = 55.0 * Float.pi / 180.0
    let aspect = Float(UIScreen.main.bounds.size.width / UIScreen.main.bounds.size.height)
    let near: Float = 0.01
    let far: Float = 500.0
    
    projectionMatrix = Matrix4.perspectiveMatrix(fov: fov, aspect: aspect, near: near, far: far)
    setProjectionMatrix()
  }
  
  var matrix: [Float] {
    if let cameraMatrix = cameraMatrix {
      return cameraMatrix.matrix
    }
    
    return Matrix4().matrix
  }
  
  func setProjectionMatrix() {
    cameraMatrix = Matrix4()
    
    if let cameraMatrix = cameraMatrix,
      let projectionMatrix = projectionMatrix {
      self.cameraMatrix = projectionMatrix * cameraMatrix
    }
  }
  
  func translate(x: Float, y: Float, z: Float) {
    let translationMatrix = Matrix4.translationMatrix(x: x, y: y, z: z)
    
    if let cameraMatrix = cameraMatrix {
      self.cameraMatrix = translationMatrix * cameraMatrix
    }
  }
  
  func rotate(x: Float?, y: Float?, z: Float?) {
    if let x = x {
      rotateX(x)
    }
    
    if let y = y {
      rotateY(y)
    }
    
    if let z = z {
      rotateZ(z)
    }
  }
  
  private func rotateX(_ angle: Float) {
    let rotation = Matrix4.rotationMatrix(angle: angle, x: 1.0, y: 0.0, z: 0.0)
    
    if let cameraMatrix = cameraMatrix {
      self.cameraMatrix = rotation * cameraMatrix
    }
  }
  
  private func rotateY(_ angle: Float) {
    let rotation = Matrix4.rotationMatrix(angle: angle, x: 0.0, y: 1.0, z: 0.0)
    
    if let cameraMatrix = cameraMatrix {
      self.cameraMatrix = rotation * cameraMatrix
    }
  }
  
  private func rotateZ(_ angle: Float) {
    let rotation = Matrix4.rotationMatrix(angle: angle, x: 0.0, y: 0.0, z: 1.0)
    
    if let cameraMatrix = cameraMatrix {
      self.cameraMatrix = rotation * cameraMatrix
    }
  }
}
