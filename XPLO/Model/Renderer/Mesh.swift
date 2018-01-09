//
//  Mesh.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

import Foundation
import AVFoundation
import Metal
import MetalKit

class Mesh: NSObject {
  
  let columns: Int
  let rows: Int
  private(set) var points = [Float]()
  private(set) var zMin: Float = .greatestFiniteMagnitude
  private(set) var zMax: Float = .leastNormalMagnitude
  var offset: Float { return (self.zMax - self.zMin) * 0.5 }
  
  init(columns: Int = 100,
       rows:Int = 100) {
    self.columns = columns
    self.rows = rows
    super.init()
  }
  
  func compute(depthData: AVDepthData) {
    points.removeAll()
    let pixelBuffer = depthData.depthDataMap
    let flag = CVPixelBufferLockFlags(rawValue: 0)
    CVPixelBufferLockBaseAddress(pixelBuffer, flag)
    
    let depthMapWidth  = CVPixelBufferGetWidth(pixelBuffer)
    let depthMapHeight = CVPixelBufferGetHeight(pixelBuffer)
    let rowBytesSize = CVPixelBufferGetBytesPerRow(pixelBuffer)
    
    let width = Float(depthMapWidth) / Float(columns)
    let height =  Float(depthMapHeight) / Float(rows)
    
    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      for j in 0..<rows {
        for i in 0..<columns {
          var x = Float(i) * width
          var y = Float(j) * height
          
          let pointer = baseAddress.advanced(by: Int(y) * rowBytesSize + Int(x) * MemoryLayout<Float>.size)
          let d = pointer.load(as: Float.self)
          
          let z = 100.0 / d
          x = (x - 0.5 * Float(depthMapWidth)) / 10
          y = -(y - 0.5 * Float(depthMapHeight)) / 10
          
          swap(&x, &y)
          
          zMin = min(zMin, z)
          zMax = max(zMax, z)
          
          let point = [x, y, z, 1.0]
          points.append(contentsOf: point)
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, flag)
  }
  
}
