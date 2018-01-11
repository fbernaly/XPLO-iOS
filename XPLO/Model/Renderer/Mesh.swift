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
  
  let size: CGSize
  private(set) var points = [Float]()
  private(set) var indices = [UInt32]()
  private(set) var zMin = Float()
  private(set) var zMax = Float()
  private(set) var offset: Float = 0
  
  init(size: CGSize = CGSize(width: 150, height: 150)) {
    self.size = size
    super.init()
    self.computeIndices()
  }
  
  func computeDepthData(_ depthData: AVDepthData,
                        orientation: CGImagePropertyOrientation,
                        mirroring: Bool,
                        maxDepth: Float) {
    points.removeAll()
    zMin = .greatestFiniteMagnitude
    zMax = .leastNormalMagnitude
    
    var pixelBuffer: CVPixelBuffer
    if depthData.depthDataType != kCVPixelFormatType_DisparityFloat32 {
      pixelBuffer = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32).depthDataMap
    } else {
      pixelBuffer = depthData.depthDataMap
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    
    let depthMapWidth  = CVPixelBufferGetWidth(pixelBuffer)
    let depthMapHeight = CVPixelBufferGetHeight(pixelBuffer)
    let rowBytesSize = CVPixelBufferGetBytesPerRow(pixelBuffer)
    
    let width = Float(depthMapWidth) / Float(size.width)
    let height =  Float(depthMapHeight) / Float(size.height)
    offset = 0
    
    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      for j in 0..<Int(size.height) {
        for i in 0..<Int(size.width) {
          var x = Float(i) * width
          var y = Float(j) * height
          
          let pointer = baseAddress.advanced(by: Int(y) * rowBytesSize + Int(x) * MemoryLayout<Float>.size)
          let d = pointer.load(as: Float.self)
          
          // 3D point
          let z: Float = min(100.0 / d, maxDepth)
          let scale: Float = 10
          x = (x - 0.5 * Float(depthMapWidth)) / scale
          y = (y - 0.5 * Float(depthMapHeight)) / scale
          
          // orientation
          switch orientation {
          case .right:
            y = -y
            swap(&x, &y)
            
          case .down:
            x = -x
            y = -y
            
          default:
            break
          }
          
          if mirroring {
            x = -x
          }
          
          // offset
          zMin = min(zMin, z)
          zMax = max(zMax, z)
          offset += z
          
          // texture
          let tx = Float(i) / Float(size.width)
          let ty = Float(j) / Float(size.height)
          
          // buffer
          let point = [x, y, z, tx, ty]
          points.append(contentsOf: point)
        }
      }
    }
    offset = 4 * offset / Float(points.count)
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
  }
  
  func computeIndices() {
    // A complete object can be described as a degenerate strip,
    // which contains zero-area triangles that the processing software
    // or hardware will discard.
    //
    //     1 ---- 2 ---- 3 ---- 4 ---- 5
    //     |    /^|    /^|    /^|    /^|
    //     |  /   |  /   |  /   |  /   |
    //     v/     v/     v/     v/     |
    // deg 6 ---- 7 ---- 8 ---- 9 ----10 deg
    //     |    /^|    /^|    /^|    /^|
    //     |  /   |  /   |  /   |  /   |
    //     v/     v/     v/     v/     |
    //     11----12 ----13 ----14 ----15
    //
    // Indices:
    // 1, 6, 2, 7, 3, 8, 4, 9, 5, 10, (10, 6), 6, 11, 7, 12, 8, 13, 9, 14, 10, 15
    
    indices.removeAll()
    let height = Int(size.height)
    let width = Int(size.width)
    for y in 0..<(height-1) {
      // Degenerate index on non-first row
      if y > 0 {
        indices.append(UInt32(y * width))
      }
      
      // Current strip
      for x in 0..<width {
        indices.append(UInt32((y    ) * width + x))
        indices.append(UInt32((y + 1) * width + x))
      }
      
      // Degenerate index on non-last row
      if y < (height - 2) {
        indices.append(UInt32((y + 1) * width + width - 1))
      }
    }
  }
  
}
