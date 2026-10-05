// Plays Slock in the background of the page: finds the nearest pellet through the maze and tilts the board to slide there,
// unhurried, the way a person does: its hand eases from one lean to the next (never snapping), wavers a little, and
// starts leaning into each corner a moment before Slock gets there.
import * as THREE from 'three'
import { FLOOR, LEVEL, VOID } from './section.js'
import { STOP_BRAKE } from './slock.js'

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]]
const HAND = 0.28        // seconds the hand takes to settle on a new lean (most of the way)
const HAND_QUICK = 0.07  // ... and to level the board in a hurry, before a hole
const EARLY = 0.9        // tiles before a corner that it starts leaning into it

export class Autopilot {
  constructor(section, body, rig) {
    this.section = section
    this.body = body
    this.rig = rig
    this.gentle = 0.55   // how hard it tilts (stick, before the response curve) into a turn ...
    this.bold = 0.7      // ... and down a long straight: a calm cruise, well short of full speed
    this._path = null
    this._replanAt = 0
    this._restFrom = 6  // now and then it levels the board and lets Slock stop, as a player does
    this._hand = new THREE.Vector2()  // where its hand is: it moves towards what it wants, not straight there
    this._last = 0
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

  /** The stick to hold now (screen-space, each axis -1..1): the hand easing towards what it wants. */
  stick(now) {
    const dt = Math.min(0.1, Math.max(0, now - this._last))
    this._last = now
    const want = this._want(now) ?? new THREE.Vector2()
    const hurry = want.lengthSq() === 0 && this._dropAhead
    this._hand.lerp(want, 1 - Math.exp(-dt / (hurry ? HAND_QUICK : HAND)))
    if (want.lengthSq() === 0) return this._hand.clone()
    // A hand never holds quite still: a slow waver of a few degrees.
    const waver = 0.06 * Math.sin(now * 1.3) + 0.04 * Math.sin(now * 2.9 + 1.7)
    return this._hand.clone().rotateAround(new THREE.Vector2(), waver)
  }

  // What it wants to hold now, or null when there's nothing left to chase.
  _want(now) {
    const b = this.body
    this._dropAhead = false
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
    if (this._runningAtDrop(here, path)) {
      this._dropAhead = true
      return new THREE.Vector2() // level: Slock stops on the last tile before it
    }
    // Lean towards the next tile. Where the path turns, that's the new way while Slock is still on the turning
    // tile, and the rails take it round at the tile's centre. Harder the longer the straight ahead.
    const d = [Math.sign(path[1][0] - path[0][0]), Math.sign(path[1][1] - path[0][1])]
    let run = 1 // how far the corridor runs on that way
    while (run < 6 && this._walkable(here[0] + d[0] * (run + 1), here[1] + d[1] * (run + 1))) run++
    const strength = this.gentle + (this.bold - this.gentle) * Math.min(1, (run - 1) / 4)
    // Nearly at a corner (the path turns off at the next tile): lean in early, half into the new way, the way a
    // player does (the game takes the turn once the opening comes).
    let lean = this._toStick(d)
    if (path.length > 2) {
      const next = [Math.sign(path[2][0] - path[1][0]), Math.sign(path[2][1] - path[1][1])]
      if (next[0] !== d[0] || next[1] !== d[1]) {
        const s = this.section
        const c = s.tileCentre(...path[1])
        const gap = (d[0] ? Math.abs(c.x - b.pos.x) : Math.abs(c.z - b.pos.z)) / s.tile
        if (gap < EARLY) lean = lean.add(this._toStick(next).multiplyScalar(1 - gap / EARLY)).normalize()
      }
    }
    return lean.multiplyScalar(strength)
  }

  // Whether Slock is running at a hole or the side ramp, with the path not turning off first, and has to level the
  // board now to stop before it (levelled, it stops on the last tile before a drop: see slock.js).
  _runningAtDrop(here, path) {
    const b = this.body
    const s = this.section
    const v = (b.travelZ ? -b.vel.z : b.vel.x) / s.tile // tiles/s: columns right, or rows away
    if (Math.abs(v) < 1) return false
    // Braking, once the board has levelled (and the time its hand takes to level it).
    const reach = (v * v) / (2 * STOP_BRAKE) + (0.04 + HAND_QUICK * 2) * Math.abs(v) + 0.5
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
