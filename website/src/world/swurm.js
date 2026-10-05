// A swurm (swurm.gd): a green block worm that inches through the maze like a telescope. The head slides two tiles
// while the body stays put; then the five segments, each 20% smaller than the one ahead, follow in a short train
// until they're tucked inside the head, and it slides again.
import * as THREE from 'three'
import { JELLY, Jelly } from './jelly.js'

const SEGMENT_SCALE = [0.8, 0.64, 0.512, 0.41, 0.328]
const SLIDE_TILES = 2
const SEGMENT_GAP = 0.08
const KNOCK_SPEED = 2.5           // a knock-back slide runs this many times faster than crawling
const DIRS = [[0, 1], [0, -1], [-1, 0], [1, 0]]

export class Swurm extends THREE.Group {
  /** `simple`: just the head, no outline or shadow (for sections only ever seen from far off). */
  constructor(section, home, geometry, frame, simple = false) {
    super()
    this.section = section
    this.size = section.tile
    this.home = home
    this.speed = section.swurmSpeed
    this.head = new Jelly(geometry, JELLY.swurm, frame, false, !simple)
    this.head.scale.setScalar(this.size)
    this.head.wobbles = false
    this.head.shell.castShadow = !simple
    this.body = simple ? [] : SEGMENT_SCALE.map((s) => {
      const seg = new Jelly(geometry, JELLY.swurm, frame)
      seg.scale.setScalar(this.size * s)
      return seg
    })
    this.add(this.head, ...this.body)
    this.releaseAt = 0
    this.speedScale = 1               // slower while scared
    this.reset()
  }

  reset() {
    this.from = [...this.home]
    this.to = [...this.home]
    this.head.position.copy(this._pos(this.home))
    this.body.forEach((seg, i) => seg.position.copy(this._floorPoint(this.head.position, SEGMENT_SCALE[i])))
    this._pickNext()
  }

  setLook(look) {
    for (const block of [this.head, ...this.body]) block.setLook(look)
  }

  _pos(t) {
    return this.section.tileCentre(...t).add(new THREE.Vector3(0, this.size * 0.5, 0))
  }

  _floorPoint(p, scale) {
    return new THREE.Vector3(p.x, this.section.floor + this.size * scale * 0.5, p.z)
  }

  tick(dt, now) {
    for (const seg of this.body) seg.step(dt)
    if (now < this.releaseAt) return
    const speed = this.speed * this.speedScale
    if (this.sliding) {
      const end = this._pos(this.to)
      const tiles = Math.max(1, this.slideStart.distanceTo(end) / this.size)
      this.t = Math.min(1, this.t + dt * speed * (this.knocked ? KNOCK_SPEED : 1) / tiles)
      // A knock starts fast and eases out; a crawl eases in and out.
      const m = this.knocked ? 1 - (1 - this.t) * (1 - this.t) : this.t * this.t * (3 - 2 * this.t)
      this.head.position.lerpVectors(this.slideStart, end, m)
      if (this.t < 1) return
      this.sliding = false
      this.gatherTime = 0
      this.gatherFrom = this.body.map((seg) => seg.position.clone())
      return
    }
    // The body: each segment sets off once the one ahead is a block-edge gap clear of it.
    this.gatherTime += dt
    let gathered = true
    let lag = 0
    this.body.forEach((seg, i) => {
      if (i > 0) lag += this.size * ((SEGMENT_SCALE[i - 1] + SEGMENT_SCALE[i]) * 0.5 + SEGMENT_GAP)
      const target = this._floorPoint(this.head.position, SEGMENT_SCALE[i])
      const dist = this.gatherFrom[i].distanceTo(target)
      const travelled = Math.max(0, this.gatherTime * speed * this.size - lag)
      const f = dist < 1e-4 ? 1 : THREE.MathUtils.clamp(travelled / dist, 0, 1)
      seg.position.lerpVectors(this.gatherFrom[i], target, f)
      if (f < 1) gathered = false
    })
    if (gathered) this._pickNext()
  }

  // Two tiles straight on if it can, else one; never straight back unless it's a dead end.
  _pickNext() {
    const back = [Math.sign(this.from[0] - this.to[0]), Math.sign(this.from[1] - this.to[1])]
    this.from = [...this.to]
    const next = this._choose(SLIDE_TILES, back) ?? this._choose(1, back)
    this.to = next ?? [this.from[0] + back[0], this.from[1] + back[1]]
    this.slideStart = this._pos(this.from)
    this.t = 0
    this.sliding = true
    this.knocked = false
  }

  /** Hit Slock: knocked up to `tiles` blocks straight away from it (sideways if that's blocked), quickly. */
  knockBack(slockPos, tiles = 3) {
    const away = this.head.position.clone().sub(slockPos)
    let dir = Math.abs(away.x) >= Math.abs(away.z) ? [away.x >= 0 ? 1 : -1, 0] : [0, away.z >= 0 ? -1 : 1]
    const at = !this.sliding || this.t >= 0.5 ? this.to : this.from
    let n = this._room(at, dir, tiles)
    if (n === 0) {
      const side = [dir[1], dir[0]]
      const a = this._room(at, side, tiles)
      const b = this._room(at, [-side[0], -side[1]], tiles)
      if (a > 0 || b > 0) {
        dir = a >= b ? side : [-side[0], -side[1]]
        n = Math.max(a, b)
      }
    }
    this.slideStart = this.head.position.clone()
    this.from = [...at]
    this.to = [at[0] + dir[0] * n, at[1] + dir[1] * n]
    this.t = 0
    this.sliding = true
    this.knocked = true
  }

  _room(at, d, tiles) {
    let k = 0
    while (k < tiles && this.section.isCrawlable(at[0] + d[0] * (k + 1), at[1] + d[1] * (k + 1))) k++
    return k
  }

  _choose(tiles, back) {
    const options = []
    for (const d of DIRS) {
      if (d[0] === back[0] && d[1] === back[1]) continue
      let clear = true
      for (let i = 1; i <= tiles; i++) clear &&= this.section.isCrawlable(this.from[0] + d[0] * i, this.from[1] + d[1] * i)
      if (clear) options.push([this.from[0] + d[0] * tiles, this.from[1] + d[1] * tiles])
    }
    return options.length ? options[Math.floor(Math.random() * options.length)] : null
  }
}
