// The game's world on the page: the renderer, the course's sections, Slock (which you can play), and the camera.
import * as THREE from 'three'
import { Assets } from './assets.js'
import { Autopilot } from './autopilot.js'
import { JELLY, Jelly } from './jelly.js'
import { aimShadow, light } from './look.js'
import { TiltRig } from './rig.js'
import { SectionView } from './section.js'
import { Shelf } from './shelf.js'
import { SlockBody } from './slock.js'

const JITTER_FILTER = 0.025       // tilt_rig.gd: smooths frame-to-frame jitter only
const FOLLOW_SMOOTHING = 0.18
const POWER_DURATION = 10
const POWER_FLASH = 2
const HIT_REACH = 0.9
const HIT_COOLDOWN = 1
const SWURM_RESPAWN = 8
const IDLE_AUTOPILOT = 4          // seconds without input before the autopilot takes over again

export class World {
  constructor(canvas, { dpr = Math.min(window.devicePixelRatio, 2), samples = 4, shadowSize = 2048 } = {}) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' })
    this.renderer.setPixelRatio(dpr)
    // Like Godot, draw in linear light with room above white, blending see-through things there, then show it: a
    // browser's own buffer would blend them after the conversion to screen colours, making them look more solid.
    this.target = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples, stencilBuffer: true })
    this.output = new THREE.Mesh(new THREE.BufferGeometry(), new THREE.ShaderMaterial({
      uniforms: { image: { value: this.target.texture } },
      vertexShader: /* glsl */ `
        varying vec2 vUv;
        void main() {
          vUv = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
          gl_Position = vec4(vUv * 2.0 - 1.0, 0.0, 1.0);
        }`,
      fragmentShader: /* glsl */ `
        uniform sampler2D image;
        varying vec2 vUv;
        void main() {
          gl_FragColor = vec4(clamp(texture2D(image, vUv).rgb, 0.0, 1.0), 1.0);
          #include <colorspace_fragment>
        }`,
      depthTest: false,
      depthWrite: false,
    }))
    this.output.geometry.setDrawRange(0, 3)
    this.output.frustumCulled = false
    this.renderer.shadowMap.enabled = true
    this.renderer.shadowMap.type = THREE.PCFShadowMap
    this.renderer.outputColorSpace = THREE.SRGBColorSpace
    this.scene = new THREE.Scene()
    this.camera = new THREE.PerspectiveCamera(40, 1, 0.3, 250)
    this.rig = new TiltRig(this.camera)
    this.size = new THREE.Vector2(1, 1)
    // Per-frame values the shaders share: the clock, the drawing size, and outline widths in pixels (the game's,
    // at its 1600 x 900, a touch heavier where the browser draws them thinner).
    this.frame = {
      time: { value: 0 },
      viewport: { value: new THREE.Vector2(1, 1) },
      inverseProjection: { value: new THREE.Matrix4() },
      outlinePx: { value: 1 },
      orbOutlinePx: { value: 1.25 },
      modelOutlinePx: { value: 1 },
    }
    this.sun = light(this.scene, this.renderer)
    this.sun.shadow.mapSize.set(shadowSize, shadowSize)
    this.now = 0
    this.stick = new THREE.Vector2()   // where the player's hand is (see steer), -1..1
    this.hand = new THREE.Vector2()    // whoever's hand is on the board this frame (the player's or the autopilot's)
    this.steering = false              // the player has the board (otherwise the autopilot does, if on)
    this.autopilotOn = true
    this.score = 0
    this.events = new EventTarget()    // 'eat', 'power', 'fall', 'hit', 'chomp'
    this._lastInput = -Infinity
    this._powerUntil = 0
    this._hitUntil = new Map()
    this._shift = [0, 0]
  }

  /** The first section, Slock and the powerups' shelf. */
  async load(progress, shelf = []) {
    const assets = (this.assets = await new Assets(this.renderer).load(progress))
    const first = (this.home = new SectionView(assets.first, assets, this.frame))
    this.sections = [first]
    this.scene.add(first)
    this.shelf = new Shelf(shelf, assets, this.frame)
    this.scene.add(this.shelf)
    this.slock = new Jelly(assets.jelly, JELLY.slock, this.frame, true)
    this.scene.add(this.slock)
    this.body = new SlockBody(first, this.slock, () => this.rig.gravityDir())
    this.body.onFall = () => this._emit('fall')
    this.autopilot = new Autopilot(first, this.body, this.rig)
    this.followPivot = this._followGoal()
    this._followVel = new THREE.Vector3()
    for (const swurm of first.swurms) swurm.releaseAt = 0
    return this
  }

  /** The rest of the course, climbing away from the first section (once). */
  loadCourse() {
    this._course ??= (async () => {
      for (let i = 1; i < this.assets.sectionCount; i++) {
        const section = new SectionView(await this.assets.section(i), this.assets, this.frame, { far: true })
        this.sections.push(section)
        this.scene.add(section)
      }
    })()
    return this._course
  }

  /** Back to the pen, and out again one at a time, as at the start of a section. */
  callSwurmsHome(gap = 1.2) {
    this.home.swurms.forEach((swurm, i) => {
      swurm.eatenUntil = 0
      swurm.visible = true
      swurm.reset()
      swurm.releaseAt = this.now + 0.4 + i * gap
    })
  }

  /** Power on (the swurms turn blue) for as long as it's held on, or off. */
  holdPower(on) {
    if (on) this._powerUntil = Math.max(this._powerUntil, this.now + POWER_FLASH + 0.5)
    else if (this._powerHeld) this._powerUntil = 0
    this._powerHeld = on
  }

  _emit(type, detail = {}) {
    this.events.dispatchEvent(new CustomEvent(type, { detail }))
  }

  /** The player's hand: a stick position (each axis -1..1), as from the mouse. */
  steer(x, y) {
    this.stick.set(x, y)
    if (this.stick.length() > 1) this.stick.normalize()
    this.steering = true
    this._lastInput = this.now
  }

  resize(width, height) {
    this.size.set(width, height)
    const dpr = this.renderer.getPixelRatio()
    this.renderer.setSize(width, height, false)
    this.target.setSize(Math.round(width * dpr), Math.round(height * dpr))
    this.camera.aspect = width / height
    this._project()
    this.frame.viewport.value.set(width * dpr, height * dpr)
    this.frame.outlinePx.value = 1 * dpr
    this.frame.orbOutlinePx.value = 1.25 * dpr
    this.frame.modelOutlinePx.value = 1 * dpr
  }

  // The projection, with the picture slid over by `_shift` (fractions of the width and height: right and down) to make
  // room for words.
  _project() {
    const { x: w, y: h } = this.size
    const [sx, sy] = this._shift
    if (sx || sy) this.camera.setViewOffset(w, h, -sx * w, -sy * h, w, h)
    else this.camera.clearViewOffset()
    this.camera.updateProjectionMatrix()
    this.frame.inverseProjection.value.copy(this.camera.projectionMatrixInverse)
  }

  _followGoal() {
    return this.body.pos.clone().add(new THREE.Vector3(0, 0, -this.rig.lookAhead))
  }

  // tilt_rig.gd's critically damped follow.
  _follow(dt) {
    const goal = this._followGoal()
    const omega = 2 / FOLLOW_SMOOTHING
    const x = omega * dt
    const e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    const change = this.followPivot.clone().sub(goal)
    const temp = this._followVel.clone().addScaledVector(change, omega).multiplyScalar(dt)
    this._followVel.addScaledVector(temp, -omega).multiplyScalar(e)
    this.followPivot.copy(goal).add(change.add(temp).multiplyScalar(e))
  }

  /** One frame. `view`: where the camera looks from ({ target, yaw, pitch, distance, shift, lift, play }); `play`
   *  lets the board tilt (the player's or the autopilot's hand), otherwise it eases back to level. */
  update(dt, view) {
    dt = Math.min(dt, 0.1)
    const now = (this.now += dt)
    this.frame.time.value = now

    // The hand on the board: the player's, else (after a while) the autopilot's, else nobody's.
    let want = new THREE.Vector2()
    this.hand = new THREE.Vector2()
    if (view.play) {
      if (this.steering && now - this._lastInput > IDLE_AUTOPILOT) this.steering = false
      const hand = this.steering ? this.stick : (this.autopilotOn ? this.autopilot.stick(now) : null)
      if (hand) {
        this.hand.copy(hand)
        const mag = hand.length()
        want = mag > 0 ? hand.clone().normalize().multiplyScalar(Math.pow(Math.min(1, mag), 2.2)) : want
      }
    }
    this.rig.tilt.lerp(want, 1 - Math.exp(-dt / JITTER_FILTER))

    this.body.update(dt)
    this.slock.step(dt, this.body.vel)
    this._eat()
    this._swurms(dt)
    for (const s of this.sections) s.update(dt, now)
    if (this.shelf.visible) this.shelf.update(now)
    this._follow(dt)

    this.rig.pivot.copy(view.target ?? this.followPivot)
    this.rig.yaw = view.yaw
    this.rig.pitch = view.pitch
    this.rig.distance = view.distance
    this.rig.place()
    const sx = view.shift ?? 0
    const sy = view.lift ?? 0
    if (sx !== this._shift[0] || sy !== this._shift[1]) {
      this._shift = [sx, sy]
      this._project()
    }
    aimShadow(this.sun, this.rig.pivot, Math.max(30, view.distance * 2.2))
  }

  _eat() {
    const b = this.body
    if (b.falling || b.launch) return
    const s = this.home
    const [col, row] = b.tile
    const item = s.items.find((i) => !i.eaten && i.tile[0] === col && i.tile[1] === row)
    if (!item || Math.abs(item.at[1] - b.pos.y) > s.tile * 1.5) return
    const kind = s.eat(col, row)
    if (kind === 'power') {
      this._powerUntil = this.now + POWER_DURATION
      this.score += 50
      this._emit('power')
    } else {
      this.score += kind === 'gold' ? 30 : 10
      this._emit('eat', { kind })
    }
  }

  get powered() { return this.now < this._powerUntil }

  _swurms() {
    const s = this.home
    const b = this.body
    const flashing = this._powerUntil - this.now < POWER_FLASH && this.now % 0.3 < 0.15
    const look = this.powered ? (flashing ? JELLY.flash : JELLY.scared) : JELLY.swurm
    for (const swurm of s.swurms) {
      if (swurm.look !== look) {
        swurm.setLook(look)
        swurm.look = look
      }
      swurm.speedScale = this.powered ? 0.55 : 1
      if (swurm.eatenUntil) {
        if (this.now < swurm.eatenUntil) continue
        swurm.eatenUntil = 0
        swurm.visible = true
        swurm.reset()
      }
      if (b.falling || b.launch) continue
      const d = b.pos.clone().sub(swurm.head.position)
      const reach = HIT_REACH * s.tile
      if (Math.abs(d.x) >= reach || Math.abs(d.y) >= b.height || Math.abs(d.z) >= reach) continue
      if (this.powered) {
        swurm.visible = false
        swurm.eatenUntil = this.now + SWURM_RESPAWN
        this.score += 200
        this._emit('chomp')
        continue
      }
      b.bounceBack(swurm.head.position, 3)
      swurm.knockBack(b.pos, 3)
      if (this.now < (this._hitUntil.get(swurm) ?? 0)) continue
      this._hitUntil.set(swurm, this.now + HIT_COOLDOWN)
      this._emit('hit')
    }
  }

  render() {
    this.renderer.setRenderTarget(this.target)
    this.renderer.render(this.scene, this.camera)
    this.renderer.setRenderTarget(null)
    this.renderer.render(this.output, this.camera)
  }
}
