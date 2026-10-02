import { useEffect, useState } from 'react';
import { Menu, X } from 'lucide-react';
import { REPO, scrollToId } from '@/lib/release';

const LINKS = [
  ['top', 'Home'],
  ['about', 'About'],
  ['play', 'How it plays'],
  ['teaser', 'Teaser'],
  ['download', 'Download'],
  ['contribute', 'Contribute'],
];

export function GitHubIcon({ size = 14 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
  );
}

export default function Header() {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const go = (e, id) => {
    setIsOpen(false);
    scrollToId(e, id);
  };

  return (
    <div className={`fixed left-0 right-0 z-50 flex flex-col items-center pointer-events-none transition-all duration-200 ${isScrolled ? 'top-0 px-0' : 'top-4 px-4'}`}>
      <header className={`pointer-events-auto flex items-center justify-between h-14 px-5 border-(--border-soft) bg-(--bg)/90 backdrop-blur-md shadow-sm w-full transition-all duration-300 ${isScrolled ? 'max-w-full rounded-none border-b' : 'max-w-6xl rounded-full border'}`}>
        <a href="#top" onClick={(e) => go(e, 'top')} className="flex items-center gap-3 rounded-full pl-1">
          <span className="jelly w-7 h-7 rounded-lg" aria-hidden="true" />
          <span className="brand-wordmark text-[14px] tracking-tight">Slock</span>
        </a>
        <nav className="hidden md:flex items-center gap-6 text-[13px] font-medium text-(--ink-dim)">
          {LINKS.map(([id, label]) => (
            <a key={id} href={`#${id}`} onClick={(e) => go(e, id)} className="hover:text-(--ink) transition rounded">
              {label}
            </a>
          ))}
        </nav>
        <div className="flex items-center gap-3">
          <a href={REPO} target="_blank" rel="noopener noreferrer" className="btn-outline px-3 py-1.5 text-[13px] gap-2 rounded-full">
            <GitHubIcon />
            <span className="hidden sm:inline">GitHub</span>
          </a>
          <button
            type="button"
            onClick={() => setIsOpen(!isOpen)}
            className="md:hidden! btn-outline p-2 text-(--ink-dim) hover:text-(--ink) rounded-full"
            aria-label="Toggle navigation menu"
            aria-expanded={isOpen}
          >
            {isOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </header>

      {isOpen && (
        <div className="pointer-events-auto mt-2 w-full max-w-6xl card p-5 bg-(--bg)/95 backdrop-blur-xl flex flex-col gap-4 text-[14px] font-medium shadow-2xl md:hidden rounded-2xl">
          {LINKS.map(([id, label]) => (
            <a key={id} href={`#${id}`} onClick={(e) => go(e, id)} className="relative hover:text-(--jelly-300) transition py-1">
              {label}
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
