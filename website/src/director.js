// Where the camera looks as you scroll: each chapter of the page has a shot of the course, held while the chapter
// fills the screen and blended into the next one's as you scroll on.
import * as THREE from 'three'

const smooth = (t) => t * t * (3 - 2 * t)

/** The shots, by chapter (each section's data-shot). `p`: how far through its chapter the page is, 0..1. On a
 *  wide screen the words sit to one side and the picture slides over (`shift`); on a tall one they sit at the
 *  bottom and it rises (`lift`). */
const COURSE = new THREE.Vector3(0, 2.5, -72)
const SHOTS = {
  // The whole first section floating in the void, tilting under your hand (on a phone, up close with Slock).
  hero: (w, p, tall) => tall
    ? { target: w.followPivot, yaw: 28, pitch: 50, distance: 24, lift: -0.06, play: true }
    : { target: new THREE.Vector3(-3, 0, -13), yaw: 28, pitch: 42, distance: 48, shift: 0.2, lift: 0.06, play: true },
  // Up close with Slock.
  tilt: (w, p, tall) => ({ target: w.followPivot, yaw: 28, pitch: 50, distance: tall ? 17 : 15, shift: tall ? 0 : 0.22,
    lift: tall ? -0.22 : 0, play: true }),
  // The side room: gold pellets and the gate's key.
  eat: (w, p, tall) => ({ target: new THREE.Vector3(-15, -1.6, -15.5), yaw: 18, pitch: 54, distance: tall ? 19 : 16,
    shift: tall ? 0 : -0.22, lift: tall ? -0.22 : 0 }),
  // The swurms' pen.
  swurms: (w, p, tall) => ({ target: new THREE.Vector3(4.5, 0, -16.5), yaw: 30, pitch: 60, distance: tall ? 15 : 13,
    shift: tall ? 0 : 0.22, lift: tall ? -0.22 : 0 }),
  // Up into the empty void, where the powerups float over their cards.
  shelf: () => ({ target: new THREE.Vector3(0, 46, -10), yaw: 28, pitch: -6, distance: 10 }),
  // The course, climbing away (on a phone, straight up the screen).
  climb: (w, p, tall) => tall
    ? { target: COURSE, yaw: 6, pitch: 42 - p * 6, distance: 128 - p * 10, lift: -0.18 }
    : { target: COURSE, yaw: 34 - p * 10, pitch: 33, distance: 92 - p * 8, shift: 0.16 },
  watch: (w, p, tall) => ({ target: COURSE, yaw: (tall ? 6 : 24) + Math.sin(w.now * 0.05) * 6, pitch: 30,
    distance: tall ? 135 : 96 }),
}

export class Director {
  /** `snap`: cut from shot to shot instead of flying between them (when motion is turned down). */
  constructor(world, chapters, { snap = false } = {}) {
    this.world = world
    this.snap = snap
    this.chapters = chapters.map((el) => ({ el, shot: el.dataset.shot }))
    this.active = null
    this.measure()
  }

  /** Where each chapter is on the page (on load and resize). */
  measure() {
    const vh = window.innerHeight
    this.tall = window.innerWidth / vh < 0.8
    const pad = 0.2 * vh
    for (const c of this.chapters) {
      const top = c.el.getBoundingClientRect().top + window.scrollY
      // Held from a little before the chapter fills the screen until its words start to leave.
      c.from = top - pad
      c.to = top + Math.max(0, c.el.offsetHeight - vh)
    }
  }

  /** The camera's view for scroll position `y`, and which chapter is in charge with how far through it the page is. */
  view(y) {
    const cs = this.chapters
    let i = 0
    while (i < cs.length - 1 && y >= cs[i + 1].from) i++
    const c = cs[i]
    const p = c.to > c.from ? THREE.MathUtils.clamp((y - c.from) / (c.to - c.from), 0, 1) : 0.5
    const a = { shift: 0, lift: 0, ...SHOTS[c.shot](this.world, p, this.tall) }
    this.active = { name: c.shot, p, el: c.el }
    const next = cs[i + 1]
    if (!next || y <= c.to) return a
    let t = smooth(THREE.MathUtils.clamp((y - c.to) / (next.from - c.to), 0, 1))
    if (this.snap) t = Math.round(t)
    const b = { shift: 0, lift: 0, ...SHOTS[next.shot](this.world, 0, this.tall) }
    if (t > 0.5) this.active = { name: next.shot, p: 0, el: next.el }
    return {
      target: a.target.clone().lerp(b.target, t),
      yaw: THREE.MathUtils.lerp(a.yaw, b.yaw, t),
      pitch: THREE.MathUtils.lerp(a.pitch, b.pitch, t),
      distance: THREE.MathUtils.lerp(a.distance, b.distance, t),
      shift: THREE.MathUtils.lerp(a.shift, b.shift, t),
      lift: THREE.MathUtils.lerp(a.lift, b.lift, t),
      play: t < 0.5 ? a.play : b.play,
    }
  }
}
