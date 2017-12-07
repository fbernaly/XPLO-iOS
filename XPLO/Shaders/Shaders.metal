//
//  Shaders.metal
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "../Model/WiggleMe/Common/WMTypes.h"

using namespace metal;

#pragma mark Samplers

// Bi-linear interpolation, normalized units, clamp to edge
constexpr sampler sL( filter::linear );

#pragma mark Structures

typedef struct
{
  packed_float3 position;
  packed_float2 texCoords;
} texture_vertex_t;

typedef struct {
  float4 position     [[position]];
  float2 texCoords    [[user(tex_coords)]];
} ColorInOut;

#pragma mark Texture Shader Pipeline

vertex ColorInOut texture_vertex_shader(device texture_vertex_t*          vertices            [[buffer(0)]],
                                        constant WMSharedUniforms&        uniforms            [[buffer(1)]],
                                        constant WMPerInstanceUniforms*   perInstanceUniforms [[buffer(2)]],
                                        uint vid [[vertex_id]],
                                        ushort iid [[instance_id]])
{
  ColorInOut out;
  
  const float4x4 modelMatrix = perInstanceUniforms[iid].modelMatrix;
  
  const float4 in_position = float4(vertices[vid].position, 1.0);
  const float2 in_texCoords = float2(vertices[vid].texCoords);
  
  const float4x4 modelViewMatrix = uniforms.viewMatrix * modelMatrix;
  const float4 modelViewPosition = modelViewMatrix * in_position;
  out.position = uniforms.projectionMatrix * modelViewPosition;
  
  out.texCoords = in_texCoords;
  
  return out;
}

fragment half4 texture_fragment_shader(ColorInOut                       in      [[stage_in]],
                                       texture2d<float, access::sample> texture [[texture(0)]])
{
  const float4 textureColor = texture.sample(sL, in.texCoords);
  return half4(textureColor);
}

// Vertex input/output structure for passing results from vertex shader to fragment shader
struct VertexIO
{
  float4 position [[position]];
  float2 textureCoord [[user(texturecoord)]];
};

// Vertex shader for a textured quad
vertex VertexIO vertexPassThrough(device packed_float4 *pPosition  [[ buffer(0) ]],
                                  device packed_float2 *pTexCoords [[ buffer(1) ]],
                                  uint                  vid        [[ vertex_id ]])
{
  VertexIO outVertex;
  
  outVertex.position = pPosition[vid];
  outVertex.textureCoord = pTexCoords[vid];
  
  return outVertex;
}

// Fragment shader for a textured quad
fragment half4 fragmentPassThrough(VertexIO         inputFragment [[ stage_in ]],
                                   texture2d<half> inputTexture  [[ texture(0) ]],
                                   sampler         samplr        [[ sampler(0) ]])
{
  return inputTexture.sample(samplr, inputFragment.textureCoord);
}
