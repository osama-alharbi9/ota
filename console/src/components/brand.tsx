import type { HTMLAttributes } from 'react';

export function OtaLockup({ className = '', ...props }: HTMLAttributes<HTMLSpanElement>) {
  return (
    <span className={`inline-flex items-center font-display text-[24px] font-bold leading-none tracking-[-0.02em] ${className}`} {...props}>
      ota
    </span>
  );
}
