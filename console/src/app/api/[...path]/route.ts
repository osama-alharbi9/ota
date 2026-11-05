import { NextRequest } from 'next/server';
import { API_URL } from '@/lib/api';

/** Same-origin proxy: /api/<anything> -> API_URL/api/<anything>, cookies both ways. */
async function proxy(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const { path } = await params;
  const url = new URL(`/api/${path.join('/')}${req.nextUrl.search}`, API_URL);
  const headers = new Headers();
  for (const h of ['content-type', 'cookie', 'authorization', 'accept']) {
    const v = req.headers.get(h);
    if (v) headers.set(h, v);
  }
  const res = await fetch(url, {
    method: req.method,
    headers,
    body: req.method === 'GET' || req.method === 'HEAD' ? undefined : await req.arrayBuffer(),
    redirect: 'manual',
    cache: 'no-store',
  });
  const out = new Headers();
  for (const h of ['content-type', 'content-length']) {
    const v = res.headers.get(h);
    if (v) out.set(h, v);
  }
  for (const sc of res.headers.getSetCookie?.() ?? []) out.append('set-cookie', sc);
  return new Response(res.body, { status: res.status, headers: out });
}

export { proxy as GET, proxy as POST, proxy as PUT, proxy as PATCH, proxy as DELETE };
