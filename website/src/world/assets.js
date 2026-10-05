// Loads what export_world.gd exported from the game (public/world/): the sections' meshes and layout, the maze's
// textures, the jelly block, and the pickup models. The first section comes first; the rest can follow later.
import * as THREE from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js'

const BASE = `${import.meta.env.BASE_URL}world/`
const TEXTURE_SETS = ['floor', 'cap', 'wall', 'cliff', 'ramp', 'pen']
export const MODELS = ['clock', 'key', 'steel', 'clear_dots', 'close_traps', 'slug_pack', 'extra_slug', 'slug', 'gate',
  'chevron']

/** A mesh's geometry in plain floats, with its place in the model applied: the jelly's shaders work in the block's
 *  own space (a unit cube), but compression stores it squeezed into -1..1, with a scale on its node. */
function baked(mesh) {
  mesh.updateWorldMatrix(true, false)
  const g = new THREE.BufferGeometry()
  for (const name of ['position', 'normal']) {
    const a = mesh.geometry.getAttribute(name)
    const f = new Float32Array(a.count * 3)
    for (let i = 0; i < a.count; i++) f.set([a.getX(i), a.getY(i), a.getZ(i)], i * 3)
    g.setAttribute(name, new THREE.BufferAttribute(f, 3))
  }
  g.setIndex(mesh.geometry.getIndex())
  g.applyMatrix4(mesh.matrixWorld)
  return g
}

export class Assets {
  constructor(renderer) {
    this.renderer = renderer
    this.gltf = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder)
  }

  /** Everything the first section needs, calling `progress(0..1)` as it arrives. */
  async load(progress = () => {}) {
    let done = 0
    const parts = TEXTURE_SETS.length * 3 + 1 + MODELS.length + 3
    const tick = (x) => {
      progress(++done / parts)
      return x
    }
    const anisotropy = Math.min(8, this.renderer.capabilities.getMaxAnisotropy())
    const loader = new THREE.TextureLoader()
    const texture = (name, colour) => loader.loadAsync(`${BASE}textures/${name}.webp`).then((t) => {
      t.flipY = false // glTF's UVs
      t.wrapS = t.wrapT = THREE.RepeatWrapping
      t.colorSpace = colour ? THREE.SRGBColorSpace : THREE.NoColorSpace
      t.anisotropy = anisotropy
      return tick(t)
    })
    const sets = Promise.all(TEXTURE_SETS.map(async (set) => {
      const [albedo, normal, orm, emission] = await Promise.all([texture(`${set}_albedo`, true),
        texture(`${set}_normal`, false), texture(`${set}_orm`, false),
        set === 'pen' ? texture('pen_emission', true) : null])
      return [set, { albedo, normal, orm, emission }]
    }))
    const [textures, layout, jelly, models, first] = await Promise.all([
      sets,
      fetch(`${BASE}world.json`).then((r) => r.json()).then(tick),
      this.gltf.loadAsync(`${BASE}jelly.glb`).then(tick),
      Promise.all(MODELS.map((name) => this.gltf.loadAsync(`${BASE}models/${name}.glb`).then(tick))),
      this.gltf.loadAsync(`${BASE}section-0.glb`).then(tick),
    ])
    this.textures = Object.fromEntries(textures)
    this.layout = layout.sections
    jelly.scene.traverse((o) => { if (o.isMesh) this.jelly = baked(o) })
    this.models = Object.fromEntries(MODELS.map((name, i) => [name, models[i].scene]))
    this.first = { ...this.layout[0], scene: first.scene }
    return this
  }

  get sectionCount() { return this.layout.length }

  /** Section `i` (its layout and mesh). */
  async section(i) {
    if (i === 0) return this.first
    const gltf = await this.gltf.loadAsync(`${BASE}section-${i}.glb`)
    return { ...this.layout[i], scene: gltf.scene }
  }
}
