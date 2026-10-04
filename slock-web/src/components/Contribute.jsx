import { REPO } from '@/lib/release';

export default function Contribute() {
  return (
    <section id="contribute" className="max-w-6xl mx-auto px-6 py-16 sm:py-24 border-t border-(--border-soft) relative">
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-150 h-100 bg-(--brand-jelly) opacity-[0.035] blur-[140px] rounded-full pointer-events-none" />
      <div className="absolute bottom-10 right-1/4 w-100 h-75 bg-(--brand-slorm) opacity-[0.025] blur-[120px] rounded-full pointer-events-none" />

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-stretch relative z-10">
        <div className="card p-6 sm:p-8 lg:p-10 shadow-2xl lg:col-span-7 flex flex-col">
          <div className="relative z-10 flex flex-col h-full">
            <span className="badge mb-4 sm:mb-6 self-start"><span className="dot-slorm"></span>it's yours too</span>
            <h2 className="font-display text-2xl sm:text-4xl lg:text-5xl tracking-tight uppercase leading-[1.1] mb-6">
              <span className="block"><span className="text-gradient-gold">Fork it.</span> Hack it.</span>
              <span className="block"><span className="text-gradient-jelly">Play it.</span></span>
            </h2>
            <p className="text-lg sm:text-xl text-(--ink-50) font-medium leading-snug mb-4">
              Slock is free, open source, and still taking shape.
            </p>
            <p className="text-[14px] sm:text-[15px] text-(--ink-dim) leading-relaxed mb-8">
              Fix a snag. Tune the tilt. Add a powerup. Build a whole new maze. If something about
              Slock bugs you, it's yours to change, and pull requests are welcome.
            </p>
            <div className="flex flex-wrap items-center gap-3.5 mt-auto">
              <a href={REPO} target="_blank" rel="noopener noreferrer" className="btn-primary px-6 py-3.5 text-[15px] gap-2 group">
                View the repo <span className="transition-transform group-hover:translate-x-0.5">→</span>
              </a>
              <a href={`${REPO}/issues`} target="_blank" rel="noopener noreferrer" className="btn-outline bg-(--ink-950) px-6 py-3.5 text-[15px]">
                Open an issue
              </a>
            </div>
          </div>
        </div>

        <div className="lg:col-span-5 flex flex-col gap-6">
          <div className="card p-6 sm:p-7">
            <div className="relative z-10">
              <span className="badge mb-4"><span className="dot-gold"></span>Build it yourself</span>
              <div className="rounded-xl border border-(--border-soft) bg-(--ink-950) p-4 font-mono text-[12px] sm:text-[13px] leading-relaxed sm:leading-loose text-(--ink-100) overflow-x-auto">
                <div className="term-line break-all sm:break-normal"><span className="term-prompt">$ </span>git clone {REPO}.git</div>
                <div className="term-line text-(--ink-400)"># open it in Godot 4.7 and press F5 to play,</div>
                <div className="term-line text-(--ink-400)"># or Project → Export for Windows / Mac / Linux</div>
              </div>
              <a href={`${REPO}#play-from-source-or-build-it`} target="_blank" rel="noopener noreferrer" className="mt-4 inline-flex text-[13px] font-medium text-(--slorm-300) hover:text-(--slorm-200) transition-colors">
                Full build instructions →
              </a>
            </div>
          </div>
          <div className="card p-6 sm:p-7 flex-1">
            <div className="relative z-10">
              <span className="badge mb-4"><span className="dot"></span>Licences</span>
              <ul className="m-0 p-0 list-none space-y-3 text-[14px]">
                <li className="flex justify-between gap-3 border-b border-(--border-soft) pb-3">
                  <span className="text-(--ink-dim)">Code</span>
                  <a href={`${REPO}/blob/main/LICENSE`} className="font-mono text-(--ink-50) hover:text-(--jelly-300)">MIT</a>
                </li>
                <li className="flex justify-between gap-3">
                  <span className="text-(--ink-dim)">Art</span>
                  <a href={`${REPO}/blob/main/LICENSE-ART.md`} className="font-mono text-(--ink-50) hover:text-(--jelly-300)">CC BY 4.0</a>
                </li>
              </ul>
              <p className="mt-4 mb-0 text-[13px] text-(--ink-300) leading-relaxed">
                Use it, change it, ship it. Just credit Pixelhack Studios (Scott O'Nanski).
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
