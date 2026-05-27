import { useEffect, useRef } from 'react';
import { gsap } from 'gsap';

const GOLD_ORBS = [
  { w: 480, h: 480, top: '5%',  left: '5%',  color: 'rgba(255,215,0,0.16)' },
  { w: 320, h: 320, top: '55%', left: '58%', color: 'rgba(253,185,49,0.12)' },
  { w: 200, h: 200, top: '25%', left: '72%', color: 'rgba(255,240,130,0.08)' },
];

const OBSIDIAN_ORBS = [
  { w: 520, h: 520, top: '2%',  left: '8%',  color: 'rgba(157,0,255,0.13)' },
  { w: 360, h: 360, top: '52%', left: '55%', color: 'rgba(94,0,179,0.10)' },
  { w: 240, h: 240, top: '20%', left: '68%', color: 'rgba(184,77,255,0.07)' },
];

export default function AdminGlowEffects({ theme }) {
  const containerRef = useRef(null);
  const orbs = theme === 'gold' ? GOLD_ORBS : OBSIDIAN_ORBS;

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const els = container.querySelectorAll('.glow-orb');
    const ctx = gsap.context(() => {
      els.forEach((el, i) => {
        gsap.to(el, {
          x: `random(-60, 60)`,
          y: `random(-60, 60)`,
          duration: gsap.utils.random(10, 20),
          ease: 'sine.inOut',
          repeat: -1,
          yoyo: true,
          delay: i * 2,
        });
        gsap.to(el, {
          opacity: gsap.utils.random(0.6, 1),
          duration: gsap.utils.random(4, 8),
          ease: 'sine.inOut',
          repeat: -1,
          yoyo: true,
          delay: i * 1.2,
        });
      });
    }, container);

    return () => ctx.revert();
  }, [theme]);

  return (
    <div
      ref={containerRef}
      style={{
        position: 'absolute',
        inset: 0,
        pointerEvents: 'none',
        zIndex: 0,
        overflow: 'hidden',
      }}
      aria-hidden="true"
    >
      {orbs.map((orb, i) => (
        <div
          key={i}
          className="glow-orb"
          style={{
            position: 'absolute',
            top: orb.top,
            left: orb.left,
            width: orb.w,
            height: orb.h,
            borderRadius: '50%',
            background: `radial-gradient(circle, ${orb.color} 0%, transparent 70%)`,
            filter: 'blur(50px)',
          }}
        />
      ))}
    </div>
  );
}
