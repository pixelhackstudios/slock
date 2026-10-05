// The soundtrack player beside the downloads: the game's music (sounds/theme-music/, as public/media/music/*.m4a),
// with its playlist. Like the game, it starts with the main theme and then shuffles the rest (shuffle can be turned
// off to play the list in order). Nothing loads until someone presses play.
const SONGS = [ // name, file, length in seconds (to show before a song has loaded)
  ['Main theme', 'main-theme', 188], ['Theme 1', 'theme-001', 172], ['Theme 2', 'theme-002', 172],
  ['Theme 3', 'theme-003', 164], ['Theme 4', 'theme-004', 142], ['Theme 5', 'theme-005', 151],
  ['Theme 6', 'theme-006', 155], ['Theme 7', 'theme-007', 165], ['Theme 8', 'theme-008', 160],
  ['Theme 9', 'theme-009', 196], ['Theme 10', 'theme-010', 185], ['Theme 11', 'theme-011', 190],
  ['Theme 12', 'theme-012', 185], ['Theme 13', 'theme-013', 174],
]
const BASE = `${import.meta.env.BASE_URL}media/music/`
const BOOST = 3 // the songs are mastered quiet (about -25 LUFS, peaks near -12 dB): this lifts them ~9.5 dB

const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`

export function setupPlayer() {
  const el = document.querySelector('.player')
  if (!el) return
  const audio = el.querySelector('audio')
  const title = el.querySelector('.player-title')
  const play = el.querySelector('.player-play')
  const shuffleButton = el.querySelector('.player-shuffle')
  const pipe = el.querySelector('.player-pipe')
  const glow = el.querySelector('.player-glow')
  const [now, total] = el.querySelectorAll('.player-times span')
  const list = el.querySelector('.player-list')
  let shuffle = true
  let queue = []   // song numbers, in the order they'll play
  let at = 0       // where in the queue we are
  let loaded = -1  // the song the audio element holds

  // The play order from song `first` on: the rest shuffled, or the list in order, round from `first`.
  const arrange = (first) => {
    const rest = SONGS.map((_, i) => (first + 1 + i) % SONGS.length).slice(0, -1)
    if (shuffle) {
      for (let i = rest.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [rest[i], rest[j]] = [rest[j], rest[i]]
      }
    }
    queue = [first, ...rest]
    at = 0
  }

  const rows = SONGS.map(([name, , length], i) => {
    const li = document.createElement('li')
    const button = document.createElement('button')
    button.type = 'button'
    button.innerHTML = `<span class="player-n">${String(i + 1).padStart(2, '0')}</span>` +
      `<span class="player-name">${name}</span><span class="player-len">${clock(length)}</span>`
    button.addEventListener('click', () => {
      arrange(i)
      show()
      start()
    })
    li.append(button)
    list.append(li)
    return button
  })

  const current = () => queue[at]
  const show = () => {
    const [name, , length] = SONGS[current()]
    title.textContent = name
    const len = (loaded === current() && audio.duration) || length
    const t = loaded === current() ? audio.currentTime : 0
    now.textContent = clock(t)
    total.textContent = clock(len)
    glow.style.width = `${Math.min(100, (t / len) * 100)}%`
    pipe.setAttribute('aria-valuenow', Math.round(t))
    pipe.setAttribute('aria-valuemax', Math.round(len))
    pipe.setAttribute('aria-valuetext', `${clock(t)} of ${clock(len)}`)
    rows.forEach((row, i) => {
      const on = i === current()
      if (on !== row.classList.contains('on')) {
        row.classList.toggle('on', on)
        if (on) {
          row.setAttribute('aria-current', 'true')
          list.scrollTo({ top: row.offsetTop - list.clientHeight / 2 + row.offsetHeight / 2, behavior: 'smooth' })
        } else row.removeAttribute('aria-current')
      }
    })
  }
  let boosted = false
  const start = () => {
    if (!boosted) { // louder than the element's own volume allows (set up on the first press: browsers need a click)
      boosted = true
      const ctx = new AudioContext()
      const gain = new GainNode(ctx, { gain: BOOST })
      ctx.createMediaElementSource(audio).connect(gain).connect(ctx.destination)
    }
    if (loaded !== current()) {
      audio.src = `${BASE}${SONGS[current()][1]}.m4a`
      loaded = current()
    }
    audio.play().catch(() => {})
  }
  const go = (step) => {
    const playing = !audio.paused
    if (at + step >= queue.length) { // round again (shuffled, never starting with the song that just played)
      const last = current()
      arrange(shuffle ? (last + 1 + Math.floor(Math.random() * (SONGS.length - 1))) % SONGS.length : (last + 1) % SONGS.length)
    } else at = Math.max(0, at + step)
    show()
    if (playing) start()
  }

  play.addEventListener('click', () => (audio.paused ? start() : audio.pause()))
  el.querySelector('.player-next').addEventListener('click', () => go(1))
  el.querySelector('.player-prev').addEventListener('click', () => {
    if (audio.currentTime > 3 && loaded === current()) audio.currentTime = 0
    else go(-1)
  })
  shuffleButton.addEventListener('click', () => {
    shuffle = !shuffle
    shuffleButton.setAttribute('aria-pressed', String(shuffle))
    arrange(current()) // the song playing stays; what follows it changes
  })
  audio.addEventListener('ended', () => {
    go(1)
    start()
  })
  audio.addEventListener('timeupdate', show)
  audio.addEventListener('loadedmetadata', show)
  for (const type of ['play', 'pause']) {
    audio.addEventListener(type, () => {
      el.classList.toggle('playing', !audio.paused)
      play.setAttribute('aria-label', audio.paused ? 'Play' : 'Pause')
    })
  }

  // Seeking: click or drag along the pipe, or the arrow keys when it has focus.
  const seek = (e) => {
    if (loaded !== current() || !audio.duration) return
    const r = pipe.getBoundingClientRect()
    audio.currentTime = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * audio.duration
  }
  pipe.addEventListener('pointerdown', (e) => {
    pipe.setPointerCapture(e.pointerId)
    seek(e)
  })
  pipe.addEventListener('pointermove', (e) => { if (pipe.hasPointerCapture(e.pointerId)) seek(e) })
  pipe.addEventListener('keydown', (e) => {
    const step = { ArrowRight: 5, ArrowLeft: -5 }[e.key]
    if (!step || loaded !== current()) return
    e.preventDefault()
    audio.currentTime = Math.max(0, audio.currentTime + step)
  })

  // The film of a run has sound too: unmuting it pauses the music.
  const film = document.querySelector('.reel video')
  film?.addEventListener('volumechange', () => { if (!film.muted) audio.pause() })
  audio.addEventListener('play', () => { if (film) film.muted = true })

  arrange(0) // the main theme first, as in the game
  show()
}
