import { Injectable, OnApplicationBootstrap } from '@nestjs/common';
import { AuthService } from './auth/auth.service';
import { config } from './config';
import { PrismaService } from './prisma/prisma.service';

/** First start: create the admin from BOOTSTRAP_EMAIL/PASSWORD and register the
 *  legacy static API_TOKEN as that user's key, so the existing scripts keep working. */
@Injectable()
export class BootstrapService implements OnApplicationBootstrap {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
  ) {}

  async onApplicationBootstrap() {
    const { email, password, apiToken } = config.bootstrap;
    let user = email ? await this.prisma.user.findUnique({ where: { email: email.toLowerCase() } }) : null;
    if (!user && email && password) {
      user = await this.auth.register(email, password, 'Admin');
      console.log(`bootstrap: created admin user ${email}`);
    }
    if (!user) user = await this.prisma.user.findFirst({ orderBy: { id: 'asc' } });
    if (user && apiToken) {
      const key = await this.auth.ensureApiKey(user.id, apiToken, 'API_TOKEN from .env');
      console.log(`bootstrap: API_TOKEN registered as key #${key.id} for ${user.email}`);
    }
    if (!user) console.log('bootstrap: no users yet; register at /api/auth/register or set BOOTSTRAP_EMAIL/BOOTSTRAP_PASSWORD');
  }
}
