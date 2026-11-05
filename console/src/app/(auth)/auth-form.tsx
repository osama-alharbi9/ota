'use client';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState } from 'react';
import { OtaLockup } from '@/components/brand';
import { buttonClass, inputClass } from '@/components/ui';
import { call } from '@/lib/client';

export function AuthForm({ mode }: { mode: 'login' | 'register' }) {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await call(`/api/auth/${mode}`, { method: 'POST', body: JSON.stringify({ email, password, display_name: name || undefined }) });
      router.push(params.get('next') || '/apps');
      router.refresh();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen">
      <div className="flex flex-1 items-center px-5 md:px-14">
        <div className="w-full max-w-sm">
          <OtaLockup className="mb-12 block text-[32px] text-ink" />
          <h1 className="font-display text-[32px] font-semibold leading-[37px] tracking-[-0.02em]">{mode === 'login' ? 'Sign in' : 'Create your account'}</h1>
          <p className="mb-8 mt-2 text-ink/60">Over-the-air updates for your Flutter and React Native apps.</p>
          <form onSubmit={submit} className="space-y-3">
            {mode === 'register' && <input className={inputClass} placeholder="Your name" value={name} onChange={(e) => setName(e.target.value)} />}
            <input className={inputClass} type="email" placeholder="Email" required value={email} onChange={(e) => setEmail(e.target.value)} />
            <input className={inputClass} type="password" placeholder="Password, 8 characters or more" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
            {error && <p className="text-[13px] text-rose">{error}</p>}
            <button className={`${buttonClass('primary')} w-full`} disabled={busy}>
              {busy ? 'Please wait…' : mode === 'login' ? 'Sign in' : 'Create account'}
            </button>
          </form>
          <p className="mt-6 text-[13px] text-ink/60">
            {mode === 'login' ? (
              <>No account? <Link href="/register">Register</Link></>
            ) : (
              <>Have an account? <Link href="/login">Sign in</Link></>
            )}
          </p>
        </div>
      </div>
    </div>
  );
}
