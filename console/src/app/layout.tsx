import type { Metadata } from 'next';
import { cookies } from 'next/headers';
import './globals.css';
import { Nav } from '@/components/nav';
import { API_URL, COOKIE } from '@/lib/api';

export const metadata: Metadata = { title: { default: 'ota', template: '%s · ota' }, description: 'Over-the-air updates for Flutter and React Native apps.' };

async function currentEmail(): Promise<string | null> {
  const session = (await cookies()).get(COOKIE)?.value;
  if (!session) return null;
  const res = await fetch(`${API_URL}/api/auth/me`, { headers: { cookie: `${COOKIE}=${session}` }, cache: 'no-store' }).catch(() => null);
  if (!res?.ok) return null;
  const body = (await res.json()) as { user: { email: string } };
  return body.user.email;
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const email = await currentEmail();
  return (
    <html lang="en" dir="ltr">
      <body className="min-h-screen antialiased">
        {email && <Nav email={email} />}
        <main className={email ? 'mx-auto max-w-6xl px-5 py-10 md:px-14' : ''}>{children}</main>
      </body>
    </html>
  );
}
