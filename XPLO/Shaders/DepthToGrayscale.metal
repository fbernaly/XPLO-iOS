//
//  DepthToGrayscale.metal
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/6/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct converterParameters {
  float offset;
  float range;
};

// Compute kernel
kernel void depthToGrayscale(texture2d<float, access::read>  inputTexture      [[ texture(0) ]],
                             texture2d<float, access::write> outputTexture     [[ texture(1) ]],
                             constant converterParameters& converterParameters [[ buffer(0) ]],
                             uint2 gid [[ thread_position_in_grid ]])
{
  // Ensure we don't read or write outside of the texture
  if ((gid.x >= inputTexture.get_width()) || (gid.y >= inputTexture.get_height())) {
    return;
  }
  
  float depth = inputTexture.read(gid).x;
  
  // Normalize the value between 0 and 1
  depth = (depth - converterParameters.offset) / (converterParameters.range);
  
  float4 outputColor = float4(float3(depth), 1.0);
  
  outputTexture.write(outputColor, gid);
}
