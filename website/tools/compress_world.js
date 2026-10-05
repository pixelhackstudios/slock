// Shrinks the meshes export_world.gd writes (public/world/*.glb and models/*.glb) in place: welds shared vertices, joins each
// section's strips into one mesh per material, quantizes and meshopt-compresses them. Run it after exporting:
//   npm run world
import { readdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { NodeIO, PropertyType } from '@gltf-transform/core'
import { EXTMeshoptCompression, KHRMeshQuantization } from '@gltf-transform/extensions'
import { dedup, flatten, join, meshopt, prune, quantize, weld } from '@gltf-transform/functions'
import { MeshoptDecoder, MeshoptEncoder } from 'meshoptimizer'

const DIR = fileURLToPath(new URL('../public/world/', import.meta.url))

await MeshoptDecoder.ready
await MeshoptEncoder.ready
const io = new NodeIO()
  .registerExtensions([EXTMeshoptCompression, KHRMeshQuantization])
  .registerDependencies({ 'meshopt.decoder': MeshoptDecoder, 'meshopt.encoder': MeshoptEncoder })

const files = [...await readdir(DIR), ...(await readdir(DIR + 'models')).map((n) => 'models/' + n)]
for (const name of files.filter((n) => n.endsWith('.glb'))) {
  const path = DIR + name
  const doc = await io.read(path)
  // Godot marks its exports with an extension nothing else reads.
  doc.getRoot().listExtensionsUsed().filter((e) => e.extensionName.startsWith('GODOT')).forEach((e) => e.dispose())
  // Not materials, and keep every vertex attribute: the maze's materials are bare placeholders, told apart by name,
  // whose textures the site adds.
  const shared = [PropertyType.ACCESSOR, PropertyType.MESH, PropertyType.TEXTURE]
  await doc.transform(dedup({ propertyTypes: shared }), flatten(), join(), weld(), quantize({ quantizeNormal: 10, quantizeTexcoord: 14 }),
    prune({ keepAttributes: true }), meshopt({ encoder: MeshoptEncoder, level: 'medium' }))
  await io.write(path, doc)
  console.log(`${name}: ${doc.getRoot().listMeshes().length} meshes`)
}
