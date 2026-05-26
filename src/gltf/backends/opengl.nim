## OpenGL backend shader sources.

import ./shaders as shaderSources

const
  BackendName* = "OpenGL"
  HasNativeRenderer* = true
  VertexEntryPoint* = "main"
  FragmentEntryPoint* = "main"

  PbrVertexShader* = shaderSources.PbrVertSrc
  PbrFragmentShader* = shaderSources.PbrFragSrc
  SkyboxVertexShader* = shaderSources.SkyboxVertSrc
  SkyboxFragmentShader* = shaderSources.SkyboxFragSrc
  ShadowDepthVertexShader* = shaderSources.ShadowDepthVertSrc
  ShadowDepthFragmentShader* = shaderSources.ShadowDepthFragSrc
