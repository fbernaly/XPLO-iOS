//
//  WMTypes.h
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

#ifndef WMTYPES_H
#define WMTYPES_H

#include <simd/simd.h>

#define UNIFORMS_ALIGNED 16

typedef struct __attribute__((__aligned__(UNIFORMS_ALIGNED)))
{
  matrix_float4x4 projectionMatrix;
  matrix_float4x4 viewMatrix;
} WMSharedUniforms;

typedef struct __attribute__((__aligned__(UNIFORMS_ALIGNED)))
{
  matrix_float4x4 modelMatrix;
} WMPerInstanceUniforms;

typedef struct  __attribute__((__packed__))
{
  float vx, vy, vz; // vertex position
  float tx, ty;     // texture coordinate
} WMTextureVertex;

#endif // WMTYPES_H
