import { Controller, Param, Post, UseGuards } from '@nestjs/common';
import { Prisma, User } from '@prisma/client';
import { ApiKeyGuard, CurrentUser } from '../auth/guards';
import { ApiError } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';
import { AccessService } from './access.service';

/** Script-friendly rollback by release version (same paths as the reference Dart
 *  server), authenticated with an API key. The dashboard uses release ids. */
@Controller('api/admin')
@UseGuards(ApiKeyGuard)
export class AdminController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AccessService,
  ) {}

  @Post('apps/:appId/releases/:version/patches/:number/rollback')
  rollback(@CurrentUser() u: User, @Param('appId') appId: string, @Param('version') version: string, @Param('number') n: string) {
    return this.set(u, appId, version, Number(n), true);
  }

  @Post('apps/:appId/releases/:version/patches/:number/unrollback')
  unrollback(@CurrentUser() u: User, @Param('appId') appId: string, @Param('version') version: string, @Param('number') n: string) {
    return this.set(u, appId, version, Number(n), false);
  }

  private async set(user: User, appId: string, version: string, number: number, rolledBack: boolean) {
    const app = await this.access.requireApp(user.id, appId);
    const release = await this.prisma.release.findUnique({ where: { appId_version: { appId, version } } });
    if (!release) throw ApiError.notFound(`Release ${version} not found.`);
    const patch = await this.prisma.patch.findUnique({ where: { releaseId_number: { releaseId: release.id, number } } });
    if (!patch) throw ApiError.notFound(`Patch ${number} of release ${version} not found.`);
    const updated = await this.prisma.patch.update({ where: { id: patch.id }, data: { isRolledBack: rolledBack } });
    await this.prisma.auditLog.create({
      data: { userId: user.id, organizationId: app.organizationId, action: rolledBack ? 'patch.rollback' : 'patch.restore', target: { app_id: appId, release_version: version, patch_number: number } as Prisma.InputJsonValue },
    });
    return { app_id: appId, release_version: version, patch_number: updated.number, is_rolled_back: updated.isRolledBack };
  }
}
