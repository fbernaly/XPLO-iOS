//
//  Shaders.metal
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position[[position]];
  float pointSize[[point_size]];
};

struct RenderParams
{
  float4x4 projectionMatrix;
};

struct XYZ
{
  float x;
  float y;
  float z;
};

vertex VertexOut vert(const device float4* vertices [[buffer(0)]],
                      const device RenderParams &params [[buffer(1)]],
                      const device XYZ &offset [[buffer(2)]],
                      unsigned int vid [[vertex_id]]) {
  
  VertexOut out;
  
  float4 pos = vertices[vid];
  pos.z = pos.z + offset.z;
  
  out.position = params.projectionMatrix * pos;
  out.pointSize = 5;
  
  return out;
}

fragment half4 frag(float2 pointCoord [[point_coord]], float4 pointPos [[position]]) {
  float dist = distance(float2(0.5), pointCoord);
  float intensity = (1.0 - (dist * 2.0));
  
  if (dist > 0.5) {
    discard_fragment();
  }
  
  return half4((pointPos.x / 1000.0) * intensity, (pointPos.y / 1000.0) * intensity, (pointPos.z / 1.0) * intensity, intensity);
}

