import { useEffect, useRef } from 'react';
import { scrollToId } from '@/lib/release';

/** Slock on a single floor tile that tilts toward the pointer: the whole game in one picture. */
function TiltTile() {
  const tile = useRef(null);
  const block = useRef(null);
  const shadow = useRef(null);

  useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let tx = 0, ty = 0, x = 0, y = 0, raf;
    const onMove = (e) => {
      const r = tile.current.getBoundingClientRect();
      tx = Math.max(-1, Math.min(1, (e.clientX - (r.left + r.width / 2)) / (window.innerWidth / 2)));
      ty = Math.max(-1, Math.min(1, (e.clientY - (r.top + r.height / 2)) / (window.innerHeight / 2)));
    };
    const tick = () => {
      x += (tx - x) * 0.08;
      y += (ty - y) * 0.08;
      tile.current.style.transform = `rotateX(${55 - y * 10}deg) rotateZ(${-35 + x * 6}deg) rotateY(${x * 10}deg)`;
      // Slock slides downhill, the way the tilt points
      block.current.style.translate = `${x * 34}% ${y * 34}%`;
      shadow.current.style.translate = `${x * 26}% ${y * 26}%`;
      raf = requestAnimationFrame(tick);
    };
    window.addEventListener('pointermove', onMove, { passive: true });
    raf = requestAnimationFrame(tick);
    return () => {
      window.removeEventListener('pointermove', onMove);
      cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <div className="relative w-72 h-72 sm:w-80 sm:h-80 lg:w-90 lg:h-90" style={{ perspective: '900px' }}>
      <div
        ref={tile}
        className="absolute inset-[8%] rounded-[1.4rem] border border-(--ink-400)/50"
        style={{
          transform: 'rotateX(55deg) rotateZ(-35deg)',
          transformStyle: 'preserve-3d',
          background: `url(${import.meta.env.BASE_URL}media/tile.jpg) 0 0 / 50% 50%`,
          boxShadow: '0 40px 60px -20px rgba(0,0,0,.9), inset 0 0 0 1px rgba(255,255,255,.08)',
        }}
      >
        <div className="absolute inset-0 grid place-items-center" style={{ transformStyle: 'preserve-3d' }}>
          <div
            ref={shadow}
            className="absolute w-36 h-36 rounded-[30%]"
            style={{ background: 'radial-gradient(closest-side, rgba(70,0,10,.55), transparent)', filter: 'blur(6px)' }}
          />
          <div ref={block} style={{ transform: 'translateZ(66px) rotateZ(35deg) rotateX(-55deg)' }}>
            <div className="jelly wobble w-28 h-28 sm:w-32 sm:h-32" />
          </div>
        </div>
      </div>
    </div>
  );
}

export default function Hero() {
  return (
    <section id="top" className="relative overflow-hidden">
      <div className="max-w-6xl mx-auto px-6 pt-28 sm:pt-40 pb-16 sm:pb-24 grid lg:grid-cols-[1.35fr_0.65fr] gap-10 items-center">
        <div className="hero-left-content">
          <div className="flex flex-wrap items-center gap-2 mb-7">
            <span className="badge"><span className="dot"></span>Free · MIT</span>
            <span className="badge">Windows · Mac · Linux</span>
            <span className="badge">made in Godot 4</span>
          </div>
          <h1 className="font-display text-[1.85rem] sm:text-[2.7rem] lg:text-[3rem] leading-[1.08] tracking-tight">
            Tilt <span className="text-gradient-gold">the world.</span><br className="hidden sm:inline" />{' '}
            Slide <span className="text-gradient-jelly">the jelly.</span>
          </h1>
          <p className="mt-6 text-base sm:text-lg text-(--ink-dim) max-w-xl leading-relaxed">
            Slock is a free, open-source game about a red jelly block lost in an endless maze.
            You don't move the block. You tilt the whole world and it slides. Eat the pellets,
            beat the clock, dodge the Swurms, and keep climbing.
          </p>
          <div className="mt-8 sm:mt-9 flex flex-col sm:flex-row items-stretch sm:items-center gap-3.5 sm:gap-4">
            <a href="#teaser" onClick={(e) => scrollToId(e, 'teaser')} className="btn-outline px-6 py-3.5 text-[15px] text-center">See it slide</a>
            <a href="#download" onClick={(e) => scrollToId(e, 'download')} className="btn-primary px-6 py-3.5 text-[15px] text-center">Get Slock →</a>
          </div>
        </div>

        <div className="flex flex-col items-center justify-center hero-right-content mt-6 lg:mt-0">
          <TiltTile />
          <div className="w-72 sm:w-80 lg:w-90 bg-(--ink-800) backdrop-blur-sm border border-(--border-soft) rounded-xl px-4 py-3 text-xs font-mono text-(--ink-dim) text-center shadow-lg -mt-6 relative z-10">
            Slock never moves. <span className="text-(--gold-300)">You</span> move everything else.
          </div>
        </div>
      </div>
    </section>
  );
}
