import { Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ApiKey, Organization, Role, User } from '@prisma/client';
import { ApiError } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';
import { generateApiKey, hashApiKey, hashPassword, keyPrefixForDisplay, verifyPassword } from './keys';

export interface SessionUser {
  id: number;
  email: string;
  displayName: string | null;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  private normEmail(email: string) {
    return email.trim().toLowerCase();
  }

  async register(email: string, password: string, displayName?: string): Promise<User> {
    email = this.normEmail(email);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw ApiError.badRequest('Invalid email address.');
    if (password.length < 8) throw ApiError.badRequest('Password must be at least 8 characters.');
    if (await this.prisma.user.findUnique({ where: { email } })) {
      throw new ApiError(409, 'email_taken', 'An account with this email already exists.');
    }
    const name = displayName?.trim() || email.split('@')[0];
    return this.prisma.user.create({
      data: {
        email,
        displayName: name,
        passwordHash: hashPassword(password),
        memberships: {
          create: { role: Role.owner, organization: { create: { name: `${name}'s organization`, type: 'personal' } } },
        },
      },
    });
  }

  async login(email: string, password: string): Promise<User> {
    const user = await this.prisma.user.findUnique({ where: { email: this.normEmail(email) } });
    if (!user || !verifyPassword(password, user.passwordHash)) {
      throw ApiError.unauthorized('Wrong email or password.');
    }
    return user;
  }

  signSession(user: User): string {
    return this.jwt.sign({ sub: user.id, email: user.email }, { expiresIn: '30d' });
  }

  async userFromSession(token: string): Promise<User | null> {
    try {
      const payload = this.jwt.verify<{ sub: number }>(token);
      return this.prisma.user.findUnique({ where: { id: payload.sub } });
    } catch {
      return null;
    }
  }

  async userFromApiKey(key: string): Promise<{ user: User; apiKey: ApiKey } | null> {
    const apiKey = await this.prisma.apiKey.findUnique({ where: { keyHash: hashApiKey(key) }, include: { user: true } });
    if (!apiKey || apiKey.revokedAt) return null;
    const stale = !apiKey.lastUsedAt || Date.now() - apiKey.lastUsedAt.getTime() > 60_000;
    if (stale) {
      void this.prisma.apiKey.update({ where: { id: apiKey.id }, data: { lastUsedAt: new Date() } }).catch(() => undefined);
    }
    return { user: apiKey.user, apiKey };
  }

  async createApiKey(userId: number, name: string): Promise<{ key: string; record: ApiKey }> {
    const key = generateApiKey();
    const record = await this.prisma.apiKey.create({
      data: { userId, name: name.trim() || 'CLI key', keyHash: hashApiKey(key), keyPrefix: keyPrefixForDisplay(key) },
    });
    return { key, record };
  }

  /** Registers a pre-shared key (e.g. API_TOKEN from .env) for a user, once. */
  async ensureApiKey(userId: number, key: string, name: string) {
    const keyHash = hashApiKey(key);
    const existing = await this.prisma.apiKey.findUnique({ where: { keyHash } });
    if (existing) return existing;
    return this.prisma.apiKey.create({ data: { userId, name, keyHash, keyPrefix: keyPrefixForDisplay(key) } });
  }

  listApiKeys(userId: number) {
    return this.prisma.apiKey.findMany({ where: { userId }, orderBy: { createdAt: 'desc' } });
  }

  async revokeApiKey(userId: number, id: number) {
    const k = await this.prisma.apiKey.findFirst({ where: { id, userId } });
    if (!k) throw ApiError.notFound('API key not found.');
    return this.prisma.apiKey.update({ where: { id }, data: { revokedAt: new Date() } });
  }

  organizationsOf(userId: number): Promise<{ organization: Organization; role: Role }[]> {
    return this.prisma.membership.findMany({ where: { userId }, include: { organization: true }, orderBy: { organizationId: 'asc' } });
  }
}
