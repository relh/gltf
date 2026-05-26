## Vulkan backend shader sources.

when not defined(windows):
  {.error: "The glTF Vulkan backend currently requires Windows.".}

import ./shaders as shaderSources

const
  BackendName* = "Vulkan"
  HasNativeRenderer* = true
  VertexEntryPoint* = "main"
  FragmentEntryPoint* = "main"

  PbrVertexShader* = shaderSources.PbrVertVulkan
  PbrFragmentShader* = shaderSources.PbrFragVulkan
  SkyboxVertexShader* = shaderSources.SkyboxVertVulkan
  SkyboxFragmentShader* = shaderSources.SkyboxFragVulkan
  ShadowDepthVertexShader* = shaderSources.ShadowDepthVertVulkan
  ShadowDepthFragmentShader* = shaderSources.ShadowDepthFragVulkan
