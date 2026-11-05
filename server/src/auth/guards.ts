import { CanActivate, ExecutionContext, Injectable, createParamDecorator } from '@nestjs/common';
import { User } from '@prisma/client';
import { Request } from 'express';
import { ApiError } from '../common/api-error';
import { config } from '../config';
import { AuthService } from './auth.service';

export type AuthedRequest = Request & { user?: User; authKind?: 'api_key' | 'session' };

/** `Authorization: Bearer ota_...` for the CLI protocol. */
@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}
  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers.authorization ?? '';
    const key = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!key) throw ApiError.unauthorized('Missing API token.');
    const found = await this.auth.userFromApiKey(key);
    if (!found) throw ApiError.unauthorized('Invalid or revoked API token.');
    req.user = found.user;
    req.authKind = 'api_key';
    return true;
  }
}

/** JWT session cookie for the dashboard; also accepts an API key bearer. */
@Injectable()
export class SessionGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}
  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const cookie = (req.cookies as Record<string, string> | undefined)?.[config.cookieName];
    if (cookie) {
      const user = await this.auth.userFromSession(cookie);
      if (user) {
        req.user = user;
        req.authKind = 'session';
        return true;
      }
    }
    const header = req.headers.authorization ?? '';
    if (header.startsWith('Bearer ')) {
      const found = await this.auth.userFromApiKey(header.slice(7).trim());
      if (found) {
        req.user = found.user;
        req.authKind = 'api_key';
        return true;
      }
    }
    throw ApiError.unauthorized('Not signed in.');
  }
}

export const CurrentUser = createParamDecorator((_data: unknown, ctx: ExecutionContext): User => {
  const req = ctx.switchToHttp().getRequest<AuthedRequest>();
  if (!req.user) throw ApiError.unauthorized();
  return req.user;
});
