import { useEffect, useRef } from 'react';
import gsap from 'gsap';
import { useGSAP } from '@gsap/react';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';
import 'lenis/dist/lenis.css';
import Header from './components/Header';
import Hero from './components/Hero';
import About from './components/About';
import Features from './components/Features';
import Teaser from './components/Teaser';
import Download from './components/Download';
import Contribute from './components/Contribute';
import Footer from './components/Footer';

gsap.registerPlugin(ScrollTrigger);

export default function App() {
  const containerRef = useRef(null);

  useEffect(() => {
    const lenis = new Lenis({
      duration: 1.2,
      easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
      smoothWheel: true,
    });
    window.lenis = lenis;
    lenis.on('scroll', ScrollTrigger.update);
    const tick = (time) => lenis.raf(time * 1000);
    gsap.ticker.add(tick);
    gsap.ticker.lagSmoothing(0);
    return () => {
      gsap.ticker.remove(tick);
      lenis.destroy();
      delete window.lenis;
    };
  }, []);

  useGSAP(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    gsap.from('.hero-left-content > *', { opacity: 0, y: 30, duration: 0.8, stagger: 0.15, ease: 'power3.out' });
    // Slock drops onto his tile, the way he lands in the game
    gsap.from('.hero-right-content', { opacity: 0, y: -120, duration: 0.9, ease: 'bounce.out', delay: 0.3 });
  }, { scope: containerRef });

  return (
    <div ref={containerRef} className="noise min-h-screen bg-(--bg) text-(--ink) antialiased">
      <Header />
      <main>
        <Hero />
        <About />
        <Features />
        <Teaser />
        <Download />
        <Contribute />
      </main>
      <Footer />
    </div>
  );
}
