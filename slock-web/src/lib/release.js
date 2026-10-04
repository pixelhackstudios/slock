import { useEffect, useState } from 'react';

export const REPO = 'https://github.com/pixelhackstudios/slock';

// Used until the GitHub API answers (or if it can't be reached).
const FALLBACK_TAG = 'v0.5.0';
const fallbackUrl = (file) => `${REPO}/releases/download/${FALLBACK_TAG}/${file}`;

export const PLATFORMS = [
  { id: 'windows', name: 'Windows', short: 'WIN', file: 'Slock-Windows.zip', match: 'Windows' },
  { id: 'mac', name: 'Mac', short: 'MAC', file: 'Slock-Mac.zip', match: 'Mac' },
  { id: 'linux', name: 'Linux', short: 'LNX', file: 'Slock-Linux.tar.gz', match: 'Linux' },
];

export function detectPlatform() {
  const ua = navigator.userAgent;
  if (/Windows/i.test(ua)) return 'windows';
  if (/Mac/i.test(ua) && !/iPhone|iPad/i.test(ua)) return 'mac';
  if (/Linux/i.test(ua) && !/Android/i.test(ua)) return 'linux';
  return null;
}

/** The newest release, pre-releases included, so the site never needs editing for a new version. */
export function useLatestRelease() {
  const [release, setRelease] = useState({
    tag: FALLBACK_TAG,
    links: Object.fromEntries(PLATFORMS.map((p) => [p.id, fallbackUrl(p.file)])),
  });

  useEffect(() => {
    let alive = true;
    fetch('https://api.github.com/repos/pixelhackstudios/slock/releases?per_page=1')
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then(([rel]) => {
        if (!alive || !rel) return;
        const links = {};
        for (const p of PLATFORMS) {
          const asset = rel.assets.find((a) => a.name.includes(p.match));
          if (asset) links[p.id] = asset.browser_download_url;
        }
        setRelease((prev) => ({ tag: rel.tag_name, links: { ...prev.links, ...links } }));
      })
      .catch(() => {});
    return () => { alive = false; };
  }, []);

  return release;
}

export function scrollToId(e, id) {
  e.preventDefault();
  const target = id === 'top' ? 0 : document.getElementById(id);
  if (window.lenis) window.lenis.scrollTo(target);
  else if (target === 0) window.scrollTo({ top: 0, behavior: 'smooth' });
  else target?.scrollIntoView({ behavior: 'smooth' });
}
