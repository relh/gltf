## DirectX backend shader sources.

when not defined(windows):
  {.error: "The glTF DirectX backend requires Windows.".}

import ./shaders as shaderSources

const
  BackendName* = "DirectX"
  HasNativeRenderer* = true
  VertexEntryPoint* = "VSMain"
  FragmentEntryPoint* = "PSMain"

  PbrVertexShader* = shaderSources.PbrVertHlsl
  PbrFragmentShader* = shaderSources.PbrFragHlsl
  SkyboxVertexShader* = shaderSources.SkyboxVertHlsl
  SkyboxFragmentShader* = shaderSources.SkyboxFragHlsl
  ShadowDepthVertexShader* = shaderSources.ShadowDepthVertHlsl
  ShadowDepthFragmentShader* = shaderSources.ShadowDepthFragHlsl
