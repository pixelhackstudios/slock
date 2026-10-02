import { REPO } from '@/lib/release';

export default function Footer() {
  return (
    <footer className="border-t border-(--border-soft) bg-(--bg) mt-14 sm:mt-20">
      <div className="max-w-6xl mx-auto px-6 py-8 sm:py-12 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
        <div className="flex items-center gap-3">
          <span className="jelly w-7 h-7 rounded-md shrink-0" aria-hidden="true" />
          <div className="text-xs sm:text-sm text-(--ink-200)">
            Slock ·{' '}
            <span className="text-(--ink-300)">
              built by{' '}
              <a href="https://www.scottonanski.com" target="_blank" rel="noopener noreferrer" className="hover:text-(--ink-50) underline underline-offset-2 transition">Scott O'Nanski</a>,{' '}
              <a href="https://www.pixelhackstudios.com" target="_blank" rel="noopener noreferrer" className="hover:text-(--ink-50) underline underline-offset-2 transition">Pixelhack Studios</a>
            </span>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-4 sm:gap-5 text-xs sm:text-sm text-(--ink-200)">
          <a href={REPO} target="_blank" rel="noopener noreferrer" className="hover:text-(--ink-50) transition py-1">GitHub</a>
          <a href={`${REPO}/tree/main/slock-web`} target="_blank" rel="noopener noreferrer" className="hover:text-(--ink-50) transition py-1">Website Source</a>
          <span className="badge">MIT · CC BY 4.0</span>
        </div>
      </div>
      <div className="max-w-6xl mx-auto px-6 pb-8 sm:pb-10">
        <p className="text-[11px] sm:text-xs text-(--ink-300) m-0">
          Free software. Endless maze. No jelly was harmed.
        </p>
      </div>
    </footer>
  );
}
