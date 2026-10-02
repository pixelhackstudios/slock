export default function Teaser() {
  const base = import.meta.env.BASE_URL;
  return (
    <section id="teaser" className="max-w-6xl mx-auto px-6 py-16 sm:py-24 border-t border-(--border-soft) relative">
      <div className="absolute top-1/3 left-1/2 -translate-x-1/2 w-150 h-100 bg-(--brand-jelly) opacity-[0.04] blur-[140px] rounded-full pointer-events-none" />
      <div className="relative z-10 mb-10 sm:mb-12">
        <span className="badge mb-4"><span className="dot-gold"></span>Seventeen seconds</span>
        <h2 className="font-display text-3xl sm:text-5xl tracking-tight mt-4 uppercase leading-[1.1]">
          See it <span className="text-gradient-jelly">slide.</span>
        </h2>
      </div>
      <div className="relative z-10 shot-frame rounded-2xl overflow-hidden border border-(--border-soft) bg-black">
        <video
          className="w-full h-auto block"
          controls
          playsInline
          preload="none"
          poster={`${base}media/teaser-poster.jpg`}
        >
          <source src={`${base}media/slock-teaser.mp4`} type="video/mp4" />
        </video>
      </div>
    </section>
  );
}
