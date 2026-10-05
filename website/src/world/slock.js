// How Slock moves (slock.gd, and main.gd's ramps), for the page: it runs along tile-centre rails and turns Pac-Man
// style at tile centres. On a flat floor the tilt sets its speed, and levelled it stops on a tile; on ramps tilted
// gravity pushes it, with floor friction the only drag. Walls stop it dead, and holes drop it. The game uses a
// physics engine; this steps the same rules by hand.
import * as THREE from 'three'
import { FLOOR, LEVEL, VOID, WALL } from './section.js'

export const FALL_GRAVITY = 75
const STEP = 1 / 120              // the game's physics rate
const FRICTION = 0.058
const CREEP_DAMPING = 6
const CREEP_FADE_SPEED = 6
const LEVEL_GRIP = 8
const MAX_TILT = 25 * Math.PI / 180
const HOLE_SNAP = 14
const TURN_SNAP = 14
const TURN_BIAS = 1.15
const HALF = 0.45                 // half the block's width, in blocks (its hull is a tenth undersize)
const HEIGHT_RATIO = 1.1
const BOOST_ACCEL = 80
const BOOST_SPEED = 15
const GUIDE_BRAKE = 20
const LAUNCH_DURATION = 0.55
const FALL_DISTANCE = 5
// On a flat floor (slock.gd has the reasons)
const TOP_SPEED = 28
const ACCEL = 40
const ACCEL_EASE = 5
const BRAKE = 175
const BRAKE_EASE = 10
const COAST = 4
export const LEVEL_TILT = 0.02 // tilt (fraction of full) under which the board counts as level
export const STOP_BRAKE = 175
const SETTLE_SPEED = 3
const TURN_MEMORY = 0.3
const TURN_LATE = 0.5
const CORNER_CARRY = 0.9
const KNOCK_TIME = 0.45

export class SlockBody {
  /** `gravity()`: the current downhill direction (a unit vector, see TiltRig.gravityDir). */
  constructor(section, jelly, gravity) {
    this.section = section
    this.jelly = jelly
    this.gravity = gravity
    this.size = section.tile
    this.height = this.size * HEIGHT_RATIO
    this.pos = new THREE.Vector3()
    this.vel = new THREE.Vector3()
    this.onFall = () => {}
    this._acc = 0
    this._clock = 0
    this._knockedUntil = 0
    this.reset()
  }

  reset() {
    this.pos.fromArray(this.section.start)
    this.vel.set(0, 0, 0)
    this.travelZ = true
    this.falling = false
    this.launch = null
    this.guide = null
    this._turn = null // a lean to the side, remembered: [axis is z, sign] ...
    this._turnUntil = 0 // ... until then
    this._place()
  }

  get tile() { return this.section.tileUnder(this.pos) }

  update(dt) {
    this._acc = Math.min(this._acc + dt, 0.1)
    while (this._acc >= STEP) {
      this._acc -= STEP
      this._step(STEP)
    }
    this._place()
  }

  _place() {
    this.jelly.position.copy(this.pos)
    this.jelly.scale.set(this.size, this.height, this.size)
  }

  _snap(v) { return Math.round(v / this.size) * this.size }

  _snapZ(z) {
    const z0 = this.section.rowZ(0)
    return z0 + Math.round((z - z0) / this.size) * this.size
  }

  /** Whether the tile `d` steps from (col, row) stops a block: a wall, or the shut gate. */
  _solid(col, row) {
    const s = this.section
    if (s.tileAt(col, row) === WALL) return true
    const exit = s.tileUnder(new THREE.Vector3(...s.exit))
    return col === exit[0] && row === exit[1]
  }

  _floorY(p) { return this.section.floorAt(p) + this.height / 2 + 0.02 }

  _step(dt) {
    const s = this.section
    const g = this.gravity().multiplyScalar(FALL_GRAVITY * this.size)
    this._clock += dt
    if (this.launch) return this._fly(dt)
    if (this.falling) {
      this.vel.y += g.y * dt
      const [col, row] = this.tile // (perhaps off the edge of the section: no floor heights there)
      this.vel.x = ((col - s.centre) * s.tile - this.pos.x) * HOLE_SNAP
      this.vel.z = (s.rowZ(row) - this.pos.z) * HOLE_SNAP
      this.pos.addScaledVector(this.vel, dt)
      if (this.pos.y < s.floor - FALL_DISTANCE) {
        this.onFall()
        this.reset()
      }
      return
    }

    this._ramps()
    this._applyGuide()
    const p = this.pos
    const v = this.vel
    const unit = g.length() / FALL_GRAVITY
    const full = g.length() * Math.sin(MAX_TILT)
    const tilt = THREE.MathUtils.clamp(Math.hypot(g.x, g.z) / Math.max(1e-4, full), 0, 1)
    const [tc, tr] = this.tile
    const f = s.floors[THREE.MathUtils.clamp(tc, 0, s.width - 1)][THREE.MathUtils.clamp(tr, 0, s.length - 1)]
    this.governed = f.every((h) => Math.abs(h - f[0]) < 1e-6) && !this._boost && this._clock >= this._knockedUntil

    // Rails: the centre stays on the tile-centre line across the corridor; it turns at a tile centre when the tilt
    // favours the other axis (or did a moment ago) and that way is open.
    let wantZ = this.travelZ
    if (Math.abs(g.z) > Math.abs(g.x) * TURN_BIAS) wantZ = true
    else if (Math.abs(g.x) > Math.abs(g.z) * TURN_BIAS) wantZ = false
    const leaning = wantZ !== this.travelZ && !this.guide
    if (leaning) {
      this._turn = [wantZ, Math.sign(wantZ ? g.z : g.x)]
      this._turnUntil = this._clock + TURN_MEMORY
    } else if (this._clock > this._turnUntil) this._turn = null

    let pulling = false
    if (this._turn && !this.guide) {
      const along = this.travelZ ? p.z : p.x
      const speed = this.travelZ ? v.z : v.x
      const nearest = this.travelZ ? this._snapZ(along) : this._snap(along)
      let at = null
      if (Math.abs(speed) < SETTLE_SPEED * unit) {
        if (this._opens(nearest)) {
          if (Math.abs(nearest - along) < 0.02 * this.size) at = nearest
          else {
            if (this.travelZ) v.z = (nearest - along) * TURN_SNAP
            else v.x = (nearest - along) * TURN_SNAP
            pulling = true
          }
        }
      } else {
        const dir = Math.sign(speed)
        const ahead = (nearest - along) * dir >= 0 ? nearest : nearest + dir * this.size
        const behind = ahead - dir * this.size
        if ((along - behind) * dir <= TURN_LATE * this.size && this._opens(behind)) at = behind
        else if ((ahead - along) * dir <= Math.abs(speed) * dt && this._opens(ahead)) at = ahead
      }
      if (at !== null) {
        const carry = this.governed ? Math.abs(speed) * CORNER_CARRY : 0
        if (this.travelZ) p.z = at
        else p.x = at
        const [z, sign] = this._turn
        this.travelZ = z
        v.x = z ? 0 : sign * carry
        v.z = z ? sign * carry : 0
        this._turn = null
        pulling = false
      }
    }
    if (this.travelZ) {
      p.x = this._snap(p.x)
      v.x = 0
    } else {
      p.z = this._snapZ(p.z)
      v.z = 0
    }

    const axis = this.travelZ ? 'z' : 'x'
    let speed = v[axis]
    if (this.governed && !pulling) {
      speed = this._govern(speed, g[axis] / Math.max(1e-4, full), tilt, leaning, unit, dt)
      if (speed === 0) {
        // At rest on a tile centre: exactly on it.
        const nearest = this.travelZ ? this._snapZ(p.z) : this._snap(p.x)
        if (Math.abs(nearest - p[axis]) < 0.002 * this.size) p[axis] = nearest
      }
    } else {
      // Tilted gravity along the rail, on the floor's slope there; friction against the floor's push back.
      const eps = 0.05 * this.size
      const ahead = p.clone()
      const behind = p.clone()
      ahead[axis] += eps
      behind[axis] -= eps
      const slope = (s.floorAt(ahead) - s.floorAt(behind)) / (2 * eps)
      const push = (g[axis] + g.y * slope) / (1 + slope * slope)
      const normal = Math.abs((slope * g[axis] - g.y) / Math.sqrt(1 + slope * slope))
      if (this._boost) {
        if (Math.sign(speed) === Math.sign(this._boost) && Math.abs(speed) < BOOST_SPEED) speed += this._boost * dt
        else if (speed === 0) speed += this._boost * dt
      }
      speed += push * dt
      const grip = pulling ? 0 : FRICTION * normal * dt
      speed = Math.abs(speed) <= grip ? 0 : speed - Math.sign(speed) * grip

      // Creep: soft resistance at low speed. Level means stop: grip that eases off as the board tilts.
      const sp = Math.abs(speed)
      const fade = CREEP_FADE_SPEED * this.size
      if (sp > 1e-4 && sp < fade) speed -= speed * Math.min(1, CREEP_DAMPING * (1 - sp / fade) * dt)
      const slack = 1 - tilt
      speed -= speed * Math.min(1, LEVEL_GRIP * slack * slack * dt)
    }
    this._boost = 0
    v[axis] = speed

    // Move, stopping dead against a wall.
    p[axis] += speed * dt
    const lead = p.clone()
    lead[axis] += Math.sign(speed) * HALF * this.size
    const [lc, lr] = s.tileUnder(lead)
    if (speed !== 0 && this._solid(lc, lr)) {
      const wall = s.tileCentre(lc, lr)[axis] - Math.sign(speed) * 0.5 * this.size
      p[axis] = wall - Math.sign(speed) * HALF * this.size
      v[axis] = 0
    }

    // Over a hole: drop through it.
    const [col, row] = this.tile
    if (s.tileAt(col, row) === VOID) {
      this.falling = true
      this.guide = null
      return
    }
    p.y = this._floorY(p)
  }

  // The speed along the rail for the next step on a flat floor (slock.gd, _govern).
  _govern(speed, pull, tilt, leaning, unit, dt) {
    if (tilt < LEVEL_TILT) return this._stopOnCentre(speed, unit, dt)
    if (leaning) return Math.sign(speed) * Math.max(0, Math.abs(speed) - COAST * unit * dt)
    const target = TOP_SPEED * unit * THREE.MathUtils.clamp(pull, -1, 1)
    const faster = Math.abs(target) > Math.abs(speed) && target * speed >= 0
    const most = (faster ? ACCEL : BRAKE) * unit
    return speed + THREE.MathUtils.clamp((target - speed) * (faster ? ACCEL_EASE : BRAKE_EASE), -most, most) * dt
  }

  // Levelled: the speed that brings it to a stop on a tile centre (slock.gd, _stop_on_centre).
  _stopOnCentre(speed, unit, dt) {
    const s = this.section
    const p = this.pos
    const along = this.travelZ ? p.z : p.x
    const nearest = this.travelZ ? this._snapZ(along) : this._snap(along)
    if (Math.abs(speed) <= SETTLE_SPEED * unit) {
      const off = nearest - along
      const most = Math.min(SETTLE_SPEED * unit, Math.sqrt(2 * STOP_BRAKE * unit * Math.abs(off)))
      return Math.sign(off) * Math.min(most, Math.abs(off) / dt)
    }
    const dir = Math.sign(speed)
    let c = (nearest - along) * dir >= 0 ? nearest : nearest + dir * this.size
    let stop = null
    for (let k = 0; k < 8; k++) {
      const at = this.travelZ ? new THREE.Vector3(p.x, p.y, c) : new THREE.Vector3(c, p.y, p.z)
      const [col, row] = s.tileUnder(at)
      // A hole, or a drop the game's floor ray doesn't reach (the top of a side ramp): stop before it.
      if (s.tileAt(col, row) === VOID || s.floorAt(at) < p.y - this.height / 2 - 0.35 * this.size) break
      stop = c
      const d = Math.abs(c - along)
      if (d > 1e-4 && (speed * speed) / (2 * d) <= STOP_BRAKE * unit) break
      const next = this.travelZ ? [col, row - dir] : [col + dir, row]
      if (this._solid(...next)) break // a wall straight after it
      c += dir * this.size
    }
    if (stop === null) return dir * Math.max(0, Math.abs(speed) - 3 * STOP_BRAKE * unit * dt)
    const d = Math.abs(stop - along)
    if (d < 1e-4) return 0
    return dir * Math.max(0, Math.abs(speed) - ((speed * speed) / (2 * d)) * dt)
  }

  // Whether the remembered turn's way is open from the tile centre at `along` on the current rail.
  _opens(along) {
    const s = this.section
    const p = this.pos
    const at = this.travelZ ? new THREE.Vector3(p.x, p.y, along) : new THREE.Vector3(along, p.y, p.z)
    const [col, row] = s.tileUnder(at)
    const [z, sign] = this._turn
    return !this._solid(...(z ? [col, row - sign] : [col + sign, row]))
  }

  // The side ramp (main.gd, _side_ramp): sliding down, it brakes to a stop just inside the side room; heading up,
  // a booster speeds it up and launches it in a hop onto the 4th tile of the maze.
  _ramps() {
    const s = this.section
    const [first, last, row] = s.side
    if (row < 0 || Math.abs(this.pos.z - s.rowZ(row)) > s.tile * 0.45) return
    const a = s.tileCentre(first, row).x
    const b = s.tileCentre(last, row).x
    if (this.pos.x < Math.min(a, b) - s.tile || this.pos.x > Math.max(a, b) + s.tile) return
    const risesRight = s.levelAt(first - 1, row) === LEVEL.LOW
    const up = risesRight ? 1 : -1
    const uphill = this.vel.x * up
    if (uphill > 0.3) {
      const topCol = risesRight ? last : first
      const topX = s.tileCentre(topCol, row).x + up * s.tile * 0.5
      if (this.pos.x * up >= topX * up) {
        const doorway = risesRight ? last + 1 : first - 1
        if (!this.governed) this._launchTo(s.tileCentre(doorway + 3 * up, row)) // up the ramp, not settling at its top
      } else this._boost = up * BOOST_ACCEL * this.size
    } else if (uphill < -0.3 && !this.guide) {
      const roomDoor = risesRight ? first - 1 : last + 1
      this.guide = { dir: -up, stop: s.tileCentre(roomDoor - up, row).x }
    }
  }

  _applyGuide() {
    if (!this.guide) return
    const { dir, stop } = this.guide
    const d = (stop - this.pos.x) * dir
    const along = this.vel.x * dir
    if (d <= 0) {
      if (along > 0) this.vel.x = 0
      this.pos.x = stop
      this.guide = null
    } else if (along <= 0.01) this.guide = null
    else {
      const most = Math.sqrt(2 * GUIDE_BRAKE * this.size * d)
      if (along > most) this.vel.x = most * dir
    }
  }

  _launchTo(landing) {
    this.launch = {
      from: this.pos.clone(), to: landing.clone().setY(landing.y + this.height / 2 + 0.02),
      peak: (this.size + 0.15 * this.size) / 0.6, t: 0,
    }
    this.guide = null
  }

  _fly(dt) {
    const l = this.launch
    l.t = Math.min(1, l.t + dt / LAUNCH_DURATION)
    const p = l.from.clone().lerp(l.to, l.t).add(new THREE.Vector3(0, l.peak * 4 * l.t * (1 - l.t), 0))
    this.vel.copy(p).sub(this.pos).divideScalar(dt)
    this.pos.copy(p)
    if (l.t >= 1) {
      const dir = l.to.clone().sub(l.from)
      this.travelZ = Math.abs(dir.z) >= Math.abs(dir.x)
      this.vel.set(0, 0, 0)
      this.launch = null
    }
  }

  /** Knocked away from `from` hard enough to slide about `tiles` blocks (a swurm hit). */
  bounceBack(from, tiles = 3) {
    const away = this.pos.clone().sub(from).setY(0)
    if (away.lengthSq() < 1e-6) away.set(this.vel.x, 0, this.vel.z)
    if (away.lengthSq() < 1e-6) away.set(0, 0, 1)
    away.normalize()
    const a = Math.max(0.5, FRICTION * FALL_GRAVITY)
    const speed = THREE.MathUtils.clamp(Math.sqrt(2 * a * tiles * this.size), 2.5, 12)
    // It stays on its rail: the knock goes along it if it has to.
    const axis = this.travelZ ? 'z' : 'x'
    this.vel[axis] = (Math.abs(away[axis]) > 0.2 ? Math.sign(away[axis]) : -Math.sign(this.vel[axis] || 1)) * speed
    this._knockedUntil = this._clock + KNOCK_TIME // slides free for a moment, rather than at the tilt's speed
  }
}

export { FLOOR }
