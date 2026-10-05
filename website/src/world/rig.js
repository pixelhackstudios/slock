// The game's camera (tilt_rig.gd): it looks down at the board from `pitch`, turned by `yaw`, and presents the tilt by
// turning the whole view the same way gravity turns, so what looks downhill is downhill.
import * as THREE from 'three'

export const MAX_TILT = 25 // degrees at full input
const DEG = Math.PI / 180
const DOWN = new THREE.Vector3(0, -1, 0)
const X = new THREE.Vector3(1, 0, 0)
const Y = new THREE.Vector3(0, 1, 0)

export class TiltRig {
  constructor(camera) {
    this.camera = camera
    this.yaw = 28
    this.pitch = 48
    this.distance = 20
    this.lookAhead = 3
    this.tilt = new THREE.Vector2() // each axis -1..1: x = screen right, y = screen up
    this.pivot = new THREE.Vector3()
  }

  /** The untilted view: looking down at `pitch`, turned by `yaw` to the right. */
  baseRotation() {
    return new THREE.Quaternion().setFromAxisAngle(Y, -this.yaw * DEG)
      .multiply(new THREE.Quaternion().setFromAxisAngle(X, -this.pitch * DEG))
  }

  /** Which way is down for the current tilt (tilt_rig.gd, gravity_dir). */
  gravityDir() {
    const mag = Math.min(1, this.tilt.length())
    if (mag < 1e-5) return DOWN.clone()
    const rot = this.baseRotation()
    const right = new THREE.Vector3(1, 0, 0).applyQuaternion(rot).setY(0).normalize()
    const fwd = new THREE.Vector3(0, 0, -1).applyQuaternion(rot).setY(0).normalize()
    const foreshorten = Math.max(0.2, Math.sin(this.pitch * DEG))
    const dir = right.multiplyScalar(this.tilt.x).addScaledVector(fwd, this.tilt.y / foreshorten).normalize()
    return DOWN.clone().addScaledVector(dir, Math.tan(mag * MAX_TILT * DEG)).normalize()
  }

  /** Put the camera `distance` back from `pivot`, tilted. */
  place() {
    const rot = new THREE.Quaternion().setFromUnitVectors(DOWN, this.gravityDir()).multiply(this.baseRotation())
    this.camera.quaternion.copy(rot)
    this.camera.position.copy(this.pivot).add(new THREE.Vector3(0, 0, this.distance).applyQuaternion(rot))
  }
}
