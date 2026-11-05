import { NextRequest, NextResponse } from 'next/server';

const PUBLIC = ['/login', '/register', '/api', '/_next', '/brand', '/icon.svg'];

/** Cheap gate: no session cookie -> login page. The API validates the cookie itself. */
export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  if (PUBLIC.some((p) => pathname.startsWith(p))) return NextResponse.next();
  if (!req.cookies.get('ota_session')) {
    const url = req.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('next', pathname);
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = { matcher: ['/((?!_next/static|_next/image).*)'] };
