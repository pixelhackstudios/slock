import { useState } from 'react';
import { PLATFORMS, REPO, detectPlatform, useLatestRelease } from '@/lib/release';

const HOW_TO_RUN = {
  windows: [['Extract', 'Slock-Windows.zip'], ['Run', 'Slock.exe']],
  mac: [['Extract', 'Slock-Mac.zip'], ['Right-click', 'Slock.app → Open']],
  linux: [['Extract', 'Slock-Linux.tar.gz'], ['Run', 'Slock/Slock.x86_64']],
};

const NOTES = {
  mac: 'It isn\'t signed by Apple yet, so a plain double-click is blocked the first time.',
};

const requirements = [
  { label: 'Price', value: 'Free' },
  { label: 'Windows', value: '64-bit' },
  { label: 'Mac', value: 'macOS' },
  { label: 'Linux', value: 'x86_64' },
  { label: 'Controls', value: 'Mouse or gamepad' },
];

function PlatformPanel({ platform, href, mine }) {
  return (
    <div className={`overflow-hidden shadow-2xl rounded-xl border bg-(--ink-950) ${mine ? 'border-(--jelly-500)' : 'border-(--border-soft)'}`}>
      <div className="bg-(--ink-800) border-b border-(--ink-950) px-4 py-3 flex items-center justify-between select-none gap-3">
        <div className="flex items-center gap-3">
          <span className="inline-flex h-7 px-1.5 items-center justify-center rounded-[5px] border border-(--jelly-500)/60 bg-(--jelly-800)/25 font-mono text-[11px] font-bold text-(--jelly-300) shrink-0">
            {platform.short}
          </span>
          <span className="font-display text-sm tracking-tight text-(--heading) uppercase">{platform.name}</span>
          {mine && <span className="badge py-0.5!"><span className="dot"></span>your computer</span>}
        </div>
        <div className="font-mono text-xs text-(--ink-300) bg-(--bg)/80 px-2.5 py-1 rounded border border-(--border-soft) shrink-0 hidden sm:block">
          {platform.file}
        </div>
      </div>
      <div className="p-4 sm:p-5 flex flex-col sm:flex-row sm:items-end justify-between gap-4">
        <div className="font-mono text-[12px] sm:text-[13px] leading-relaxed sm:leading-loose text-(--ink-100)">
          {HOW_TO_RUN[platform.id].map(([verb, what]) => (
            <div key={verb} className="term-line">
              <span className="term-prompt">→ </span>{verb} <span className="text-(--ink-50)">{what}</span>
            </div>
          ))}
          {NOTES[platform.id] && <div className="term-line text-(--ink-400) mt-1 font-sans text-[12px]">{NOTES[platform.id]}</div>}
        </div>
        <a href={href} className={`${mine ? 'btn-primary' : 'btn-outline-solid'} px-5 py-3 text-[14px] gap-2 shrink-0 group`}>
          Download
          <span className="opacity-60 group-hover:opacity-100 transition-opacity">↓</span>
        </a>
      </div>
    </div>
  );
}

export default function Download() {
  const { tag, links } = useLatestRelease();
  const [mine] = useState(detectPlatform);
  const ordered = [...PLATFORMS].sort((a, b) => (b.id === mine) - (a.id === mine));

  return (
    <section id="download" className="max-w-6xl mx-auto px-6 py-16 sm:py-24 border-t border-(--border-soft) relative">
      <div className="absolute top-20 left-1/4 w-125 h-125 bg-(--brand-jelly) opacity-[0.025] blur-[120px] rounded-full pointer-events-none" />

      <div className="mb-12 sm:mb-16 max-w-2xl relative z-10">
        <span className="badge mb-4"><span className="dot-slorm"></span>Getting started</span>
        <h2 className="font-display text-3xl sm:text-5xl tracking-tight mt-4 uppercase leading-[1.1]">
          <span className="text-gradient-gold">Download.</span> Extract.<br />
          <span className="text-gradient-jelly">Start tilting.</span>
        </h2>
        <p className="mt-4 sm:mt-5 text-(--ink-dim) text-base sm:text-lg leading-relaxed">
          Nothing to install and no account to make. Pick your computer and play.
        </p>
      </div>

      <div className="grid lg:grid-cols-[320px_minmax(0,1fr)] gap-8 items-stretch relative z-10">
        <div className="order-last lg:order-first flex flex-col">
          <div className="card p-6 sm:p-7 shadow-xl flex flex-col justify-between flex-1">
            <div className="relative z-10">
              <span className="badge mb-6"><span className="dot-slorm"></span>What you'll need</span>
              <ul className="space-y-4 text-[13px] sm:text-[14px] m-0 p-0 list-none">
                {requirements.map((r, i) => (
                  <li key={r.label} className={`flex items-start justify-between gap-3 ${i < requirements.length - 1 ? 'border-b border-(--border-soft) pb-4' : ''}`}>
                    <span className="text-(--ink-dim) shrink-0">{r.label}</span>
                    <span className="font-mono text-(--ink-50) text-right text-[12px] sm:text-[13px]">{r.value}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div className="relative z-10 mt-auto pt-6 border-t border-(--border-soft)">
              <div className="flex items-center gap-2 font-mono text-xs text-(--gold-300) uppercase tracking-wider mb-1.5 font-semibold">
                <span className="w-2 h-2 rounded-full bg-(--gold-400) shadow-[0_0_8px_var(--gold-400)] shrink-0"></span>
                {tag} · early pre-release
              </div>
              <p className="text-[13px] text-(--ink-300) leading-relaxed m-0">
                Windows and Mac builds haven't been tested on real machines yet. If Slock won't
                start, <a href={`${REPO}/issues`} className="underline underline-offset-2 hover:text-(--ink-50)">open an issue</a> and
                say what happened.
              </p>
            </div>
          </div>
        </div>

        <div className="space-y-6">
          {ordered.map((p) => <PlatformPanel key={p.id} platform={p} href={links[p.id]} mine={p.id === mine} />)}
          <p className="text-[13px] text-(--ink-400) m-0">
            Older versions are on the <a href={`${REPO}/releases`} className="underline underline-offset-2 hover:text-(--ink-50)">releases page</a>.
          </p>
        </div>
      </div>
    </section>
  );
}
