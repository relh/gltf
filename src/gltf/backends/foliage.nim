## Foliage shader sources generated through Shady.

import
  shady, vmath

var
  baseColorTexture*: Uniform[Sampler2d]
  baseColorFactor*: Uniform[Vec4]
  baseColorTexCoord*: Uniform[int]
  baseColorUvOffset*: Uniform[Vec2]
  baseColorUvScale*: Uniform[Vec2]
  baseColorUvRotation*: Uniform[float32]

  occlusionTexture*: Uniform[Sampler2d]
  occlusionStrength*: Uniform[float32]
  occlusionTexCoord*: Uniform[int]
  occlusionUvOffset*: Uniform[Vec2]
  occlusionUvScale*: Uniform[Vec2]
  occlusionUvRotation*: Uniform[float32]

  emissiveTexture*: Uniform[Sampler2d]
  emissiveFactor*: Uniform[Vec3]
  emissiveTexCoord*: Uniform[int]
  emissiveUvOffset*: Uniform[Vec2]
  emissiveUvScale*: Uniform[Vec2]
  emissiveUvRotation*: Uniform[float32]

  environmentMap*: Uniform[SamplerCube]
  environmentMipCount*: Uniform[float32]
  environmentMapStrength*: Uniform[float32]
  tint*: Uniform[Vec4]
  alphaCutoff*: Uniform[float32]
  ambientLightColor*: Uniform[Vec4]
  cameraPosition*: Uniform[Vec3]
  debugViewMode*: Uniform[int]
  fogColor*: Uniform[Vec4]
  fogStart*: Uniform[float32]
  fogEnd*: Uniform[float32]
  fogDensity*: Uniform[float32]
  fogStrength*: Uniform[float32]

func transformUv(uv, offset, scale: Vec2, rotation: float32): Vec2 =
  ## Applies the glTF texture transform to one UV coordinate.
  let
    c = cos(rotation)
    s = sin(rotation)
    scaled = uv * scale
  result = vec2(
    c * scaled.x + s * scaled.y,
    -s * scaled.x + c * scaled.y
  ) + offset

func selectUv(texCoord: int, uv, uv1: Vec2): Vec2 =
  ## Selects the requested glTF texture coordinate set.
  if texCoord == 1:
    uv1
  else:
    uv

proc fogAmount(worldPos: Vec3): float32 =
  ## Returns the fog blend amount for one world position.
  let
    distance = length(cameraPosition - worldPos)
    start = max(fogStart, 0.0'f)
    finish = max(fogEnd, start + 0.001'f)
    linear = clamp((distance - start) / (finish - start), 0.0'f, 1.0'f)
    dense = clamp(
      max(distance - start, 0.0'f) * max(fogDensity, 0.0'f),
      0.0'f,
      1.0'f
    )
  result = clamp(max(linear, dense) * fogStrength, 0.0'f, 1.0'f)

proc applyFog(value, worldPos: Vec3): Vec3 =
  ## Applies the configured fog color to a shaded RGB value.
  mix(value, fogColor.rgb, fogAmount(worldPos) * fogColor.a)

proc foliageEnvironmentDiffuse(): Vec3 =
  ## Samples a broad diffuse color from the current environment cube.
  let
    lod = min(environmentMipCount, 6.0'f)
    sky = textureLod(environmentMap, vec3(0.0'f, 1.0'f, 0.0'f), lod).rgb
    north = textureLod(
      environmentMap,
      normalize(vec3(0.0'f, 0.45'f, -1.0'f)),
      lod
    ).rgb
    south = textureLod(
      environmentMap,
      normalize(vec3(0.0'f, 0.45'f, 1.0'f)),
      lod
    ).rgb
    east = textureLod(
      environmentMap,
      normalize(vec3(1.0'f, 0.45'f, 0.0'f)),
      lod
    ).rgb
    west = textureLod(
      environmentMap,
      normalize(vec3(-1.0'f, 0.45'f, 0.0'f)),
      lod
    ).rgb
    ground = textureLod(environmentMap, vec3(0.0'f, -1.0'f, 0.0'f), lod).rgb
  result =
    sky * 0.36'f +
    (north + south + east + west) * 0.135'f +
    ground * 0.10'f

proc gltfFoliageFrag*(
  worldPos: Vec3,
  color: Vec4,
  normal: Vec3,
  uv: Vec2,
  uv1: Vec2,
  tangent: Vec3,
  bitangent: Vec3,
  vPosLightSpace: Vec4,
  fragColor: var Vec4
) =
  ## Shades alpha-card foliage with broad environment diffuse light.
  let
    baseColorUv = transformUv(
      selectUv(baseColorTexCoord, uv, uv1),
      baseColorUvOffset,
      baseColorUvScale,
      baseColorUvRotation
    )
    occlusionUv = transformUv(
      selectUv(occlusionTexCoord, uv, uv1),
      occlusionUvOffset,
      occlusionUvScale,
      occlusionUvRotation
    )
    emissiveUv = transformUv(
      selectUv(emissiveTexCoord, uv, uv1),
      emissiveUvOffset,
      emissiveUvScale,
      emissiveUvRotation
    )
    base = texture(baseColorTexture, baseColorUv) * baseColorFactor * color

  if base.a < alphaCutoff:
    discardFragment()

  let
    albedo = base.rgb
    ambientOcclusion =
      texture(occlusionTexture, occlusionUv).r *
      occlusionStrength
    emissiveValue =
      texture(emissiveTexture, emissiveUv).rgb *
      emissiveFactor
    ambient =
      ambientLightColor.rgb *
      ambientLightColor.a *
      ambientOcclusion
    envDiffuse =
      foliageEnvironmentDiffuse() *
      environmentMapStrength *
      ambientOcclusion
    light = ambient + envDiffuse * 0.92'f
    litColor = applyFog(albedo * light + emissiveValue, worldPos)

  if debugViewMode == 1:
    fragColor = vec4(albedo * tint.rgb, base.a * tint.a)
  elif debugViewMode == 2:
    fragColor = vec4(0.5'f, 0.75'f, 0.5'f, base.a)
  elif debugViewMode == 3:
    fragColor = vec4(
      ambientOcclusion,
      ambientOcclusion,
      ambientOcclusion,
      base.a
    )
  else:
    fragColor = vec4(litColor, base.a) * tint
