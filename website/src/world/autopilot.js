// Plays Slock while nobody else is: finds the nearest pellet through the maze and tilts the board to slide there,
// leaning into each turn as Slock reaches it, the way a player does.
import * as THREE from 'three'
import { FLOOR, LEVEL, VOID } from './section.js'
import { STOP_BRAKE } from './slock.js'

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]]

export class Autopilot {
  constructor(section, body, rig) {
    this.section = section
    this.body = body
    this.rig = rig
    this.gentle = 0.56   // how hard it tilts (stick, before the response curve) into a turn ...
    this.bold = 0.75     // ... and down a long straight
    this._path = null
    this._replanAt = 0
    this._restFrom = 6  // now and then it levels the board and lets Slock stop, as a player does
  }

  _walkable(col, row) {
    const s = this.section
    // The maze and the corridor in (not the side ramp and room: their booster is the game's business).
    if (s.tileAt(col, row) !== FLOOR || ![LEVEL.MAIN, LEVEL.CLIMB].includes(s.levelAt(col, row))) return false
    const exit = s.tileUnder(new THREE.Vector3(...s.exit))
    return !(col === exit[0] && row === exit[1])
  }

  // Breadth-first from Slock's tile to the nearest tile with something on it to eat.
  _plan(from) {
    const s = this.section
    const food = new Set(s.items.filter((i) => !i.eaten && ['pellet', 'power', 'gold'].includes(i.kind))
      .map((i) => s.key(...i.tile)))
    const seen = new Map([[s.key(...from), null]])
    const queue = [from]
    while (queue.length) {
      const t = queue.shift()
      if (food.has(s.key(...t)) && (t[0] !== from[0] || t[1] !== from[1])) {
        const path = [t]
        for (let k = seen.get(s.key(...t)); k; k = seen.get(s.key(...k))) path.unshift(k)
        return path
      }
      for (const [dc, dr] of DIRS) {
        const n = [t[0] + dc, t[1] + dr]
        if (!seen.has(s.key(...n)) && this._walkable(...n)) {
          seen.set(s.key(...n), t)
          queue.push(n)
        }
      }
    }
    return null
  }

  /** The stick to hold now (screen-space, each axis -1..1), or null when there's nothing left to chase. */
  stick(now) {
    const b = this.body
    if (b.falling || b.launch) return new THREE.Vector2()
    if (now > this._restFrom) {
      if (now < this._restFrom + 1.4) return new THREE.Vector2()
      this._restFrom = now + 4 + Math.random() * 4
    }
    const here = b.tile
    const end = this._path?.at(-1)
    const arrived = end && end[0] === here[0] && end[1] === here[1] // straight on to the next, not a pause
    if (!this._path || now > this._replanAt || !this._onPath(here) || arrived) {
      this._path = this._plan(here)
      if (!this._path && this._walkable(...here)) {
        this.section.refill() // it has eaten everything: put the pellets back and go round again
        this._path = this._plan(here)
      }
      this._replanAt = now + 0.5
    }
    if (!this._path || this._path.length < 2) return null
    // Trim what's behind, then head for the first turn.
    const i = this._path.findIndex((t) => t[0] === here[0] && t[1] === here[1])
    const path = this._path.slice(Math.max(0, i))
    if (path.length < 2) return null
    if (this._runningAtDrop(here, path)) return new THREE.Vector2() // level: Slock stops on the last tile before it
    // Lean towards the next tile. Where the path turns, that's the new way while Slock is still on the turning
    // tile, and the rails take it round at the tile's centre. Harder the longer the straight ahead.
    const d = [Math.sign(path[1][0] - path[0][0]), Math.sign(path[1][1] - path[0][1])]
    let run = 1 // how far the corridor runs on that way
    while (run < 6 && this._walkable(here[0] + d[0] * (run + 1), here[1] + d[1] * (run + 1))) run++
    const strength = this.gentle + (this.bold - this.gentle) * Math.min(1, (run - 1) / 4)
    return this._toStick(d).multiplyScalar(strength)
  }

  // Whether Slock is running at a hole or the side ramp, with the path not turning off first, and has to level the
  // board now to stop before it (levelled, it stops on the last tile before a drop: see slock.js).
  _runningAtDrop(here, path) {
    const b = this.body
    const s = this.section
    const v = (b.travelZ ? -b.vel.z : b.vel.x) / s.tile // tiles/s: columns right, or rows away
    if (Math.abs(v) < 1) return false
    const reach = (v * v) / (2 * STOP_BRAKE) + 0.04 * Math.abs(v) + 0.5 // braking, once the board has levelled
    const step = b.travelZ ? [0, Math.sign(v)] : [Math.sign(v), 0]
    for (let k = 1; k - 0.5 <= reach; k++) {
      const p = path[k]
      if (p && (step[0] ? p[1] !== here[1] : p[0] !== here[0])) return false // it turns off first
      const [col, row] = [here[0] + step[0] * k, here[1] + step[1] * k]
      if (this._walkable(col, row)) continue
      // A hole, or the side ramp down (a wall or the gate just stops it).
      const kind = s.tileAt(col, row)
      return kind === VOID || (kind === FLOOR && ![LEVEL.MAIN, LEVEL.CLIMB].includes(s.levelAt(col, row)))
    }
    return false
  }

  _onPath(t) {
    return this._path?.some((p) => p[0] === t[0] && p[1] === t[1])
  }

  // A grid direction (columns right, rows away from the camera) as a stick: the inverse of TiltRig.gravityDir.
  _toStick([dc, dr]) {
    const world = new THREE.Vector3(dc, 0, -dr)
    const rot = this.rig.baseRotation()
    const right = new THREE.Vector3(1, 0, 0).applyQuaternion(rot).setY(0).normalize()
    const fwd = new THREE.Vector3(0, 0, -1).applyQuaternion(rot).setY(0).normalize()
    const foreshorten = Math.max(0.2, Math.sin(this.rig.pitch * Math.PI / 180))
    return new THREE.Vector2(world.dot(right), world.dot(fwd) * foreshorten).normalize()
  }
}
