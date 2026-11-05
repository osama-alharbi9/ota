import { cookies } from 'next/headers';

export const API_URL = process.env.API_URL ?? 'http://localhost:8080';
export const COOKIE = 'ota_session';

export class ApiFailure extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

/** Server-side fetch to the API, forwarding the session cookie. */
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const jar = await cookies();
  const session = jar.get(COOKIE)?.value;
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: { ...(init.headers ?? {}), ...(session ? { cookie: `${COOKIE}=${session}` } : {}) },
    cache: 'no-store',
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { code?: string; message?: string };
    throw new ApiFailure(res.status, body.code ?? 'error', body.message ?? res.statusText);
  }
  return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
}

export const fmtBytes = (n: number) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)} MB` : n >= 1e3 ? `${(n / 1e3).toFixed(1)} KB` : `${n} B`);
export const fmtDate = (s: string) => new Date(s).toLocaleString();
