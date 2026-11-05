import type { Metadata } from 'next';
import { Funnel_Display, Funnel_Sans, JetBrains_Mono } from 'next/font/google';
import { cookies } from 'next/headers';
import './globals.css';
import { Nav } from '@/components/nav';
import { API_URL, COOKIE } from '@/lib/api';

const display = Funnel_Display({ subsets: ['latin'], weight: ['600', '700'], variable: '--font-funnel-display' });
const sans = Funnel_Sans({ subsets: ['latin'], weight: ['400', '500', '600'], variable: '--font-funnel-sans' });
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400'], variable: '--font-jetbrains-mono' });

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
    <html lang="en" dir="ltr" className={`${display.variable} ${sans.variable} ${mono.variable}`}>
      <body className="min-h-screen antialiased">
        {email && <Nav email={email} />}
        <main className={email ? 'mx-auto max-w-6xl px-5 py-10 md:px-14' : ''}>{children}</main>
      </body>
    </html>
  );
}
