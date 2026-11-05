import { Body, Controller, Get, Post, Res, UseGuards } from '@nestjs/common';
import { User } from '@prisma/client';
import { Response } from 'express';
import { config } from '../config';
import { AuthService } from './auth.service';
import { CurrentUser, SessionGuard } from './guards';

const publicUser = (u: User) => ({ id: u.id, email: u.email, display_name: u.displayName, created_at: u.createdAt });

@Controller('api/auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  private setCookie(res: Response, token: string) {
    res.cookie(config.cookieName, token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: config.publicUrl.startsWith('https://'),
      maxAge: 30 * 24 * 3600 * 1000,
      path: '/',
    });
  }

  @Post('register')
  async register(
    @Body() body: { email: string; password: string; display_name?: string },
    @Res({ passthrough: true }) res: Response,
  ) {
    const user = await this.auth.register(body.email ?? '', body.password ?? '', body.display_name);
    this.setCookie(res, this.auth.signSession(user));
    return { user: publicUser(user) };
  }

  @Post('login')
  async login(@Body() body: { email: string; password: string }, @Res({ passthrough: true }) res: Response) {
    const user = await this.auth.login(body.email ?? '', body.password ?? '');
    this.setCookie(res, this.auth.signSession(user));
    return { user: publicUser(user) };
  }

  @Post('logout')
  logout(@Res({ passthrough: true }) res: Response) {
    res.clearCookie(config.cookieName, { path: '/' });
    return { ok: true };
  }

  @Get('me')
  @UseGuards(SessionGuard)
  me(@CurrentUser() user: User) {
    return { user: publicUser(user) };
  }
}
