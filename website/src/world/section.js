// One section of the course, dressed the way section.gd dresses it: the maze mesh with its textures, the pellets,
// the pickups, the gate and the booster chevrons, and its swurms.
import * as THREE from 'three'
import { JELLY, Jelly } from './jelly.js'
import { ORBS, gateBarrierMaterial, mazeMaterial, orbMaterial, orbOutlineMaterial, outlineModel } from './look.js'
import { Swurm } from './swurm.js'

export const VOID = 0
export const FLOOR = 1
export const WALL = 2
export const LEVEL = { MAIN: 0, LOW: 1, CLIMB: 2, SIDE: 3 }

const PICKUP_BOB = 0.12
const LIFE_SIZE = 0.4
const POWERUP_MODELS = {
  steel: 'steel', clear_dots: 'clear_dots', close_traps: 'close_traps', slug_pack: 'slug_pack',
  extra_slug: 'extra_slug', clock: 'clock', key: 'key',
}

export class SectionView extends THREE.Group {
  /** `far`: a section only ever seen from a distance: simpler pellets and swurms, and no outlines on its models. */
  constructor(data, assets, frame, { far = false } = {}) {
    super()
    Object.assign(this, data) // the layout export_world.gd wrote (see world.json)
    this.frame = frame
    this.pickups = new Map() // "col,row" -> [node, home, phase]
    this.slots = new Map()   // "col,row" -> [orb batch, ring batch, index]

    const maze = data.scene
    const looks = {}
    maze.traverse((o) => {
      if (!o.isMesh) return
      const set = o.material.name
      looks[set] ??= mazeMaterial(assets.textures[set])
      o.material = looks[set]
      o.castShadow = o.receiveShadow = true
    })
    this.add(maze)
    this._addOrbs(far ? [10, 6] : [16, 10])
    for (const item of data.items) {
      if (item.kind in POWERUP_MODELS) {
        this._addPickup(item, assets.models[POWERUP_MODELS[item.kind]].clone(true), !far)
      } else if (item.kind === 'life') this._addLife(item, assets)
    }
    this._addGate(assets.models.gate, !far)
    this._addChevrons(assets.models.chevron, data.chevrons)
    this.swurms = []
    const homes = data.swurmHomes.length ? data.swurmHomes : this._crawlableTiles()
    for (let k = 0; k < data.swurms; k++) {
      const swurm = new Swurm(this, homes[k % homes.length], assets.jelly, frame, far)
      this.swurms.push(swurm)
      this.add(swurm)
    }
  }

  key(col, row) { return `${col},${row}` }

  tileAt(col, row) {
    if (col < 0 || col >= this.width || row < 0 || row >= this.length) return VOID
    return this.tiles[col][row]
  }

  levelAt(col, row) { return this.levels[col]?.[row] ?? LEVEL.MAIN }

  rowZ(row) { return this.nearEdge - (row - 0.5) * this.tile }

  /** Floor centre of a tile, in world space. */
  tileCentre(col, row) {
    const f = this.floors[col][row]
    return new THREE.Vector3((col - this.centre) * this.tile, (f[0] + f[1] + f[2] + f[3]) / 4, this.rowZ(row))
  }

  /** The tile under a world position. */
  tileUnder(p) {
    return [Math.round(p.x / this.tile) + this.centre, Math.round((this.nearEdge - p.z) / this.tile + 0.5)]
  }

  /** Floor height under a world position (follows the ramps). */
  floorAt(p) {
    const [col, row] = this.tileUnder(p)
    const f = this.floors[THREE.MathUtils.clamp(col, 0, this.width - 1)][THREE.MathUtils.clamp(row, 0, this.length - 1)]
    const c = this.tileCentre(...this.tileUnder(p))
    const u = THREE.MathUtils.clamp((p.x - c.x) / this.tile + 0.5, 0, 1)  // left to right
    const v = THREE.MathUtils.clamp((c.z - p.z) / this.tile + 0.5, 0, 1)  // near to far
    const near = f[0] + (f[1] - f[0]) * u
    const far = f[3] + (f[2] - f[3]) * u
    return near + (far - near) * v
  }

  /** Tiles swurms may crawl on: maze floor, away from its outer edge and the entry and exit. */
  isCrawlable(col, row) {
    return this.tileAt(col, row) === FLOOR && this.levelAt(col, row) === LEVEL.MAIN && col > this.mazeLeft &&
      col < this.mazeRight && row > this.mazeStart && row < this.length - 1
  }

  _crawlableTiles() {
    const out = []
    for (let col = 0; col < this.width; col++) {
      for (let row = this.mazeStart + 5; row < this.length - 2; row++) if (this.isCrawlable(col, row)) out.push([col, row])
    }
    return out
  }

  // The pellets: one batch per look, each orb bobbing on the GPU, with a black ring round it. `segments`: the
  // spheres' detail (around, down).
  _addOrbs(segments) {
    const clock = this.frame.time
    for (const kind of ['pellet', 'gold', 'power']) {
      const items = this.items.filter((i) => i.kind === kind)
      if (!items.length) continue
      const look = ORBS[kind]
      const radius = look.radius * this.tile
      const half = radius * 1.6
      const sphere = new THREE.InstancedMesh(new THREE.SphereGeometry(radius, ...segments), orbMaterial(look, clock),
        items.length)
      const ring = new THREE.InstancedMesh(new THREE.PlaneGeometry(half * 2, half * 2), orbOutlineMaterial(radius, half,
        clock, this.frame), items.length)
      const bob = new Float32Array(items.length * 3)
      const m = new THREE.Matrix4()
      items.forEach((item, n) => {
        m.makeTranslation(...item.at)
        sphere.setMatrixAt(n, m)
        ring.setMatrixAt(n, m)
        const pellet = kind !== 'power'
        bob.set([Math.random() * (pellet ? 100 : 10), pellet ? 1.2 + Math.random() * 1.2 : 3, look.bob * this.tile], n * 3)
        this.slots.set(this.key(...item.tile), [sphere, ring, n])
      })
      for (const batch of [sphere, ring]) {
        batch.geometry.setAttribute('bob', new THREE.InstancedBufferAttribute(bob, 3))
        batch.computeBoundingSphere()
        batch.boundingSphere.radius += this.tile // room for the bob, and the rings facing the camera
        this.add(batch)
      }
    }
  }

  _addPickup(item, node, outlined, model = true) {
    if (model) node.scale.setScalar(this.tile) // one block = 1 (the little Slock is sized already)
    node.traverse((o) => { if (o.isMesh) o.castShadow = false })
    if (outlined) outlineModel(node, this.frame)
    const home = new THREE.Vector3(...item.at)
    node.position.copy(home)
    this.add(node)
    this.pickups.set(this.key(...item.tile), [node, home, Math.random() * 10])
  }

  // The extra life: a little Slock.
  _addLife(item, assets) {
    const life = new Jelly(assets.jelly, JELLY.slock, this.frame, true)
    life.scale.set(1, 1.1, 1).multiplyScalar(LIFE_SIZE * this.tile)
    life.shell.castShadow = false
    life.wobbles = false
    this._addPickup(item, life, false, false)
  }

  // The booster's glowing chevrons: one batch per part of the model.
  _addChevrons(model, chevrons) {
    if (!chevrons.length) return
    const place = chevrons.map((c) => {
      const [bx, by, bz] = [c.basis.slice(0, 3), c.basis.slice(3, 6), c.basis.slice(6, 9)]
      return new THREE.Matrix4().set(bx[0], by[0], bz[0], c.at[0], bx[1], by[1], bz[1], c.at[1], bx[2], by[2], bz[2],
        c.at[2], 0, 0, 0, 1)
    })
    model.updateWorldMatrix(true, true)
    model.traverse((o) => {
      if (!o.isMesh) return
      const batch = new THREE.InstancedMesh(o.geometry, o.material, place.length)
      place.forEach((m, i) => batch.setMatrixAt(i, m.clone().multiply(o.matrixWorld)))
      batch.computeBoundingSphere()
      this.add(batch)
    })
  }

  _addGate(model, outlined) {
    const at = new THREE.Vector3(...this.exit)
    const gate = model.clone(true)
    gate.scale.setScalar(this.tile)
    gate.position.copy(at)
    let barrier = null
    gate.traverse((o) => {
      if (o.isMesh && o.name.startsWith('barrier')) barrier = o
    })
    barrier?.removeFromParent()
    if (outlined) outlineModel(gate, this.frame)
    gate.traverse((o) => { if (o.isMesh && o.material.type !== 'ShaderMaterial') o.castShadow = true })
    this.add(gate)
    if (barrier) {
      barrier.material = gateBarrierMaterial(this.frame.time)
      barrier.scale.setScalar(this.tile)
      barrier.position.copy(at)
      this.barrier = barrier
      this.add(barrier)
    }
  }

  /** Eat whatever floats on tile (col, row). Returns its kind, or null. */
  eat(col, row) {
    const k = this.key(col, row)
    const item = this.items.find((i) => i.tile[0] === col && i.tile[1] === row && !i.eaten)
    if (!item) return null
    item.eaten = true
    if (this.slots.has(k)) {
      const [sphere, ring, n] = (item.slot = this.slots.get(k))
      const gone = new THREE.Matrix4().makeScale(0, 0, 0)
      for (const batch of [sphere, ring]) {
        batch.setMatrixAt(n, gone)
        batch.instanceMatrix.needsUpdate = true
      }
      this.slots.delete(k)
    } else if (this.pickups.has(k)) {
      this.pickups.get(k)[0].removeFromParent()
      this.pickups.delete(k)
    }
    return item.kind
  }

  /** Put the eaten pellets back. */
  refill() {
    const m = new THREE.Matrix4()
    for (const item of this.items) {
      if (!item.eaten || !item.slot) continue
      const [sphere, ring, n] = item.slot
      m.makeTranslation(...item.at)
      for (const batch of [sphere, ring]) {
        batch.setMatrixAt(n, m)
        batch.instanceMatrix.needsUpdate = true
      }
      this.slots.set(this.key(...item.tile), item.slot)
      item.eaten = false
    }
  }

  /** Pickups spin and bob; swurms crawl. */
  update(dt, now) {
    for (const [node, home, phase] of this.pickups.values()) {
      const ph = phase + now
      node.position.copy(home).y += Math.sin(ph * 3) * PICKUP_BOB * this.tile
      node.rotation.y = THREE.MathUtils.degToRad(ph * 150)
    }
    for (const swurm of this.swurms) swurm.tick(dt, now)
  }
}
