/**
 * Release seal (design system section 8): a marble generated from a hash.
 * Same hash, same seal. Square, 8 px corners, sizes 24/32/44/64 (96 on the
 * release page).
 *
 * v1 approximation of the reference renderer: hash-seeded colour bands in
 * night/indigo/cobalt/violet with one copper streak, advected by a seeded
 * turbulence field. Deterministic, server-rendered, no JavaScript.
 */
const PALETTE = ['#050507', '#1b1f5a', '#1f4fd1', '#6f3fd6', '#1b1f5a', '#050507'];
const COPPER = '#c2703a';

function seededRandom(hash: string) {
  let h = 2166136261;
  for (let i = 0; i < hash.length; i++) {
    h ^= hash.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  let a = h >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function Seal({ hash, size = 32, title }: { hash: string; size?: 24 | 32 | 44 | 64 | 96; title?: string }) {
  const rnd = seededRandom(hash || 'empty');
  const id = `seal-${(hash || 'x').slice(0, 12)}-${size}`;
  const angle = Math.floor(rnd() * 180);
  const bands: { y: number; h: number; color: string }[] = [];
  let y = -40;
  while (y < 140) {
    const h = 6 + rnd() * 18;
    bands.push({ y, h, color: PALETTE[Math.floor(rnd() * PALETTE.length)] });
    y += h;
  }
  const copperY = 20 + rnd() * 60;
  const seed = Math.floor(rnd() * 10000);
  const freq = (0.012 + rnd() * 0.02).toFixed(4);
  const scale = Math.round(28 + rnd() * 30);
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" role="img" aria-label={title ?? `Seal ${hash.slice(0, 8)}`} className="shrink-0">
      <defs>
        <clipPath id={`${id}-clip`}>
          <rect width="100" height="100" rx={(8 / size) * 100} />
        </clipPath>
        <filter id={`${id}-marble`} x="-20%" y="-20%" width="140%" height="140%">
          <feTurbulence type="fractalNoise" baseFrequency={freq} numOctaves="2" seed={seed} result="noise" />
          <feDisplacementMap in="SourceGraphic" in2="noise" scale={scale} xChannelSelector="R" yChannelSelector="G" />
        </filter>
      </defs>
      <g clipPath={`url(#${id}-clip)`}>
        <rect width="100" height="100" fill="#050507" />
        <g filter={`url(#${id}-marble)`} transform={`rotate(${angle} 50 50)`}>
          {bands.map((b, i) => (
            <rect key={i} x="-40" y={b.y} width="180" height={b.h + 0.5} fill={b.color} />
          ))}
          <rect x="-40" y={copperY} width="180" height={2.2 + rnd() * 2} fill={COPPER} />
        </g>
      </g>
    </svg>
  );
}
