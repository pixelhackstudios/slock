import { useEffect, useRef, useState } from 'react';

const DOTS = 9;

/** A strip of maze you can play: the tilt follows the pointer (or ← →), Slock slides and eats. */
function Corridor() {
  const strip = useRef(null);
  const slock = useRef(null);
  const dots = useRef([]);
  const [eaten, setEaten] = useState(0);
  const [pops, setPops] = useState([]);
  const [touch] = useState(() => matchMedia('(pointer: coarse)').matches);

  useEffect(() => {
    const el = strip.current;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const state = dots.current.map((node, i) => ({ node, at: (i + 1) / (DOTS + 1), back: 0 }));
    let tilt = 0, target = 0, keys = 0, x = 0.06, v = 0, squash = 0, raf, last = performance.now(), popId = 0;

    const onMove = (e) => {
      const r = el.getBoundingClientRect();
      if (e.clientY < r.top - 300 || e.clientY > r.bottom + 300) return;   // only when you're near it
      target = Math.max(-1, Math.min(1, (e.clientX - (r.left + r.width / 2)) / (r.width / 2)));
    };
    const onKey = (e) => {
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight')
        keys = e.type === 'keyup' ? 0 : e.key === 'ArrowLeft' ? -1 : 1;
    };

    const frame = (now) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      tilt += ((keys || target) - tilt) * Math.min(1, dt * 8);
      el.style.setProperty('--tilt', `${(tilt * 9).toFixed(2)}deg`);

      // a gentle tilt creeps and a hard tilt slides, like the game
      v += tilt * Math.abs(tilt) * 2.2 * dt;
      v *= Math.pow(0.35, dt);
      x += v * dt;
      const w = el.clientWidth, half = 26 / w;
      if (x < half || x > 1 - half) {
        x = Math.max(half, Math.min(1 - half, x));
        if (Math.abs(v) > 0.08) squash = Math.min(1, Math.abs(v) * 1.6);
        v *= -0.35;
      }
      squash *= Math.pow(0.0005, dt);
      slock.current.style.transform =
        `translateX(${(x * w).toFixed(1)}px) scale(${(1 - squash * 0.3).toFixed(3)}, ${(1 + squash * 0.25).toFixed(3)})`;

      for (const d of state) {
        if (d.back > 0) {
          d.back -= dt;
          if (d.back <= 0) d.node.style.opacity = 1;
          continue;
        }
        if (Math.abs(d.at - x) * w < 24) {
          d.back = 5;
          d.node.style.opacity = 0;
          setEaten((n) => n + 1);
          const id = ++popId;
          setPops((p) => [...p, { id, at: d.at }]);
          setTimeout(() => setPops((p) => p.filter((q) => q.id !== id)), 700);
        }
      }
      raf = requestAnimationFrame(frame);
    };

    window.addEventListener('pointermove', onMove, { passive: true });
    window.addEventListener('keydown', onKey);
    window.addEventListener('keyup', onKey);
    if (reduce) slock.current.style.transform = `translateX(${x * el.clientWidth}px)`;
    else raf = requestAnimationFrame(frame);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('keyup', onKey);
      cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <div>
      <div style={{ perspective: '900px' }}>
        <div
          ref={strip}
          role="img"
          aria-label="A small corridor of the maze. Tilting it makes Slock slide along and eat the pellets."
          className="relative h-24 rounded-md border-y-16 border-t-(--ink-400) border-b-(--ink-500)"
          style={{
            background: `url(${import.meta.env.BASE_URL}media/tile.jpg) 0 0 / 48px 48px`,
            transform: 'rotateX(18deg) rotateY(var(--tilt, 0deg))',
            boxShadow: 'inset 0 12px 16px -6px rgba(0,0,0,.55), 0 24px 34px -14px rgba(0,0,0,.9)',
            touchAction: 'pan-y',
          }}
        >
          {Array.from({ length: DOTS }, (_, i) => (
            <span
              key={i}
              ref={(n) => { dots.current[i] = n; }}
              className="absolute top-1/2 w-3.5 h-3.5 -mt-1.75 -ml-1.75 rounded-full transition-opacity duration-200"
              style={{
                left: `${((i + 1) / (DOTS + 1)) * 100}%`,
                background: 'radial-gradient(circle at 35% 30%, #cfe2ff 0 20%, var(--pellet-400) 55%)',
                boxShadow: '0 0 10px var(--pellet-400)',
              }}
            />
          ))}
          {pops.map((p) => (
            <span key={p.id} className="pellet-pop absolute top-1 font-display text-sm text-(--pellet-300) pointer-events-none" style={{ left: `${p.at * 100}%` }}>
              +1s
            </span>
          ))}
          <div ref={slock} className="jelly absolute top-1/2 left-0 w-13 h-13 -mt-6.5 -ml-6.5 will-change-transform" />
        </div>
      </div>
      <div className="mt-5 flex flex-wrap items-center justify-between gap-3 font-mono text-xs text-(--ink-300)">
        <span>{touch ? 'Drag sideways across the corridor to tilt it.' : 'Move your mouse to tilt it, or use ← →.'}</span>
        <span>Pellets eaten: <span className="text-(--pellet-300)">{eaten}</span></span>
      </div>
    </div>
  );
}

export default function About() {
  return (
    <section id="about" className="max-w-6xl mx-auto px-6 py-14 sm:py-20 border-t border-(--border-soft)">
      <div className="card p-6 sm:p-12 lg:p-14">
        <div className="relative z-10">
          <span className="badge mb-5"><span className="dot-gold"></span>The one rule</span>
          <h2 className="font-display text-2xl sm:text-4xl tracking-tight mt-4 mb-6">
            You don't move <span className="text-gradient-jelly">Slock.</span>
          </h2>
          <div className="grid lg:grid-cols-2 gap-6 lg:gap-12 mb-10 sm:mb-12">
            <p className="text-(--ink-dim) text-base leading-relaxed m-0">
              There's no up, down, left or right button. The mouse (or a gamepad stick) tilts the
              whole maze, and Slock slides wherever the floor slopes. Tilt gently and it creeps.
              Tilt hard and it races.
            </p>
            <p className="text-(--ink-dim) text-base leading-relaxed m-0">
              That's what makes it hard. Slock turns into side openings when you lean toward
              them, but come in too fast and you'll slide right past. Holes and open edges end
              the run. Go on, try a corridor.
            </p>
          </div>
          <Corridor />
        </div>
      </div>
    </section>
  );
}
