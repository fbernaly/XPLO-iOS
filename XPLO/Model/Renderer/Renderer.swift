//
//  Renderer.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

import UIKit
import AVFoundation
import Metal
import MetalKit

class Renderer: NSObject {
  
  private var numberOfObjects:Int = 0
  private var commandQueue: MTLCommandQueue?
  private var renderPipelineState: MTLRenderPipelineState?
  private var positionsIn: MTLBuffer?
  private var renderParams: MTLBuffer?
  private var offsetParams: MTLBuffer?
  private var view: MTKView?
  private var camera = VirtualCamera()
  
  private var lastFrameTime: TimeInterval = 0.0
  private var angularVelocity: CGPoint = .zero
  var position: XYZ
  var rotation: XYZ
  private let mesh: Mesh
  
  private static let kVelocityScale: CGFloat = 0.005
  private static let kRotationDamping: CGFloat = 0.98
  
  init(withView view: MTKView) {
    self.position = XYZ(x: 0, y: 0, z: 0)
    self.rotation = XYZ(x: 0, y: 0, z: 0)
    self.mesh = Mesh()
    super.init()
    
    self.view = view
    self.view?.delegate = self
    self.view?.device = MTLCreateSystemDefaultDevice()
    
    initMetal()
  }
  
  func initMetal() {
    guard let device = self.view?.device,
      let library = device.makeDefaultLibrary() else {
        return
    }
    
    commandQueue = device.makeCommandQueue()
    
    let renderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
    renderPipelineStateDescriptor.vertexFunction = library.makeFunction(name: "vert")
    renderPipelineStateDescriptor.fragmentFunction = library.makeFunction(name: "frag")
    renderPipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    renderPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
    renderPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
    renderPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
    renderPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
    renderPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
    
    do {
      renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineStateDescriptor)
    } catch {
      print("Failed to create render pipeline state")
    }
  }
  
  //MARK: - Update
  
  func updateMotion() {
    let frameTime = CFAbsoluteTimeGetCurrent()
    let deltaTime: TimeInterval = frameTime - lastFrameTime
    lastFrameTime = frameTime
    
    rotation.x += Float(angularVelocity.y) * Float(deltaTime)
    rotation.y += Float(angularVelocity.x) * Float(deltaTime)
    
    angularVelocity.x *= Renderer.kRotationDamping
    angularVelocity.y *= Renderer.kRotationDamping
    
    if angularVelocity.x < 0.01 {
      angularVelocity.x = 0
    }
    
    if angularVelocity.y < 0.01 {
      angularVelocity.y = 0
    }
  }
  
  func updateCamera() {
    updateMotion()
    camera.setProjectionMatrix()
    camera.translate(x: position.x, y: position.y, z: position.z)
    camera.rotate(x: rotation.x, y: rotation.y, z: rotation.z)
    
    guard let device = view?.device else { return }
    
    renderParams = device.makeBuffer(bytes: camera.matrix, length: MemoryLayout<matrix_float4x4>.size, options: .cpuCacheModeWriteCombined)
  }
  
  func setRotationVelocity(_ velocity: CGPoint) {
    angularVelocity = CGPoint(x: velocity.x * Renderer.kVelocityScale, y: velocity.y * Renderer.kVelocityScale)
  }
  
  func update(depthData: AVDepthData, image: UIImage? = nil) {
    mesh.compute(depthData: depthData)
    var points = mesh.points
    let i = 1000
    for j in -i...i {
      let point: [Float] = [0, Float(j), mesh.offset, 1]
      points.append(contentsOf: point)
    }
    
    let z = mesh.zMax - mesh.offset
    position.z = -z - 30
    rotation.x = 0
    rotation.y = Float.pi
    rotation.z = Float.pi
    angularVelocity = .zero
    
    guard let device = view?.device else { return }
    numberOfObjects = points.count / 4
    let datasize = MemoryLayout<float4>.size * numberOfObjects
    positionsIn = device.makeBuffer(bytes: points, length: datasize, options: [])
    
    var offset = XYZ(x: 0, y: 0, z: -mesh.offset)
    offsetParams = device.makeBuffer(bytes: &offset, length: MemoryLayout<XYZ>.size, options: .cpuCacheModeWriteCombined)
  }
  
}

extension Renderer: MTKViewDelegate {
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
  
  func draw(in view: MTKView) {
    updateCamera()
    
    guard let commandBuffer = commandQueue?.makeCommandBuffer(),
      let renderPipelineState = self.renderPipelineState,
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable
      else {
        return
    }
    
    // Vertex and fragment shaders
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.15, 0.15, 0.3, 1.0)
    
    if numberOfObjects > 0,
      let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
      renderEncoder.setRenderPipelineState(renderPipelineState)
      renderEncoder.setVertexBuffer(positionsIn, offset: 0, index: 0)
      renderEncoder.setVertexBuffer(renderParams, offset: 0, index: 1)
      renderEncoder.setVertexBuffer(offsetParams, offset: 0, index: 2)
      renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: numberOfObjects)
      renderEncoder.endEncoding()
    }
    
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
}
