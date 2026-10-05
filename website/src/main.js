import '@fontsource-variable/tilt-warp'
import '@fontsource-variable/archivo'
import '@fontsource-variable/martian-mono'
import './styles.css'
import Lenis from 'lenis'
import { Director } from './director.js'
import { setupDownloads } from './downloads.js'
import { setupPlayer } from './player.js'
import { LEVEL_TILT } from './world/slock.js'
import { World } from './world/world.js'

const root = document.documentElement
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
const touch = matchMedia('(pointer: coarse)').matches
setupDownloads()
setupPlayer()

// ------------------------------------------------------------------ scrolling

const lenis = reduced ? null : new Lenis({ lerp: 0.11 })
for (const a of document.querySelectorAll('a[data-scroll]')) {
  a.addEventListener('click', (e) => {
    const id = a.getAttribute('href').slice(1)
    const target = document.getElementById(id)
    if (!target) return
    e.preventDefault()
    // The soundtrack player sits in the middle of the screen; the chapters start at the top.
    const middle = id === 'soundtrack' ? -Math.max(90, (innerHeight - target.offsetHeight) / 2) : 0
    if (lenis) lenis.scrollTo(id === 'top' ? 0 : target, { duration: 1.6, offset: middle })
    else target.scrollIntoView({ block: id === 'soundtrack' ? 'center' : 'start' })
  })
}

// Words arrive as their chapter comes in.
const arriving = document.querySelectorAll('.copy > *, .shelf-head > *, .shelf li, .slugs, .chapter--watch > *, .download-inner > *')
const arrive = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (e.isIntersecting) {
      e.target.classList.add('in')
      arrive.unobserve(e.target)
    }
  }
}, { rootMargin: '0px 0px -12% 0px' })
arriving.forEach((el, i) => {
  el.classList.add('reveal')
  el.style.transitionDelay = `${(i % 4) * 70}ms`
  arrive.observe(el)
})

// The film: it loads and plays only while it's on screen.
const video = document.querySelector('.reel video')
new IntersectionObserver(([e]) => {
  if (e.isIntersecting) {
    if (!video.src) video.src = video.dataset.src
    if (!reduced) video.play().catch(() => {})
  } else video.pause()
}, { threshold: 0.4 }).observe(video)

// ------------------------------------------------------------------ the world

const canvas = document.getElementById('world')
let world = null
try {
  world = new World(canvas, {
    dpr: Math.min(devicePixelRatio, touch ? 1.5 : 2), samples: touch ? 2 : 4, shadowSize: touch ? 1024 : 2048,
  })
} catch {
  noWorld()
}

if (world) await start(world)

// Without WebGL, a still from the game stands in for the live world.
function noWorld() {
  root.style.setProperty('--fallback', `url(${import.meta.env.BASE_URL}media/run.jpg)`)
  root.classList.add('no-webgl', 'ready')
}

async function start(world) {
  const loader = document.querySelector('.loader-row')
  const cards = [...document.querySelectorAll('.shelf li')]
  try {
    await world.load((p) => loader.style.setProperty('--p', p.toFixed(3)), cards.map((li) => li.dataset.pickup))
  } catch (err) {
    console.error(err)
    noWorld()
    return
  }
  const director = new Director(world, [...document.querySelectorAll('[data-shot]')], { snap: reduced })
  world.autopilotOn = !reduced
  const resize = () => {
    world.resize(canvas.clientWidth, canvas.clientHeight)
    director.measure()
  }
  resize()
  addEventListener('resize', resize)
  document.fonts.ready.then(() => director.measure())
  setTimeout(() => world.loadCourse(), 1500)

  const dials = [...document.querySelectorAll('.dial')]
  const states = [...document.querySelectorAll('.states li')]
  const swurms = document.getElementById('swurms')
  const download = document.getElementById('download')
  let shown = { state: null, since: 0 }
  let chapter = null

  let last = performance.now()
  requestAnimationFrame(function frame(t) {
    requestAnimationFrame(frame)
    lenis?.raf(t)
    const dt = Math.min((t - last) / 1000, 0.1)
    last = t
    const covered = download.getBoundingClientRect().top <= 0
    if (covered) return // the porcelain download section hides the world: nothing to draw

    const view = director.view(lenis ? lenis.scroll : scrollY)
    const active = director.active
    if (active.name !== chapter) {
      if (active.name === 'swurms') world.callSwurmsHome()
      chapter = active.name
    }
    const powered = active.name === 'swurms' && active.p > 0.45
    world.holdPower(powered)
    swurms.classList.toggle('powered', powered)

    const onShelf = cards[0].getBoundingClientRect().top < innerHeight * 1.2 &&
      cards[cards.length - 1].getBoundingClientRect().bottom > -innerHeight * 0.2
    world.shelf.visible = onShelf
    world.update(dt, view)
    if (onShelf) {
      world.shelf.place(world.camera, cards.map((li) => {
        const r = li.getBoundingClientRect()
        return { left: r.left, top: r.top, width: r.width, height: r.width }
      }), canvas.clientHeight)
    }
    world.render()

    // The board's tilt, on the dial, and how Slock is moving.
    const k = world.rig.tilt
    const hand = world.hand.clone()
    if (hand.length() > 1) hand.normalize()
    for (const dial of dials) {
      const dot = dial.lastElementChild
      dot.setAttribute('cx', (hand.x * 56).toFixed(1))
      dot.setAttribute('cy', (-hand.y * 56).toFixed(1))
      dial.classList.toggle('level', k.length() < LEVEL_TILT)
    }
    const speed = Math.hypot(world.body.vel.x, world.body.vel.z) / world.body.size
    const state = k.length() < 0.03 && speed < 0.3 ? 'stop' : speed > 4 ? 'slide' : 'creep'
    if (state !== shown.state && world.now - shown.since > 0.6) {
      shown = { state, since: world.now }
      for (const li of states) li.classList.toggle('on', li.dataset.state === state)
    }
  })
  root.classList.add('ready')
}
