//
//  WMMatrixUtilities.m
//  XPLO
//
//  Tweaked by Francisco Bernal Yescas on 12/5/17.
//  Source: https://developer.apple.com/videos/play/wwdc2017/507/
//  Copyright © 2017 Apple Inc. All rights reserved.
//

@import GLKit;

#import "WMMatrixUtilities.h"

static const matrix_float4x4 matrix_ndc_float4x4 = {
  .columns[0] = { 1.0f, 0.0f, 0.0f, 0.0f },
  .columns[1] = { 0.0f, 1.0f, 0.0f, 0.0f },
  .columns[2] = { 0.0f, 0.0f, 0.5f, 0.5f },
  .columns[3] = { 0.0f, 0.0f, 0.0f, 1.0f }
};

matrix_float4x4 matrix_from_frustrum(float left, float right, float bottom, float top, float nearZ, float farZ)
{
  const float A = (right + left) / (right - left);
  const float B = (top + bottom) / (top - bottom);
  const float C = ((farZ + nearZ) / (farZ - nearZ));
  const float D = ((2.0 * farZ * nearZ) / (farZ - nearZ));
  
  const float sx = (2.0f * nearZ) / (right - left);
  const float sy = (2.0f * nearZ) / (top - bottom);
  
  matrix_float4x4 m = {
    .columns[0] = {   sx, 0.0f,     A, 0.0f },
    .columns[1] = { 0.0f,   sy,     B, 0.0f },
    .columns[2] = { 0.0f, 0.0f,     C,    D },
    .columns[3] = { 0.0f, 0.0f, -1.0f, 0.0f }
  };
  
  return matrix_multiply(matrix_ndc_float4x4, m);
}

matrix_float4x4 matrix_from_perspective(float fovY, float aspect, float nearZ, float farZ)
{
  const float hheight = nearZ * tanf(fovY * 0.5f);
  const float hwidth  = hheight * aspect;
  
  return matrix_from_frustrum(-hwidth, hwidth, -hheight, hheight, nearZ, farZ);
}

matrix_float4x4 matrix_from_translation(float x, float y, float z)
{
  matrix_float4x4 m = matrix_identity_float4x4;
  m.columns[3] = (vector_float4) { x, y, z, 1.0 };
  return m;
}

matrix_float4x4 matrix_from_rotation(float radians, float x, float y, float z)
{
  vector_float3 v = vector_normalize(((vector_float3){x, y, z}));
  float cos = cosf(radians);
  float cosp = 1.0f - cos;
  float sin = sinf(radians);
  
  matrix_float4x4 m = {
    .columns[0] = {
      cos + cosp * v.x * v.x,
      cosp * v.x * v.y + v.z * sin,
      cosp * v.x * v.z - v.y * sin,
      0.0f,
    },
    
    .columns[1] = {
      cosp * v.x * v.y - v.z * sin,
      cos + cosp * v.y * v.y,
      cosp * v.y * v.z + v.x * sin,
      0.0f,
    },
    
    .columns[2] = {
      cosp * v.x * v.z + v.y * sin,
      cosp * v.y * v.z - v.x * sin,
      cos + cosp * v.z * v.z,
      0.0f,
    },
    
    .columns[3] = { 0.0f, 0.0f, 0.0f, 1.0f }
  };
  return m;
}

matrix_float4x4 matrix_from_scale(float sx, float sy, float sz)
{
  matrix_float4x4 m = {
    .columns[0] = {  sx,   0,   0, 0 },
    .columns[1] = {   0,  sy,   0, 0 },
    .columns[2] = {   0,   0,  sz, 0 },
    .columns[3] = {   0,   0,   0, 1 }
  };
  
  return m;
}

