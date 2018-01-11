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
  private var depthStencilState: MTLDepthStencilState?
  private var pointsBuffer: MTLBuffer?
  private var indecesBuffer: MTLBuffer?
  private var renderParams: MTLBuffer?
  private var textureRotationParams: MTLBuffer?
  private var offsetParams: MTLBuffer?
  private var view: MTKView?
  private var texture: MTLTexture?
  private var camera = VirtualCamera()
  
  private var lastFrameTime: TimeInterval = 0.0
  private var angularVelocity: CGPoint = .zero
  var position: XYZ
  var rotation: XYZ
  var live = false
  let mesh: Mesh
  
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
    self.view?.preferredFramesPerSecond = 30
    self.view?.sampleCount = 4
    self.view?.depthStencilPixelFormat = .depth32Float_stencil8
    
    initMetal()
    
    setVirtualCameraOffset()
  }
  
  func initMetal() {
    guard let device = self.view?.device,
      let library = device.makeDefaultLibrary(),
      let view = self.view else {
        return
    }
    
    commandQueue = device.makeCommandQueue()
    
    let renderPipelineStateDescriptor = MTLRenderPipelineDescriptor()
    renderPipelineStateDescriptor.sampleCount = view.sampleCount
    renderPipelineStateDescriptor.vertexFunction = library.makeFunction(name: "vert")
    renderPipelineStateDescriptor.fragmentFunction = library.makeFunction(name: "frag")
    renderPipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    renderPipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
    renderPipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
    
    do {
      renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineStateDescriptor)
    } catch {
      print("Failed to create render pipeline state")
    }
    
    let depthStencilDescriptor = MTLDepthStencilDescriptor()
    depthStencilDescriptor.depthCompareFunction = .less
    depthStencilDescriptor.isDepthWriteEnabled = true
    depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    
    let datasize = MemoryLayout<UInt32>.size * mesh.indices.count
    indecesBuffer = device.makeBuffer(bytes: mesh.indices,
                                      length: datasize,
                                      options:.cpuCacheModeWriteCombined)
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
    
    renderParams = device.makeBuffer(bytes: camera.matrix,
                                     length: MemoryLayout<matrix_float4x4>.size,
                                     options: .cpuCacheModeWriteCombined)
  }
  
  func setRotationVelocity(_ velocity: CGPoint) {
    angularVelocity = CGPoint(x: velocity.x * Renderer.kVelocityScale,
                              y: velocity.y * Renderer.kVelocityScale)
  }
  
  func update(depthData: AVDepthData,
              image: UIImage,
              orientation: CGImagePropertyOrientation,
              radians: Float,
              mirroring: Bool) {
    guard let device = view?.device,
      let cgImage = image.cgImage else {
        return
    }
    
    // create texture
    let loader = MTKTextureLoader(device: device)
    guard let texture = try? loader.newTexture(cgImage: cgImage, options: nil) else {
      return
    }
    self.texture = texture
    
    // texture rotation
    let v = vector3(0, 0, Float(1.0))
    let cos = cosf(radians)
    let cosp = 1.0 - cos
    let sin = sinf(radians)
    let textureRotationMatrix: [Float] = [cos + cosp * v.x * v.x,
                                          cosp * v.x * v.y + v.z * sin,
                                          cosp * v.x * v.z - v.y * sin,
                                          0.0,
                                          
                                          cosp * v.x * v.y - v.z * sin,
                                          cos + cosp * v.y * v.y,
                                          cosp * v.y * v.z + v.x * sin,
                                          0.0,
                                          
                                          cosp * v.x * v.z + v.y * sin,
                                          cosp * v.y * v.z - v.x * sin,
                                          cos + cosp * v.z * v.z,
                                          0.0,
                                          
                                          0.0,
                                          0.0,
                                          0.0,
                                          1.0]
    textureRotationParams = device.makeBuffer(bytes: textureRotationMatrix,
                                              length: MemoryLayout<matrix_float4x4>.size,
                                              options: .cpuCacheModeWriteCombined)
    
    // create mesh
    mesh.computeDepthData(depthData,
                          orientation: orientation,
                          mirroring:  mirroring)
    let points = mesh.points
    
    // update render params
    numberOfObjects = points.count / 5
    let datasize = MemoryLayout<Float>.size * points.count
    pointsBuffer = device.makeBuffer(bytes: points,
                                     length: datasize,
                                     options: [])
    
    var offset = XYZ(x: 0, y: 0, z: -mesh.offset)
    offsetParams = device.makeBuffer(bytes: &offset,
                                     length: MemoryLayout<XYZ>.size,
                                     options: .cpuCacheModeWriteCombined)
  }
  
  func setVirtualCameraOffset(_ offset: Float = -200) {
    position.x = 0
    position.y = 0
    position.z = offset
    
    rotation.x = 0
    rotation.y = Float.pi
    rotation.z = Float.pi
    
    angularVelocity = .zero
  }
  
}

extension Renderer: MTKViewDelegate {
  
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
  
  func draw(in view: MTKView) {
    guard let commandQueue = self.commandQueue,
      let renderPipelineState = self.renderPipelineState,
      let depthStencilState = self.depthStencilState,
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
        return
    }
    
    updateCamera()
    
    renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setCullMode(self.live ? .front : .back)
    renderEncoder.setRenderPipelineState(renderPipelineState)
    if let pointsBuffer = self.pointsBuffer,
      let renderParams = self.renderParams,
      let textureRotationParams = self.textureRotationParams,
      let offsetParams = self.offsetParams,
      let indecesBuffer = self.indecesBuffer,
      let texture = self.texture {
      renderEncoder.setVertexBuffer(pointsBuffer, offset: 0, index: 0)
      renderEncoder.setVertexBuffer(renderParams, offset: 0, index: 1)
      renderEncoder.setVertexBuffer(textureRotationParams, offset: 0, index: 2)
      renderEncoder.setVertexBuffer(offsetParams, offset: 0, index: 3)
      renderEncoder.setFragmentTexture(texture, index: 0)
      renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
                                          indexCount: mesh.indices.count,
                                          indexType: .uint32,
                                          indexBuffer: indecesBuffer,
                                          indexBufferOffset: 0)
    }
    renderEncoder.endEncoding()
    
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
}
