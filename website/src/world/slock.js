// How Slock moves (slock.gd, and main.gd's ramps), for the page: tilted gravity pushes it along tile-centre rails,
// floor friction is the only drag, it turns Pac-Man style at tile centres, walls stop it dead, and holes drop it.
// The game uses a physics engine; this steps the same rules by hand.
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
    this.reset()
  }

  reset() {
    this.pos.fromArray(this.section.start)
    this.vel.set(0, 0, 0)
    this.travelZ = true
    this.falling = false
    this.launch = null
    this.guide = null
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
    if (this.launch) return this._fly(dt)
    if (this.falling) {
      this.vel.y += g.y * dt
      const [col, row] = this.tile
      const centre = s.tileCentre(col, row)
      this.vel.x = (centre.x - this.pos.x) * HOLE_SNAP
      this.vel.z = (centre.z - this.pos.z) * HOLE_SNAP
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

    // Rails: the centre stays on the tile-centre line across the corridor; it turns where the tilt favours the
    // other axis and that way is open from the nearest tile centre.
    let wantZ = this.travelZ
    if (Math.abs(g.z) > Math.abs(g.x) * TURN_BIAS) wantZ = true
    else if (Math.abs(g.x) > Math.abs(g.z) * TURN_BIAS) wantZ = false
    const along = this.travelZ ? p.z : p.x
    const alongCentre = this.travelZ ? this._snapZ(along) : this._snap(along)
    if (wantZ !== this.travelZ && !this.guide) {
      const centre = this.travelZ ? new THREE.Vector3(p.x, p.y, alongCentre) : new THREE.Vector3(alongCentre, p.y, p.z)
      const [col, row] = s.tileUnder(centre)
      const next = wantZ ? [col, row - Math.sign(g.z)] : [col + Math.sign(g.x), row]
      if (!this._solid(...next)) {
        if (Math.abs(alongCentre - along) < 0.02 * this.size) {
          this.travelZ = wantZ
          p.copy(centre)
          if (this.travelZ) v.x = 0
          else v.z = 0
        } else if (this.travelZ) v.z = (alongCentre - along) * TURN_SNAP
        else v.x = (alongCentre - along) * TURN_SNAP
      }
    }
    if (this.travelZ) {
      p.x = this._snap(p.x)
      v.x = 0
    } else {
      p.z = this._snapZ(p.z)
      v.z = 0
    }

    // Tilted gravity along the rail, on the floor's slope there; friction against the floor's push back.
    const axis = this.travelZ ? 'z' : 'x'
    const eps = 0.05 * this.size
    const ahead = p.clone()
    const behind = p.clone()
    ahead[axis] += eps
    behind[axis] -= eps
    const slope = (s.floorAt(ahead) - s.floorAt(behind)) / (2 * eps)
    const push = (g[axis] + g.y * slope) / (1 + slope * slope)
    const normal = Math.abs((slope * g[axis] - g.y) / Math.sqrt(1 + slope * slope))
    let speed = v[axis]
    if (this._boost) {
      if (Math.sign(speed) === Math.sign(this._boost) && Math.abs(speed) < BOOST_SPEED) speed += this._boost * dt
      else if (speed === 0) speed += this._boost * dt
      this._boost = 0
    }
    speed += push * dt
    const grip = FRICTION * normal * dt
    speed = Math.abs(speed) <= grip ? 0 : speed - Math.sign(speed) * grip

    // Creep: soft resistance at low speed. Level means stop: grip that eases off as the board tilts.
    const sp = Math.abs(speed)
    const fade = CREEP_FADE_SPEED * this.size
    if (sp > 1e-4 && sp < fade) speed -= speed * Math.min(1, CREEP_DAMPING * (1 - sp / fade) * dt)
    const tilt = THREE.MathUtils.clamp(Math.hypot(g.x, g.z) / Math.max(1e-4, g.length() * Math.sin(MAX_TILT)), 0, 1)
    const slack = 1 - tilt
    speed -= speed * Math.min(1, LEVEL_GRIP * slack * slack * dt)
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
        this._launchTo(s.tileCentre(doorway + 3 * up, row))
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
  }
}

export { FLOOR }
