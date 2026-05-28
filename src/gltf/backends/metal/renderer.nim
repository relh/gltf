import
  chroma, pixie, vmath, windy,
  ../../common,
  ./common,
  ../shaders as shaderSources

when defined(macosx):
  import pkg/metal4

const
  VertexEntryPoint* = "vertexMain"
  FragmentEntryPoint* = "fragmentMain"

  PbrVertexShader* = shaderSources.PbrVertMsl
  PbrFragmentShader* = shaderSources.PbrFragMsl
  SkyboxVertexShader* = shaderSources.SkyboxVertMsl
  SkyboxFragmentShader* = shaderSources.SkyboxFragMsl
  ShadowDepthVertexShader* = shaderSources.ShadowDepthVertMsl
  ShadowDepthFragmentShader* = shaderSources.ShadowDepthFragMsl

type
  MetalVertex {.packed.} = object
    position: array[3, float32]
    color: array[4, float32]
    normal: array[3, float32]
    uv: array[2, float32]
    tangent: array[4, float32]
    joints: array[4, uint16]
    weights: array[4, float32]
    uv1: array[2, float32]

  Renderer* = ref object
    window*: Window
    size*: IVec2
    clearColor*: Color
    when defined(macosx):
      ctx*: MetalContext

proc clampSize(size: IVec2): IVec2 =
  ivec2(max(1'i32, size.x), max(1'i32, size.y))

proc toRgbx(value: Color): ColorRGBX =
  proc channel(v: float32): uint8 =
    var c = v
    if c < 0:
      c = 0
    elif c > 1:
      c = 1
    uint8(c * 255 + 0.5)
  rgbx(channel(value.r), channel(value.g), channel(value.b), channel(value.a))

when defined(macosx):
  proc toMetalColor(value: Color): MTLClearColor =
    MTLClearColor(
      red: value.r.float64,
      green: value.g.float64,
      blue: value.b.float64,
      alpha: value.a.float64
    )

proc copyVec2(dst: var array[2, float32], src: Vec2) =
  dst[0] = src.x
  dst[1] = src.y

proc copyVec3(dst: var array[3, float32], src: Vec3) =
  dst[0] = src.x
  dst[1] = src.y
  dst[2] = src.z

proc copyVec4(dst: var array[4, float32], src: Vec4) =
  dst[0] = src.x
  dst[1] = src.y
  dst[2] = src.z
  dst[3] = src.w

proc copyColor(dst: var array[4, float32], src: ColorRGBX) =
  dst[0] = src.r.float32 / 255.0
  dst[1] = src.g.float32 / 255.0
  dst[2] = src.b.float32 / 255.0
  dst[3] = src.a.float32 / 255.0

proc buildVertices(primitive: Primitive): seq[MetalVertex] =
  result.setLen(primitive.points.len)
  for i in 0 ..< result.len:
    result[i].position.copyVec3(primitive.points[i])
    if i < primitive.colors.len:
      result[i].color.copyColor(primitive.colors[i])
    else:
      result[i].color = [1.0'f32, 1.0, 1.0, 1.0]
    if i < primitive.normals.len:
      result[i].normal.copyVec3(primitive.normals[i])
    if i < primitive.uvs.len:
      result[i].uv.copyVec2(primitive.uvs[i])
    if i < primitive.tangents.len:
      result[i].tangent.copyVec4(primitive.tangents[i])
    if i < primitive.jointIds.len:
      result[i].joints = primitive.jointIds[i]
    if i < primitive.jointWeights.len:
      result[i].weights.copyVec4(primitive.jointWeights[i])
    if i < primitive.uvs1.len:
      result[i].uv1.copyVec2(primitive.uvs1[i])

when defined(macosx):
  proc uploadBuffer[T](
    renderer: Renderer,
    values: openArray[T]
  ): MTLBuffer =
    if values.len == 0:
      return 0.MTLBuffer
    result = renderer.ctx.device.newBufferWithBytes(
      unsafeAddr values[0],
      uint(values.len * sizeof(T)),
      0
    )
    checkNil(result, "Could not create a Metal buffer")

  proc uploadImage(renderer: Renderer, image: Image): MetalTexture =
    if image == nil or image.width <= 0 or image.height <= 0:
      return nil

    result = MetalTexture(width: image.width, height: image.height)
    let descriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
      MTLPixelFormatRGBA8Unorm,
      image.width.uint,
      image.height.uint,
      false
    )
    descriptor.setUsage(MTLTextureUsageShaderRead)
    result.texture = renderer.ctx.device.newTextureWithDescriptor(descriptor)
    checkNil(result.texture, "Could not create a Metal texture")
    result.texture.replaceRegion(
      MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(
          width: image.width.uint,
          height: image.height.uint,
          depth: 1
        )
      ),
      0,
      unsafeAddr image.data[0],
      uint(image.width * 4)
    )

proc ensurePrimitive(renderer: Renderer, primitive: Primitive) =
  if primitive == nil:
    return
  if primitive.data == nil:
    primitive.data = PrimitiveData()
  if primitive.data.geometryVersion == primitive.geometryVersion:
    return

  let vertices = primitive.buildVertices()
  primitive.data.vertexCount = vertices.len
  primitive.data.uses32BitIndices = primitive.indices32.len > 0
  primitive.data.indexCount =
    if primitive.indices32.len > 0:
      primitive.indices32.len
    else:
      primitive.indices16.len
  primitive.data.geometryVersion = primitive.geometryVersion

  when defined(macosx):
    primitive.data.vertexBuffer = renderer.uploadBuffer(vertices)
    if primitive.indices32.len > 0:
      primitive.data.indexBuffer = renderer.uploadBuffer(primitive.indices32)
    else:
      primitive.data.indexBuffer = renderer.uploadBuffer(primitive.indices16)
  else:
    discard renderer

proc ensureMaterial(renderer: Renderer, material: Material) =
  if material == nil:
    return
  if material.data == nil:
    material.data = MaterialData()
  if material.data.materialVersion == material.materialVersion:
    return

  material.data.materialVersion = material.materialVersion
  when defined(macosx):
    material.data.baseColor = renderer.uploadImage(material.baseColor)
    material.data.metallicRoughness =
      renderer.uploadImage(material.metallicRoughness)
    material.data.normal = renderer.uploadImage(material.normal)
    material.data.occlusion = renderer.uploadImage(material.occlusion)
    material.data.emissive = renderer.uploadImage(material.emissive)
  else:
    discard renderer

proc prepareNode(renderer: Renderer, node: Node) =
  if node == nil:
    return
  if node.mesh != nil:
    for primitive in node.mesh.primitives:
      renderer.ensurePrimitive(primitive)
      renderer.ensureMaterial(primitive.material)
  for child in node.nodes:
    renderer.prepareNode(child)

proc newRenderer*(window: Window): Renderer =
  result = Renderer(
    window: window,
    size: clampSize(window.size),
    clearColor: color(0, 0, 0, 1)
  )
  when defined(macosx):
    result.ctx = newMetalContext(window)

proc beginFrame*(renderer: Renderer; window: Window; size: IVec2) =
  renderer.window = window
  renderer.size = clampSize(size)
  when defined(macosx):
    renderer.ctx.window = window
    renderer.ctx.updateDrawableSize()

proc clearScreen*(renderer: Renderer; color: ColorRGBX) =
  renderer.clearColor = color.color

proc clearScreen*(renderer: Renderer; color: Color) =
  renderer.clearColor = color

proc render*(renderer: Renderer; node: Node; params: RenderParams) =
  if node != nil:
    renderer.prepareNode(node)
  discard params

proc render*(renderer: Renderer; file: GltfFile; params: RenderParams) =
  if file != nil:
    if file.data == nil:
      file.data = GltfFileData()
    file.data.sceneVersion = file.sceneVersion
    renderer.render(file.root, params)

proc endFrame*(renderer: Renderer) =
  when defined(macosx):
    renderer.ctx.window = renderer.window
    let drawable = renderer.ctx.currentDrawable()
    if drawable.isNil:
      return

    let
      commandBuffer = renderer.ctx.newCommandBuffer()
      renderPass = renderer.ctx.clearPass(
        drawable,
        renderer.clearColor.toMetalColor()
      )
      encoder = commandBuffer.renderCommandEncoderWithDescriptor(renderPass)
    checkNil(encoder, "Could not create a Metal render encoder")
    encoder.setViewport(
      MTLViewport(
        originX: 0,
        originY: 0,
        width: renderer.ctx.layer.drawableSize().width,
        height: renderer.ctx.layer.drawableSize().height,
        znear: 0,
        zfar: 1
      )
    )
    encoder.setCullMode(MTLCullModeBack)
    encoder.setFrontFacingWinding(MTLWindingCounterClockwise)
    encoder.endEncoding()
    commandBuffer.presentDrawable(drawable)
    commandBuffer.commit()
  else:
    discard renderer

proc captureScreenshot*(renderer: Renderer): Image =
  result = newImage(renderer.size.x.int, renderer.size.y.int)
  result.fill(renderer.clearColor.toRgbx())

proc release*(renderer: Renderer; node: Node) =
  discard renderer
  if node == nil:
    return
  if node.mesh != nil:
    for primitive in node.mesh.primitives:
      primitive.data = nil
      if primitive.material != nil:
        primitive.material.data = nil
  for child in node.nodes:
    renderer.release(child)

proc shutdown*(renderer: Renderer) =
  discard renderer
