// The download buttons: the right file for this computer, from the newest release on GitHub (pre-releases too, so
// the site never needs editing for a new version).
const REPO = 'https://github.com/pixelhackstudios/slock'
const FALLBACK_TAG = 'v0.9.0' // until GitHub answers, or if it can't be reached

const PLATFORMS = {
  windows: { name: 'Windows', file: 'Slock-Windows.zip', match: 'Windows' },
  mac: { name: 'Mac', file: 'Slock-Mac.zip', match: 'Mac' },
  linux: { name: 'Linux', file: 'Slock-Linux.tar.gz', match: 'Linux' },
}

function detect() {
  const ua = navigator.userAgent
  if (/iPhone|iPad|Android/i.test(ua)) return null
  if (/Windows/i.test(ua)) return 'windows'
  if (/Mac/i.test(ua)) return 'mac'
  if (/Linux/i.test(ua)) return 'linux'
  return null
}

const megabytes = (bytes) => `${Math.round(bytes / 1e6)} MB`

export function setupDownloads() {
  const mine = detect()
  const links = Object.fromEntries(Object.entries(PLATFORMS).map(([id, p]) =>
    [id, { url: `${REPO}/releases/download/${FALLBACK_TAG}/${p.file}`, size: null }]))

  const show = (tag) => {
    for (const a of document.querySelectorAll('[data-download]')) {
      if (mine) {
        a.href = links[mine].url
        a.textContent = `Download for ${PLATFORMS[mine].name}`
      } else {
        a.href = `${REPO}/releases/latest`
        a.textContent = 'Download free'
      }
    }
    for (const a of document.querySelectorAll('[data-platform]')) {
      const link = links[a.dataset.platform]
      a.href = link.url
      a.textContent = PLATFORMS[a.dataset.platform].name + (link.size ? ` (${megabytes(link.size)})` : '')
    }
    const short = mine ? `Free · ${tag} · also for ${Object.keys(PLATFORMS).filter((id) => id !== mine)
      .map((id) => PLATFORMS[id].name).join(' and ')}` : `Free · ${tag} · Windows, Mac and Linux`
    for (const el of document.querySelectorAll('[data-version]')) el.textContent = short
    for (const el of document.querySelectorAll('[data-version-long]')) {
      el.textContent = mine ? `Slock ${tag}. Not on ${PLATFORMS[mine].name}? Pick another above.` : `Slock ${tag}.`
    }
  }
  show(FALLBACK_TAG)

  fetch('https://api.github.com/repos/pixelhackstudios/slock/releases?per_page=1')
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then(([release]) => {
      if (!release) return
      for (const [id, p] of Object.entries(PLATFORMS)) {
        const asset = release.assets.find((a) => a.name.includes(p.match))
        if (asset) links[id] = { url: asset.browser_download_url, size: asset.size }
      }
      show(release.tag_name)
    })
    .catch(() => {})
}
