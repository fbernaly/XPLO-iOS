//
//  Shaders.metal
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#pragma mark Samplers

// Bi-linear interpolation, normalized units, clamp to edge
constexpr sampler sL( filter::linear );

#pragma mark Structures

struct VertexIn {
  packed_float3 position;
  packed_float2 texCoords;
};

struct VertexOut {
  float4 position     [[position]];
  float2 texCoords    [[user(tex_coords)]];
};

struct Params {
  float4x4 matrix;
};

struct XYZ {
  float x;
  float y;
  float z;
};

#pragma mark Texture Shader Pipeline

vertex VertexOut vert(const device VertexIn*        vertices        [[buffer(0)]],
                      const device Params           &renderParams   [[buffer(1)]],
                      const device Params           &textureParams  [[buffer(2)]],
                      const device XYZ              &offset         [[buffer(3)]],
                      unsigned int vid                              [[vertex_id]]) {
  
  const float4 position = float4(vertices[vid].position, 1.0);
  position.z = position.z - offset.z;
  
  const float4 rawTexCoords = float4(vertices[vid].texCoords, 0, 1);
  rawTexCoords.x = rawTexCoords.x - 0.5;
  rawTexCoords.y = rawTexCoords.y - 0.5;
  const float4 texCoords = textureParams.matrix * rawTexCoords;
  texCoords.x = texCoords.x + 0.5;
  texCoords.y = texCoords.y + 0.5;
  
  VertexOut out;
  out.position = renderParams.matrix * position;
  out.texCoords = float2(texCoords.x, texCoords.y);
  
  return out;
}

fragment half4 frag(VertexOut in                              [[stage_in]],
                    texture2d<float, access::sample> texture  [[texture(0)]]) {
  const float4 textureColor = texture.sample(sL, in.texCoords);
  return half4(textureColor);
}
