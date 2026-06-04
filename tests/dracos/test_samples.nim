import
  std/[algorithm, base64, json, os, strformat, strutils],
  gltf,
  gltf/dracos,
  helpers

type
  DecodeStats = object
    modelPath: string
    primitiveCount: int
    pointCount: int
    faceCount: int
    attributeCount: int

  RuntimeStats = object
    primitiveCount: int
    pointCount: int
    indexCount: int

proc findSampleModelsDir(): string =
  ## Finds the local glTF Sample Assets model directory.
  let candidates = [
    joinPath(getCurrentDir(), "..", "glTF-Sample-Assets", "Models"),
    joinPath(getCurrentDir(), "..", "..", "glTF-Sample-Assets", "Models"),
    joinPath(getCurrentDir(), "glTF-Sample-Assets", "Models"),
    "/Users/me/p/glTF-Sample-Assets/Models"
  ]
  for candidate in candidates:
    if dirExists(candidate):
      return candidate
  ""

proc componentType(value: int): ComponentType =
  ## Converts a glTF component type integer.
  case value
  of 5120:
    ByteComponent
  of 5121:
    UnsignedByteComponent
  of 5122:
    ShortComponent
  of 5123:
    UnsignedShortComponent
  of 5125:
    UnsignedIntComponent
  of 5126:
    FloatComponent
  else:
    raise newException(DracoError, &"Invalid component type {value}")

proc componentSize(componentType: ComponentType): int =
  ## Returns the byte size of one component.
  case componentType
  of ByteComponent, UnsignedByteComponent:
    1
  of ShortComponent, UnsignedShortComponent:
    2
  of UnsignedIntComponent, FloatComponent:
    4

proc componentCount(kind: string): int =
  ## Returns the component count for a glTF accessor type.
  case kind
  of "SCALAR":
    1
  of "VEC2":
    2
  of "VEC3":
    3
  of "VEC4":
    4
  of "MAT2":
    4
  of "MAT3":
    9
  of "MAT4":
    16
  else:
    raise newException(DracoError, &"Invalid accessor type {kind}")

proc optionalInt(node: JsonNode, key: string, defaultValue = 0): int =
  ## Reads an optional JSON integer field.
  if node.hasKey(key):
    node[key].getInt()
  else:
    defaultValue

proc readBuffer(modelPath: string, buffer: JsonNode): string =
  ## Reads one glTF JSON buffer payload.
  if not buffer.hasKey("uri"):
    raise newException(DracoError, "GLB sample buffers are not supported here")
  let uri = buffer["uri"].getStr()
  if uri.startsWith("data:"):
    let comma = uri.find(',')
    if comma < 0:
      raise newException(DracoError, "Invalid data URI")
    return decode(uri[comma + 1 .. ^1])
  readFile(joinPath(modelPath.parentDir(), uri))

proc readBuffers(modelPath: string, root: JsonNode): seq[string] =
  ## Reads all external or embedded buffers for a glTF JSON file.
  for buffer in root["buffers"]:
    result.add(readBuffer(modelPath, buffer))

proc bufferViewPayload(
  root: JsonNode,
  buffers: seq[string],
  viewId: int
): string =
  ## Returns the byte payload for a buffer view.
  let
    view = root["bufferViews"][viewId]
    bufferId = view["buffer"].getInt()
    offset = view.optionalInt("byteOffset")
    length = view["byteLength"].getInt()
  buffers[bufferId][offset ..< offset + length]

proc findAttribute(
  decoded: DracoDecodeResult,
  name: string
): DracoAttributeData =
  ## Finds a decoded Draco attribute by semantic name.
  for attr in decoded.attributes:
    if attr.name == name:
      return attr
  doAssert false, "Decoded Draco attribute not found: " & name

proc decodePrimitive(
  root: JsonNode,
  buffers: seq[string],
  primitive: JsonNode
): DecodeStats =
  ## Decodes one KHR_draco_mesh_compression primitive.
  if not primitive.hasKey("extensions"):
    return
  let extensions = primitive["extensions"]
  if not extensions.hasKey("KHR_draco_mesh_compression"):
    return
  let
    draco = extensions["KHR_draco_mesh_compression"]
    payload = root.bufferViewPayload(
      buffers,
      draco["bufferView"].getInt()
    )
  var specs: seq[DracoDecodeAttribute]
  for name, idNode in draco["attributes"]:
    let
      accessorId = primitive["attributes"][name].getInt()
      accessor = root["accessors"][accessorId]
      parsedType = componentType(accessor["componentType"].getInt())
    specs.add(DracoDecodeAttribute(
      name: name,
      id: idNode.getInt(),
      componentType: parsedType
    ))

  let decoded = decodeDraco(payload, specs)
  doAssert decoded.indices.len == decoded.faceCount * 3
  if primitive.hasKey("indices"):
    let indexAccessor = root["accessors"][primitive["indices"].getInt()]
    doAssert decoded.indices.len == indexAccessor["count"].getInt()

  for spec in specs:
    let
      accessorId = primitive["attributes"][spec.name].getInt()
      accessor = root["accessors"][accessorId]
      count = accessor["count"].getInt()
      components = componentCount(accessor["type"].getStr())
      attr = decoded.findAttribute(spec.name)
    doAssert decoded.pointCount == count
    doAssert attr.componentCount == components
    doAssert attr.data.len ==
      count * components * componentSize(attr.componentType)

  DecodeStats(
    primitiveCount: 1,
    pointCount: decoded.pointCount,
    faceCount: decoded.faceCount,
    attributeCount: decoded.attributes.len
  )

proc decodeModel(modelPath: string): DecodeStats =
  ## Decodes all Draco primitives in one glTF JSON model.
  let
    root = parseJson(readFile(modelPath))
    buffers = readBuffers(modelPath, root)
  result.modelPath = modelPath
  for mesh in root["meshes"]:
    for primitive in mesh["primitives"]:
      let stats = decodePrimitive(root, buffers, primitive)
      result.primitiveCount += stats.primitiveCount
      result.pointCount += stats.pointCount
      result.faceCount += stats.faceCount
      result.attributeCount += stats.attributeCount
  doAssert result.primitiveCount > 0, "Expected Draco primitives in " & modelPath
  doAssert result.pointCount > 0, "Expected Draco points in " & modelPath
  doAssert result.faceCount > 0, "Expected Draco faces in " & modelPath

proc discoverDracoModels(modelsDir: string): seq[string] =
  ## Discovers Draco glTF JSON samples.
  for path in walkDirRec(modelsDir):
    let lower = path.toLowerAscii()
    if lower.endsWith(".gltf") and "draco" in lower:
      result.add(path)
  result.sort()

proc checkKnownCounts(stats: DecodeStats) =
  ## Checks exact counts for representative sample models.
  let name = stats.modelPath.extractFilename()
  case name
  of "Box.gltf":
    doAssert stats.primitiveCount == 1
    doAssert stats.pointCount == 24
    doAssert stats.faceCount == 12
  of "CesiumMilkTruck.gltf":
    doAssert stats.primitiveCount == 4
    doAssert stats.pointCount == 4028
    doAssert stats.faceCount == 2856
  of "CarConcept.gltf":
    doAssert stats.primitiveCount == 109
  else:
    discard

proc addRuntimeStats(node: Node, stats: var RuntimeStats) =
  ## Adds runtime primitive geometry counts from a node tree.
  if node == nil:
    return
  if node.mesh != nil:
    for primitive in node.mesh.primitives:
      stats.primitiveCount += 1
      stats.pointCount += primitive.points.len
      if primitive.indices32.len > 0:
        stats.indexCount += primitive.indices32.len
      else:
        stats.indexCount += primitive.indices16.len
  for child in node.nodes:
    child.addRuntimeStats(stats)

proc runtimeStats(modelPath: string): RuntimeStats =
  ## Loads a glTF file through the public reader and returns geometry counts.
  let file = readGltfFile(modelPath)
  file.root.addRuntimeStats(result)

proc testMalformedPayloads() =
  ## Checks public decoder errors for invalid Draco headers.
  expectDracoError:
    discard decodeDraco("", @[])
  expectDracoError:
    discard decodeDraco("NOPE!\x02\x02\x01\x00\x00\x00", @[])
  expectDracoError:
    discard decodeDraco("DRACO\x02\x03\x01\x00\x00\x00", @[])
  expectDracoError:
    discard decodeDraco("DRACO\x02\x02\x00\x00\x00\x00", @[])
  expectDracoError:
    discard decodeDraco("DRACO\x02\x02\x01\xff\x00\x00", @[])

proc testDirectSamples(modelsDir: string) =
  ## Checks all JSON Draco sample payloads without rendering.
  let paths = discoverDracoModels(modelsDir)
  doAssert paths.len >= 10, "Expected Draco sample assets"
  for path in paths:
    let stats = decodeModel(path)
    stats.checkKnownCounts()
    echo &"  {path.extractFilename()}: {stats.primitiveCount} primitives, " &
      &"{stats.pointCount} points, {stats.faceCount} faces"

proc testReaderSamples(modelsDir: string) =
  ## Checks selected Draco samples through the public glTF reader.
  let samples = [
    ("Box/glTF-Draco/Box.gltf", 1, 24, 36),
    ("CesiumMilkTruck/glTF-Draco/CesiumMilkTruck.gltf", 0, 0, 0),
    ("RiggedSimple/glTF-Draco/RiggedSimple.gltf", 0, 0, 0),
    ("VirtualCity/glTF-Draco/VirtualCity.gltf", 0, 0, 0),
    ("WaterBottle/glTF-Draco/WaterBottle.gltf", 0, 0, 0)
  ]
  for (relative, primitives, points, indices) in samples:
    let
      path = joinPath(modelsDir, relative)
      stats = runtimeStats(path)
    echo &"  reader {relative.extractFilename()}: " &
      &"{stats.primitiveCount} primitives, " &
      &"{stats.pointCount} points, {stats.indexCount} indices"
    doAssert stats.pointCount > 0
    doAssert stats.indexCount > 0
    if primitives > 0:
      doAssert stats.primitiveCount == primitives
    if points > 0:
      doAssert stats.pointCount == points
    if indices > 0:
      doAssert stats.indexCount == indices

proc runSampleTests*() =
  ## Runs Draco malformed payload and sample asset tests.
  echo "Testing Draco sample assets"
  testMalformedPayloads()
  let modelsDir = findSampleModelsDir()
  if modelsDir.len == 0:
    echo "  Skipping sample assets; glTF-Sample-Assets was not found."
  else:
    testDirectSamples(modelsDir)
    testReaderSamples(modelsDir)
