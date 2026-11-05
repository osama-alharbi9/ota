'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { OtaLockup } from '@/components/brand';
import { call } from '@/lib/client';

export function Nav({ email }: { email: string }) {
  const path = usePathname();
  const router = useRouter();
  const link = (href: string, label: string) => (
    <Link
      href={href}
      className={`rounded-button px-3 py-2 text-[15px] font-medium no-underline hover:no-underline ${path.startsWith(href) ? 'bg-indigo text-ink' : 'text-ink/60 hover:text-ink'}`}
    >
      {label}
    </Link>
  );
  return (
    <header className="border-b border-ink/12">
      <div className="mx-auto flex max-w-6xl items-center gap-2 px-5 py-4 md:px-14">
        <Link href="/apps" className="mr-6 text-ink hover:no-underline" aria-label="ota home">
          <OtaLockup />
        </Link>
        {link('/apps', 'Apps')}
        {link('/account/api-keys', 'API keys')}
        {link('/getting-started', 'Getting started')}
        <span className="ml-auto text-[13px] text-ink/60">{email}</span>
        <button
          className="ml-3 text-[13px] text-ink/60 hover:text-ink"
          onClick={async () => {
            await call('/api/auth/logout', { method: 'POST' });
            router.push('/login');
            router.refresh();
          }}
        >
          Log out
        </button>
      </div>
    </header>
  );
}
