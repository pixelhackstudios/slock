// A rounded jelly block that wobbles like jelly (jelly.gd): the top sways behind the bottom when it speeds up, stops
// or turns, and the whole block squishes and springs back when it smacks into something. Slock is red with a darker
// core; swurms are green, without one.
import * as THREE from 'three'
import { JELLY, coreMaterial, jellyMaterial, jellyOutlineMaterial } from './look.js'

const SWAY_GAIN = 0.012
const SWAY_MAX = 0.32
const SWAY_STIFFNESS = 260
const SWAY_DAMPING = 5
const SQUISH_GAIN = 0.05
const SQUISH_MAX = 0.32
const SQUISH_STIFFNESS = 380
const SQUISH_DAMPING = 7
const IMPACT_THRESHOLD = 1.5

const inverse = new THREE.Matrix4()

export class Jelly extends THREE.Group {
  /** `geometry`: the rounded block (jelly.glb). `look`: one of JELLY. `core`: Slock's dark core. `outline`: its thin
   *  black outline (left off where it's too far away to see). */
  constructor(geometry, look, frame, core = false, outline = true) {
    super()
    this.wobbles = true
    this.uniforms = {
      sway: { value: new THREE.Vector2() },
      squish: { value: 0 },
      squishAxis: { value: new THREE.Vector3(0, 1, 0) },
    }
    this.shell = new THREE.Mesh(geometry, jellyMaterial(look, this.uniforms))
    this.shell.castShadow = true
    this.add(this.shell)
    if (outline) {
      const line = new THREE.Mesh(geometry, jellyOutlineMaterial(this.uniforms, frame))
      line.onBeforeRender = (renderer, scene, camera) => {
        line.material.uniforms.viewToModel.value.copy(inverse.multiplyMatrices(camera.matrixWorldInverse,
          line.matrixWorld).invert())
      }
      this.add(line)
    }
    if (core) {
      this.core = new THREE.Mesh(geometry, coreMaterial())
      this.core.scale.setScalar(0.5)
      this.add(this.core)
    }
    this._sway = new THREE.Vector2()
    this._swayVel = new THREE.Vector2()
    this._squish = 0
    this._squishVel = 0
    this._lastVel = new THREE.Vector3()
    this._lastPos = null
  }

  setLook(look) {
    this.shell.material.color.copy(look.color)
    this.shell.material.emissive.copy(look.glow)
  }

  /** Squish along `normal` (world space) for an impact of `speed`. */
  hit(normal, speed) {
    if (speed < 0.6) return
    const axis = this.uniforms.squishAxis.value
    axis.copy(normal)
    if (axis.lengthSq() < 1e-8) axis.set(0, 1, 0)
    axis.normalize()
    this._squishVel += Math.min(speed * SQUISH_GAIN * 60, 12)
  }

  /** Advance the wobble: `velocity` given (Slock), or worked out from how far it moved (swurm segments). */
  step(dt, velocity = null) {
    if (!this.wobbles || dt <= 0) return
    if (!velocity) {
      if (!this._lastPos) this._lastPos = this.position.clone()
      velocity = this.position.clone().sub(this._lastPos).divideScalar(dt)
      this._lastPos.copy(this.position)
    }
    const dv = velocity.clone().sub(this._lastVel)
    const accel = dv.clone().divideScalar(dt)
    this._lastVel.copy(velocity)
    if (dv.length() > IMPACT_THRESHOLD) this.hit(dv, dv.length())

    // In the block's own space (one block across), like the game.
    const target = new THREE.Vector2(-accel.x / this.scale.x, -accel.z / this.scale.z).multiplyScalar(SWAY_GAIN)
    if (target.length() > SWAY_MAX) target.setLength(SWAY_MAX)
    this._swayVel.addScaledVector(target.sub(this._sway).multiplyScalar(SWAY_STIFFNESS)
      .addScaledVector(this._swayVel, -SWAY_DAMPING), dt)
    this._sway.addScaledVector(this._swayVel, dt)
    if (this._sway.length() > SWAY_MAX) this._sway.setLength(SWAY_MAX)

    this._squishVel += (-SQUISH_STIFFNESS * this._squish - SQUISH_DAMPING * this._squishVel) * dt
    this._squish = THREE.MathUtils.clamp(this._squish + this._squishVel * dt, -SQUISH_MAX, SQUISH_MAX)

    this.uniforms.sway.value.copy(this._sway)
    this.uniforms.squish.value = this._squish
    if (this.core) this.core.position.set(this._sway.x * 0.3, 0, this._sway.y * 0.3)
  }
}

export { JELLY }
