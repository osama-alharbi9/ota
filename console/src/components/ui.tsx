import Link from 'next/link';
import { ReactNode } from 'react';

/* OTA components (design system section 7). One copper action per screen. */

export const Card = ({ title, children, action }: { title?: string; children: ReactNode; action?: ReactNode }) => (
  <section className="rounded-card border border-ink/12 bg-slate">
    {(title || action) && (
      <header className="flex items-center justify-between gap-4 border-b border-ink/12 px-6 py-4">
        <h2 className="text-[15px] font-semibold leading-[22px]">{title}</h2>
        {action}
      </header>
    )}
    <div className="p-6">{children}</div>
  </section>
);

export const Title = ({ children, sub }: { children: ReactNode; sub?: ReactNode }) => (
  <div>
    <h1 className="font-display text-[32px] font-semibold leading-[37px] tracking-[-0.02em]">{children}</h1>
    {sub && <div className="mt-1 text-[13px] leading-[18px] text-ink/60">{sub}</div>}
  </div>
);

export const Table = ({ head, children, numeric = [] }: { head: string[]; children: ReactNode; numeric?: number[] }) => (
  <div className="overflow-x-auto">
    <table className="w-full text-[15px]">
      <thead>
        <tr className="border-b border-ink/12 text-left text-[12px] font-semibold text-ink/60">
          {head.map((h, i) => (
            <th key={h} className={`py-2 pr-4 font-semibold ${numeric.includes(i) ? 'text-right' : ''}`}>{h}</th>
          ))}
        </tr>
      </thead>
      <tbody className="divide-y divide-ink/12">{children}</tbody>
    </table>
  </div>
);

export const Td = ({ children, mono, right, className = '' }: { children: ReactNode; mono?: boolean; right?: boolean; className?: string }) => (
  <td className={`py-3 pr-4 align-middle ${mono ? 'font-mono text-[13px] leading-[20px]' : ''} ${right ? 'text-right' : ''} ${className}`}>{children}</td>
);

/** State dot: 8 px circle followed by the word. */
export const State = ({ tone, children }: { tone: 'live' | 'waiting' | 'failed' | 'neutral'; children: ReactNode }) => {
  const dot = { live: 'bg-jade', waiting: 'bg-amber', failed: 'bg-rose', neutral: 'bg-ink/35' }[tone];
  return (
    <span className="inline-flex items-center gap-2 whitespace-nowrap text-[13px] leading-[18px]">
      <span className={`inline-block h-2 w-2 rounded-full ${dot}`} />
      {children}
    </span>
  );
};

/** Neutral chip for channel names and similar labels. */
export const Chip = ({ children }: { children: ReactNode }) => (
  <span className="inline-block rounded-input border border-ink/12 bg-indigo/60 px-2 py-0.5 text-[13px] leading-[18px]">{children}</span>
);

export const buttonClass = (variant: 'primary' | 'secondary' | 'danger' = 'secondary') =>
  `inline-flex items-center justify-center whitespace-nowrap rounded-button px-5 py-3 text-[15px] font-semibold leading-[18px] transition-colors disabled:opacity-50 ${
    variant === 'primary'
      ? 'bg-copper text-night hover:bg-copper/90'
      : variant === 'danger'
        ? 'border border-rose/50 text-rose hover:bg-rose/10'
        : 'border border-ink/30 text-ink hover:bg-ink/5'
  }`;

export const smallButtonClass = (variant: 'primary' | 'secondary' | 'danger' = 'secondary') =>
  buttonClass(variant).replace('px-5 py-3', 'px-3 py-1.5').replace('text-[15px]', 'text-[13px]');

export const Code = ({ children }: { children: ReactNode }) => (
  <pre className="overflow-x-auto rounded-input border border-ink/12 bg-night p-4 font-mono text-[13px] leading-[20px] text-ink">{children}</pre>
);

export const Mono = ({ children }: { children: ReactNode }) => <code className="font-mono text-[13px]">{children}</code>;

export const Crumbs = ({ items }: { items: { href?: string; label: string }[] }) => (
  <nav className="mb-6 text-[13px] leading-[18px] text-ink/60">
    {items.map((it, i) => (
      <span key={i}>
        {i > 0 && <span className="mx-2">/</span>}
        {it.href ? <Link href={it.href} className="text-ink/60 hover:text-ink">{it.label}</Link> : <span className="text-ink">{it.label}</span>}
      </span>
    ))}
  </nav>
);

export const inputClass =
  'w-full rounded-input border border-ink/12 bg-night px-3 py-2.5 text-[15px] text-ink placeholder:text-ink/40 outline-none focus:border-cobalt';

export const Muted = ({ children }: { children: ReactNode }) => <p className="text-[13px] leading-[18px] text-ink/60">{children}</p>;
