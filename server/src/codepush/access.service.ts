import { Injectable } from '@nestjs/common';
import { App, Release } from '@prisma/client';
import { ApiError } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';

/** Ownership checks shared by the CLI API and the dashboard. */
@Injectable()
export class AccessService {
  constructor(private readonly prisma: PrismaService) {}

  async organizationIdsOf(userId: number): Promise<number[]> {
    const m = await this.prisma.membership.findMany({ where: { userId }, select: { organizationId: true } });
    return m.map((x) => x.organizationId);
  }

  async requireOrgMember(userId: number, organizationId: number) {
    const m = await this.prisma.membership.findUnique({ where: { userId_organizationId: { userId, organizationId } } });
    if (!m) throw new ApiError(403, 'forbidden', 'You are not a member of this organization.');
    return m;
  }

  async requireApp(userId: number, appId: string): Promise<App> {
    const app = await this.prisma.app.findUnique({ where: { id: appId } });
    if (!app) throw ApiError.notFound(`App ${appId} not found.`);
    await this.requireOrgMember(userId, app.organizationId).catch(() => {
      throw ApiError.notFound(`App ${appId} not found.`);
    });
    return app;
  }

  async requireRelease(userId: number, appId: string, releaseId: number): Promise<Release> {
    await this.requireApp(userId, appId);
    const release = await this.prisma.release.findFirst({ where: { id: releaseId, appId } });
    if (!release) throw ApiError.notFound(`Release ${releaseId} not found for app ${appId}.`);
    return release;
  }
}
