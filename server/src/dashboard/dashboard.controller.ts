import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { Prisma, User } from '@prisma/client';
import * as crypto from 'crypto';

/** Seal input: sha256 over the release's uploaded artifact hashes, sorted. Same
 *  artifacts, same seal. Falls back to app id + version before any upload. */
const sealHash = (appId: string, version: string, hashes: string[]) =>
  crypto.createHash('sha256').update(hashes.length ? [...hashes].sort().join(':') : `${appId}:${version}`).digest('hex');
import { AuthService } from '../auth/auth.service';
import { CurrentUser, SessionGuard } from '../auth/guards';
import { AccessService } from '../codepush/access.service';
import { downloadUrl, wireReleasePatch } from '../codepush/wire';
import { ApiError } from '../common/api-error';
import { iso, jsonSafe } from '../common/serialize';
import { config } from '../config';
import { PrismaService } from '../prisma/prisma.service';

/** JSON API for the Next.js dashboard. Session cookie (or API key) required. */
@Controller('api/dashboard')
@UseGuards(SessionGuard)
export class DashboardController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
    private readonly access: AccessService,
  ) {}

  @Get('overview')
  async overview(@CurrentUser() user: User) {
    const orgs = await this.auth.organizationsOf(user.id);
    return {
      user: { id: user.id, email: user.email, display_name: user.displayName },
      organizations: orgs.map((m) => ({ id: m.organization.id, name: m.organization.name, type: m.organization.type, role: m.role })),
      public_url: config.publicUrl,
    };
  }

  // ------------------------------------------------------------------- apps

  @Get('apps')
  async apps(@CurrentUser() user: User) {
    const orgIds = await this.access.organizationIdsOf(user.id);
    const apps = await this.prisma.app.findMany({
      where: { organizationId: { in: orgIds } },
      orderBy: { createdAt: 'desc' },
      include: {
        organization: true,
        _count: { select: { releases: true } },
        releases: { orderBy: { id: 'desc' }, take: 1, include: { patches: { orderBy: { number: 'desc' }, take: 1 } } },
      },
    });
    return {
      apps: apps.map((a) => ({
        id: a.id,
        display_name: a.displayName,
        organization: { id: a.organization.id, name: a.organization.name },
        release_count: a._count.releases,
        latest_release_version: a.releases[0]?.version ?? null,
        latest_patch_number: a.releases[0]?.patches[0]?.number ?? null,
        created_at: iso(a.createdAt),
      })),
    };
  }

  @Post('apps')
  async createApp(@CurrentUser() user: User, @Body() body: { display_name?: string; organization_id?: number }) {
    const name = body?.display_name?.trim();
    if (!name) throw ApiError.badRequest('display_name is required.');
    const orgId = body.organization_id ?? (await this.auth.organizationsOf(user.id))[0]?.organization.id;
    if (!orgId) throw ApiError.badRequest('No organization.');
    await this.access.requireOrgMember(user.id, orgId);
    const app = await this.prisma.app.create({ data: { id: crypto.randomUUID(), displayName: name, organizationId: orgId } });
    await this.audit(user, orgId, 'app.create', { app_id: app.id, display_name: name });
    return { app: { id: app.id, display_name: app.displayName } };
  }

  @Delete('apps/:appId')
  @HttpCode(204)
  async deleteApp(@CurrentUser() user: User, @Param('appId') appId: string) {
    const app = await this.access.requireApp(user.id, appId);
    await this.prisma.app.delete({ where: { id: appId } });
    await this.audit(user, app.organizationId, 'app.delete', { app_id: appId });
  }

  @Get('apps/:appId')
  async app(@CurrentUser() user: User, @Param('appId') appId: string) {
    const app = await this.access.requireApp(user.id, appId);
    const releases = await this.prisma.release.findMany({
      where: { appId },
      orderBy: { id: 'desc' },
      include: {
        _count: { select: { patches: true, artifacts: true } },
        patches: { orderBy: { number: 'desc' }, take: 1 },
        artifacts: { where: { uploaded: true }, select: { hash: true } },
      },
    });
    const channels = await this.prisma.channel.findMany({ where: { appId }, orderBy: { id: 'asc' } });
    const [checks24h, events24h] = await Promise.all([
      this.prisma.patchCheck.count({ where: { appId, receivedAt: { gte: new Date(Date.now() - 86400e3) } } }),
      this.prisma.patchEvent.count({ where: { appId, receivedAt: { gte: new Date(Date.now() - 86400e3) } } }),
    ]);
    return {
      app: { id: app.id, display_name: app.displayName, organization_id: app.organizationId, created_at: iso(app.createdAt) },
      ota_yaml: `app_id: ${app.id}\nbase_url: ${config.publicUrl}\n`,
      channels: channels.map((c) => ({ id: c.id, name: c.name })),
      stats: { patch_checks_24h: checks24h, events_24h: events24h },
      releases: releases.map((r) => ({
        id: r.id,
        version: r.version,
        flutter_version: r.flutterVersion,
        flutter_revision: r.flutterRevision,
        platform_statuses: r.platformStatuses,
        patch_count: r._count.patches,
        artifact_count: r._count.artifacts,
        latest_patch_number: r.patches[0]?.number ?? null,
        seal_hash: sealHash(appId, r.version, r.artifacts.map((a) => a.hash)),
        created_at: iso(r.createdAt),
        updated_at: iso(r.updatedAt),
      })),
    };
  }

  @Get('apps/:appId/releases/:releaseId')
  async release(@CurrentUser() user: User, @Param('appId') appId: string, @Param('releaseId') releaseId: string) {
    const rid = Number(releaseId);
    const release = await this.access.requireRelease(user.id, appId, rid);
    const artifacts = await this.prisma.releaseArtifact.findMany({ where: { releaseId: rid }, orderBy: { id: 'asc' } });
    const patches = await this.prisma.patch.findMany({
      where: { releaseId: rid },
      orderBy: { number: 'desc' },
      include: { artifacts: { orderBy: { id: 'asc' } }, channels: { include: { channel: true } } },
    });
    const channels = await this.prisma.channel.findMany({ where: { appId }, orderBy: { id: 'asc' } });
    const installs = await this.prisma.patchEvent.groupBy({
      by: ['event'],
      where: { appId, event: { path: ['event', 'release_version'], equals: release.version } },
      _count: true,
    }).catch(() => []);
    return jsonSafe({
      release: {
        id: release.id,
        version: release.version,
        flutter_version: release.flutterVersion,
        flutter_revision: release.flutterRevision,
        display_name: release.displayName,
        notes: release.notes,
        platform_statuses: release.platformStatuses,
        metadata: release.metadata,
        seal_hash: sealHash(appId, release.version, artifacts.filter((a) => a.uploaded).map((a) => a.hash)),
        created_at: iso(release.createdAt),
        updated_at: iso(release.updatedAt),
      },
      artifacts: artifacts.map((a) => ({
        id: a.id, arch: a.arch, platform: a.platform, hash: a.hash, size: Number(a.size), filename: a.filename,
        can_sideload: a.canSideload, uploaded: a.uploaded, download_url: a.uploaded ? downloadUrl('release', a.downloadToken) : null,
        created_at: iso(a.createdAt),
      })),
      patches: patches.map((p) => ({
        ...wireReleasePatch(p),
        created_at: iso(p.createdAt),
        metadata: p.metadata,
        artifacts: p.artifacts.map((a) => ({
          id: a.id, arch: a.arch, platform: a.platform, hash: a.hash, size: Number(a.size), uploaded: a.uploaded,
          signed: a.hashSignature !== null, created_at: iso(a.createdAt),
        })),
      })),
      channels: channels.map((c) => ({ id: c.id, name: c.name })),
      install_event_groups: installs.length,
    });
  }

  @Post('apps/:appId/releases/:releaseId/patches/:number/rollback')
  rollback(@CurrentUser() user: User, @Param('appId') appId: string, @Param('releaseId') releaseId: string, @Param('number') number: string) {
    return this.setRolledBack(user, appId, Number(releaseId), Number(number), true);
  }

  @Post('apps/:appId/releases/:releaseId/patches/:number/unrollback')
  unrollback(@CurrentUser() user: User, @Param('appId') appId: string, @Param('releaseId') releaseId: string, @Param('number') number: string) {
    return this.setRolledBack(user, appId, Number(releaseId), Number(number), false);
  }

  @Post('apps/:appId/releases/:releaseId/patches/:number/promote')
  async promote(
    @CurrentUser() user: User,
    @Param('appId') appId: string,
    @Param('releaseId') releaseId: string,
    @Param('number') number: string,
    @Body() body: { channel?: string },
  ) {
    const app = await this.access.requireApp(user.id, appId);
    const release = await this.access.requireRelease(user.id, appId, Number(releaseId));
    const patch = await this.prisma.patch.findUnique({ where: { releaseId_number: { releaseId: release.id, number: Number(number) } } });
    if (!patch) throw ApiError.notFound('Patch not found.');
    const name = body?.channel?.trim();
    if (!name) throw ApiError.badRequest('channel is required.');
    const channel = await this.prisma.channel.upsert({ where: { appId_name: { appId, name } }, create: { appId, name }, update: {} });
    await this.prisma.$transaction([
      this.prisma.patchChannel.deleteMany({ where: { patchId: patch.id } }),
      this.prisma.patchChannel.create({ data: { patchId: patch.id, channelId: channel.id } }),
    ]);
    await this.audit(user, app.organizationId, 'patch.promote', { app_id: appId, release_version: release.version, patch_number: patch.number, channel: name });
    return { ok: true, channel: name };
  }

  @Get('apps/:appId/activity')
  async activity(@CurrentUser() user: User, @Param('appId') appId: string, @Query('limit') limit?: string) {
    await this.access.requireApp(user.id, appId);
    const take = Math.min(Number(limit) || 50, 500);
    const [checks, events] = await Promise.all([
      this.prisma.patchCheck.findMany({ where: { appId }, orderBy: { id: 'desc' }, take }),
      this.prisma.patchEvent.findMany({ where: { appId }, orderBy: { id: 'desc' }, take }),
    ]);
    return jsonSafe({
      patch_checks: checks.map((c) => ({ id: Number(c.id), received_at: iso(c.receivedAt), request: c.request, response: c.response })),
      events: events.map((e) => ({ id: Number(e.id), received_at: iso(e.receivedAt), event: (e.event as { event?: object })?.event ?? e.event })),
    });
  }

  // --------------------------------------------------------------- api keys

  @Get('api-keys')
  async apiKeys(@CurrentUser() user: User) {
    const keys = await this.auth.listApiKeys(user.id);
    return {
      keys: keys.map((k) => ({
        id: k.id, name: k.name, prefix: k.keyPrefix, created_at: iso(k.createdAt),
        last_used_at: k.lastUsedAt ? iso(k.lastUsedAt) : null, revoked_at: k.revokedAt ? iso(k.revokedAt) : null,
      })),
      public_url: config.publicUrl,
    };
  }

  @Post('api-keys')
  async createApiKey(@CurrentUser() user: User, @Body() body: { name?: string }) {
    const { key, record } = await this.auth.createApiKey(user.id, body?.name ?? 'CLI key');
    return { key, id: record.id, name: record.name, prefix: record.keyPrefix };
  }

  @Delete('api-keys/:id')
  @HttpCode(204)
  async revokeApiKey(@CurrentUser() user: User, @Param('id') id: string) {
    await this.auth.revokeApiKey(user.id, Number(id));
  }

  private async setRolledBack(user: User, appId: string, releaseId: number, number: number, rolledBack: boolean) {
    const app = await this.access.requireApp(user.id, appId);
    const release = await this.access.requireRelease(user.id, appId, releaseId);
    const patch = await this.prisma.patch.findUnique({ where: { releaseId_number: { releaseId: release.id, number } } });
    if (!patch) throw ApiError.notFound(`Patch ${number} of release ${release.version} not found.`);
    const updated = await this.prisma.patch.update({ where: { id: patch.id }, data: { isRolledBack: rolledBack } });
    await this.audit(user, app.organizationId, rolledBack ? 'patch.rollback' : 'patch.restore', {
      app_id: appId, release_version: release.version, patch_number: number,
    });
    return { app_id: appId, release_version: release.version, patch_number: updated.number, is_rolled_back: updated.isRolledBack };
  }

  private audit(user: User, organizationId: number, action: string, target: object) {
    return this.prisma.auditLog.create({ data: { userId: user.id, organizationId, action, target: target as Prisma.InputJsonValue } });
  }
}
