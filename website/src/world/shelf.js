// The powerups, each floating over its card on the page: placed every frame where that card's empty spot is, at a
// fixed depth in front of the camera, so they scroll with the words. They spin and bob like they do in the game.
import * as THREE from 'three'
import { JELLY, Jelly } from './jelly.js'
import { outlineModel } from './look.js'

const DEPTH = 12          // how far in front of the camera they float
const FILL = 0.74         // how much of its spot a model fills
const forward = new THREE.Vector3()

export class Shelf extends THREE.Group {
  /** `names`: the pickups in card order ('life' is the little red Slock). */
  constructor(names, assets, frame) {
    super()
    this.items = names.map((name, i) => {
      let model
      if (name === 'life') {
        model = new Jelly(assets.jelly, JELLY.slock, frame, true)
        model.scale.set(1, 1.1, 1)
        model.wobbles = false
      } else {
        model = assets.models[name].clone(true)
        outlineModel(model, frame)
      }
      model.traverse((o) => { if (o.isMesh) o.castShadow = false })
      // All the same size on the shelf, whatever their size in the game, and centred.
      const box = new THREE.Box3().setFromObject(model)
      const size = box.getSize(new THREE.Vector3())
      const fit = new THREE.Group()
      fit.scale.setScalar(1 / Math.max(size.x, size.y, size.z))
      fit.position.copy(box.getCenter(new THREE.Vector3())).multiplyScalar(-fit.scale.x)
      fit.add(model)
      const spin = new THREE.Group()
      spin.add(fit)
      const holder = new THREE.Group()
      holder.add(spin)
      this.add(holder)
      return { holder, spin, phase: i * 1.7 }
    })
    this.visible = false
  }

  /** Put each model over its spot: `spots` are the spots' rectangles on screen (CSS pixels). */
  place(camera, spots, height) {
    camera.getWorldDirection(forward)
    const perPx = 2 * DEPTH * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) / height
    const width = height * camera.aspect
    spots.forEach((r, i) => {
      const item = this.items[i]
      const ndc = new THREE.Vector3(((r.left + r.width / 2) / width) * 2 - 1, 1 - ((r.top + r.height / 2) / height) * 2, 0.5)
      const ray = ndc.unproject(camera).sub(camera.position).normalize()
      item.holder.position.copy(camera.position).addScaledVector(ray, DEPTH / ray.dot(forward))
      item.holder.scale.setScalar(Math.min(r.width, r.height) * perPx * FILL)
      item.holder.quaternion.copy(camera.quaternion)
    })
  }

  update(now) {
    for (const item of this.items) {
      const ph = item.phase + now
      item.spin.position.y = Math.sin(ph * 3) * 0.06
      // Turned towards the camera a little, so they show their tops as they spin.
      item.spin.rotation.set(0.38, THREE.MathUtils.degToRad(ph * 90), 0)
    }
  }
}
