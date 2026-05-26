## Metal backend shader stubs.
##
## The Shady source is generated so the backend can compile, but the renderer is
## intentionally left as a stub until the native Metal path is implemented.

import ./shaders as shaderSources

const
  BackendName* = "Metal"
  HasNativeRenderer* = false
  VertexEntryPoint* = "vertexMain"
  FragmentEntryPoint* = "fragmentMain"

  PbrVertexShader* = shaderSources.PbrVertMsl
  PbrFragmentShader* = shaderSources.PbrFragMsl
  SkyboxVertexShader* = shaderSources.SkyboxVertMsl
  SkyboxFragmentShader* = shaderSources.SkyboxFragMsl
  ShadowDepthVertexShader* = shaderSources.ShadowDepthVertMsl
  ShadowDepthFragmentShader* = shaderSources.ShadowDepthFragMsl
