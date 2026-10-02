import { CheckCircle2, Move, Timer, Bug, Infinity as Endless } from 'lucide-react';
import gameplay from '@shots/gameplay.jpg';
import sideRoom from '@shots/side-room.jpg';
import powerMode from '@shots/power-mode.jpg';
import deepSection from '@shots/deep-section.jpg';

const SECTIONS = [
  {
    num: '01',
    badge: 'How it moves',
    title: [['gold', 'Tilt gently.'], ['', ' Creep.'], ['br'], ['jelly', 'Tilt hard.'], ['', ' Slide.']],
    blurb: 'Every run is a balancing act between going fast enough and not going over the edge.',
    shot: gameplay,
    alt: 'Slock, a red jelly block, sliding through a white tiled maze full of blue pellets',
    icon: Move,
    footer: 'Mouse or gamepad left stick. That\'s the whole control scheme.',
    groups: [
      { label: 'Moving', items: [['Creep or slide', 'Tilt the other way to slow down.'], ['Turn by leaning', 'Slock turns into openings you tilt toward.']] },
      { label: 'Watch out', items: [['Holes and open edges', 'Fall off and the run is over.'], ['Too fast to turn', 'Overshoot and you slide right past.']] },
    ],
  },
  {
    num: '02',
    badge: 'Tick, tock',
    title: [['gold', 'Feed'], ['', ' the clock.'], ['br'], ['jelly', 'Eat'], ['', ' everything.']],
    blurb: 'You start with 35 seconds. Every pellet buys a little more, and every gate opens the next section.',
    shot: sideRoom,
    alt: 'A side room of the maze full of gold pellets',
    icon: Timer,
    footer: 'Side rooms hide gold. Worth the detour, if you\'ve got the time.',
    groups: [
      { label: 'Time', items: [['Blue pellet', '+1 second.'], ['Small yellow pellet', '+2 seconds.'], ['Clock pickup', '+20 seconds.']] },
      { label: 'Gates', items: [['Eat every pellet', 'Or find the key, and the gate opens.'], ['No going back', 'The way behind you seals shut.']] },
    ],
  },
  {
    num: '03',
    badge: 'Things that crawl',
    title: [['', 'Mind the '], ['jelly', 'Slorms.'], ['br'], ['', 'Then '], ['gold', 'eat them.']],
    blurb: 'Green worms crawl out of the pen one at a time, and every new section has one more.',
    shot: powerMode,
    alt: 'Power mode: a blue, edible Slorm in a corridor surrounded by pellets',
    icon: Bug,
    footer: 'Slugs are for emergencies. A miss still costs one.',
    groups: [
      { label: 'Slorms', items: [['Touch one, lose a third', 'It steals your time and knocks you back.'], ['Grab a power gem', 'They turn blue. Eat them to win it all back.']] },
      { label: 'Slugs', items: [['Click to freeze and aim', 'There\'s no backing out.'], ['Click again to fire', 'Destroy a Slorm or blast open a wall block.']] },
    ],
  },
  {
    num: '04',
    badge: 'Climb forever',
    title: [['gold', 'Bigger.'], ['', ' Smaller.'], ['br'], ['jelly', 'Endless.']],
    blurb: 'Every section is bigger, with smaller blocks, more Slorms and more holes. Slock shrinks to fit.',
    shot: deepSection,
    alt: 'A deeper section of the maze with smaller blocks and a denser layout',
    icon: Endless,
    footer: 'Three powerups per section. Take one and another turns up ten seconds later.',
    groups: [
      { label: 'Powerups', items: [['Slock of Steel', 'Smash inner walls and Slorms for 10 seconds.'], ['Close Traps', 'Every hole and gap in the walls sealed.']] },
      { label: 'Also', items: [['Clear Dots', 'A quarter of the pellets vanish.'], ['Refresh and Extra Slug', 'Refill your slugs, or carry one more.']] },
    ],
  },
];

function Title({ parts }) {
  return parts.map(([kind, text], i) => {
    if (kind === 'br') return <br key={i} />;
    if (kind) return <span key={i} className={`text-gradient-${kind}`}>{text}</span>;
    return <span key={i}>{text}</span>;
  });
}

function FeatureCard({ groups, footer, icon: Icon }) {
  return (
    <div className="card p-6 sm:p-8 flex flex-col justify-between">
      <div className="relative z-10 space-y-6 sm:space-y-8">
        {groups.map((group) => (
          <div key={group.label}>
            <div className="font-bold text-xs tracking-wider text-(--jelly-300) uppercase mb-3 sm:mb-4">{group.label}</div>
            <div className="space-y-3.5 sm:space-y-4">
              {group.items.map(([name, desc]) => (
                <div key={name}>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <span className="dot shrink-0"></span>
                      <span className="text-(--ink-50) text-[14px] sm:text-[15px] font-medium leading-snug">{name}</span>
                    </div>
                    <CheckCircle2 className="w-4 h-4 text-(--slorm-300) opacity-70 shrink-0" />
                  </div>
                  <p className="pl-6 text-[12px] sm:text-[13px] text-(--ink-200) mt-0.5 mb-0">{desc}</p>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="relative z-10 mt-8 pt-6 border-t border-(--border-soft) flex items-center gap-3">
        <Icon className="w-5 h-5 text-(--ink-400) shrink-0" />
        <span className="text-[13px] text-(--ink-400)">{footer}</span>
      </div>
    </div>
  );
}

/** Three pellets in a row: the section divider, like the eggs on chickenbutt.dev. */
function Spacer() {
  return (
    <div className="my-10 sm:my-20 flex items-center justify-center gap-4" aria-hidden="true">
      <div className="h-px flex-1 bg-linear-to-r from-transparent via-(--border-soft) to-transparent" />
      <div className="flex gap-2.5 px-4 opacity-25">
        {[0, 1, 2].map((i) => <span key={i} className="w-2.5 h-2.5 rounded-full bg-(--pellet-300)" />)}
      </div>
      <div className="h-px flex-1 bg-linear-to-r from-transparent via-(--border-soft) to-transparent" />
    </div>
  );
}

export default function Features() {
  return (
    <section id="play" className="max-w-6xl mx-auto px-6 py-10 sm:py-16 mt-6 sm:mt-10 border-t border-(--border-soft)">
      {SECTIONS.map((s, i) => {
        const flip = i % 2 === 1;
        return (
          <div key={s.num}>
            {i > 0 && <Spacer />}
            <div className="mb-12 sm:mb-16 flex items-start justify-between gap-4">
              <div>
                <span className="badge mb-4"><span className="dot-slorm"></span>{s.badge}</span>
                <h2 className="font-display text-3xl sm:text-5xl tracking-tight mt-4 uppercase leading-[1.1]">
                  <Title parts={s.title} />
                </h2>
                <p className="mt-4 sm:mt-5 text-(--ink-dim) text-base sm:text-lg leading-relaxed max-w-2xl">{s.blurb}</p>
              </div>
              <span className="font-display text-6xl sm:text-8xl lg:text-9xl text-white opacity-[0.03] select-none pointer-events-none shrink-0 leading-none">
                {s.num}
              </span>
            </div>
            <div className={`grid gap-6 lg:gap-12 items-center ${flip ? 'lg:grid-cols-[minmax(0,0.7fr)_minmax(0,1.3fr)]' : 'lg:grid-cols-[minmax(0,1.3fr)_minmax(0,0.7fr)]'}`}>
              <figure className={`m-0 ${flip ? 'order-first lg:order-last' : ''}`}>
                <div className="shot-frame rounded-2xl overflow-hidden bg-(--ink-800)">
                  <img src={s.shot} alt={s.alt} className="w-full h-auto block" loading="lazy" width="1920" height="1080" />
                </div>
              </figure>
              <FeatureCard groups={s.groups} footer={s.footer} icon={s.icon} />
            </div>
          </div>
        );
      })}
    </section>
  );
}
