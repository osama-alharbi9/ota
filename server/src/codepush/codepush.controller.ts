import { Body, Controller, Delete, Get, HttpCode, Param, Patch as HttpPatch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { Prisma, User } from '@prisma/client';
import * as crypto from 'crypto';
import { Request } from 'express';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { AuthService } from '../auth/auth.service';
import { ApiKeyGuard, CurrentUser } from '../auth/guards';
import { ApiError } from '../common/api-error';
import { parseMultipart } from '../common/multipart';
import { iso } from '../common/serialize';
import { config } from '../config';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { AccessService } from './access.service';
import {
  PLATFORMS,
  STATUSES,
  wireApp,
  wireAppMetadata,
  wireChannel,
  wireCreatePatchArtifact,
  wireCreateReleaseArtifact,
  wirePatch,
  wireRelease,
  wireReleaseArtifact,
  wireReleasePatch,
} from './wire';

const token = () => crypto.randomBytes(24).toString('hex');
const int = (s: string, what: string) => {
  const n = Number(s);
  if (!Number.isInteger(n)) throw ApiError.badRequest(`Invalid ${what}: ${s}`);
  return n;
};
const platformOf = (s: string | undefined) => {
  if (!s || !(PLATFORMS as readonly string[]).includes(s)) throw ApiError.badRequest(`Invalid platform: ${s}`);
  return s;
};
const field = (f: Record<string, string>, k: string) => {
  if (f[k] === undefined) throw ApiError.badRequest(`Missing form field "${k}".`);
  return f[k];
};

/** CLI protocol used by the ota CLI. Paths and JSON shapes are fixed by the updater compiled into the engine. */
@Controller('api/v1')
@UseGuards(ApiKeyGuard)
export class CodePushController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly auth: AuthService,
    private readonly access: AccessService,
  ) {}

  // ------------------------------------------------------------ users / orgs

  @Get('users/me')
  me(@CurrentUser() user: User) {
    return {
      id: user.id,
      email: user.email,
      display_name: user.displayName,
      has_active_subscription: true,
      stripe_customer_id: null,
      jwt_issuer: config.publicUrl,
      patch_overage_limit: null,
    };
  }

  @Post('users')
  createUser(@CurrentUser() user: User) {
    return this.me(user);
  }

  @Get('organizations')
  async organizations(@CurrentUser() user: User) {
    const memberships = await this.auth.organizationsOf(user.id);
    return {
      organizations: memberships.map((m) => ({
        organization: {
          id: m.organization.id,
          name: m.organization.name,
          organization_type: m.organization.type,
          created_at: iso(m.organization.createdAt),
          updated_at: iso(m.organization.updatedAt),
        },
        role: m.role,
      })),
    };
  }

  // ------------------------------------------------------------------- apps

  @Get('apps')
  async listApps(@CurrentUser() user: User) {
    const orgIds = await this.access.organizationIdsOf(user.id);
    const apps = await this.prisma.app.findMany({
      where: { organizationId: { in: orgIds } },
      orderBy: { createdAt: 'asc' },
      include: { releases: { orderBy: { id: 'desc' }, take: 1, include: { patches: { orderBy: { number: 'desc' }, take: 1 } } } },
    });
    return {
      apps: apps.map((a) => {
        const latest = a.releases[0];
        return wireAppMetadata(a, latest?.version ?? null, latest?.patches[0]?.number ?? null);
      }),
    };
  }

  @Post('apps')
  async createApp(@CurrentUser() user: User, @Body() body: { display_name?: string; organization_id?: number }) {
    if (!body?.display_name) throw ApiError.badRequest('display_name is required.');
    let orgId = body.organization_id;
    if (orgId === undefined) {
      const first = (await this.auth.organizationsOf(user.id))[0];
      if (!first) throw ApiError.badRequest('User has no organization.');
      orgId = first.organization.id;
    }
    await this.access.requireOrgMember(user.id, orgId);
    const app = await this.prisma.app.create({ data: { id: crypto.randomUUID(), displayName: body.display_name, organizationId: orgId } });
    await this.audit(user, orgId, 'app.create', { app_id: app.id, display_name: app.displayName });
    return wireApp(app);
  }

  @Get('apps/:appId')
  async getApp(@CurrentUser() user: User, @Param('appId') appId: string) {
    const app = await this.access.requireApp(user.id, appId);
    return wireAppMetadata(app, null, null);
  }

  @Delete('apps/:appId')
  @HttpCode(204)
  async deleteApp(@CurrentUser() user: User, @Param('appId') appId: string) {
    const app = await this.access.requireApp(user.id, appId);
    await this.prisma.app.delete({ where: { id: appId } });
    await this.audit(user, app.organizationId, 'app.delete', { app_id: appId });
  }

  // --------------------------------------------------------------- channels

  /** The CLI expects a bare JSON array here, not `{channels: [...]}`. */
  @Get('apps/:appId/channels')
  async listChannels(@CurrentUser() user: User, @Param('appId') appId: string) {
    await this.access.requireApp(user.id, appId);
    const rows = await this.prisma.channel.findMany({ where: { appId }, orderBy: { id: 'asc' } });
    return rows.map(wireChannel);
  }

  @Post('apps/:appId/channels')
  async createChannel(@CurrentUser() user: User, @Param('appId') appId: string, @Body() body: { channel?: string }) {
    await this.access.requireApp(user.id, appId);
    if (!body?.channel) throw ApiError.badRequest('channel is required.');
    const row = await this.prisma.channel.upsert({
      where: { appId_name: { appId, name: body.channel } },
      create: { appId, name: body.channel },
      update: {},
    });
    return wireChannel(row);
  }

  // --------------------------------------------------------------- releases

  @Get('apps/:appId/releases')
  async listReleases(@CurrentUser() user: User, @Param('appId') appId: string, @Query('sideloadable') sideloadable?: string) {
    await this.access.requireApp(user.id, appId);
    const rows = await this.prisma.release.findMany({
      where: { appId, ...(sideloadable === 'true' ? { artifacts: { some: { canSideload: true, uploaded: true } } } : {}) },
      orderBy: { id: 'asc' },
    });
    return { releases: rows.map(wireRelease) };
  }

  @Post('apps/:appId/releases')
  async createRelease(
    @CurrentUser() user: User,
    @Param('appId') appId: string,
    @Body() body: { version?: string; flutter_revision?: string; flutter_version?: string; display_name?: string },
  ) {
    const app = await this.access.requireApp(user.id, appId);
    if (!body?.version || !body.flutter_revision) throw ApiError.badRequest('version and flutter_revision are required.');
    if (await this.prisma.release.findUnique({ where: { appId_version: { appId, version: body.version } } })) {
      throw new ApiError(409, 'release_exists', `Release ${body.version} already exists.`);
    }
    const release = await this.prisma.release.create({
      data: { appId, version: body.version, flutterRevision: body.flutter_revision, flutterVersion: body.flutter_version, displayName: body.display_name },
    });
    await this.audit(user, app.organizationId, 'release.create', { app_id: appId, release_id: release.id, version: release.version });
    return { release: wireRelease(release) };
  }

  @Get('apps/:appId/releases/:releaseId')
  async getRelease(@CurrentUser() user: User, @Param('appId') appId: string, @Param('releaseId') releaseId: string) {
    const release = await this.access.requireRelease(user.id, appId, int(releaseId, 'release id'));
    return { release: wireRelease(release) };
  }

  @HttpPatch('apps/:appId/releases/:releaseId')
  @HttpCode(204)
  async updateRelease(
    @CurrentUser() user: User,
    @Param('appId') appId: string,
    @Param('releaseId') releaseId: string,
    @Body() body: { status?: string; platform?: string; metadata?: object; notes?: string },
  ) {
    const id = int(releaseId, 'release id');
    const release = await this.access.requireRelease(user.id, appId, id);
    const platform = body.platform ? platformOf(body.platform) : undefined;
    const statuses = { ...((release.platformStatuses as Record<string, string>) ?? {}) };
    const metadata = { ...((release.metadata as Record<string, unknown>) ?? {}) };
    if (body.status !== undefined) {
      if (!(STATUSES as readonly string[]).includes(body.status)) throw ApiError.badRequest(`Invalid status: ${body.status}`);
      if (platform) statuses[platform] = body.status;
    }
    if (body.metadata !== undefined) metadata[platform ?? 'unknown'] = body.metadata;
    await this.prisma.release.update({
      where: { id },
      data: {
        platformStatuses: statuses as Prisma.InputJsonValue,
        metadata: metadata as Prisma.InputJsonValue,
        ...(body.notes !== undefined ? { notes: body.notes } : {}),
      },
    });
  }

  // ------------------------------------------------------ release artifacts

  @Get('apps/:appId/releases/:releaseId/artifacts')
  async listReleaseArtifacts(
    @CurrentUser() user: User,
    @Param('appId') appId: string,
    @Param('releaseId') releaseId: string,
    @Query('arch') arch?: string,
    @Query('platform') platform?: string,
  ) {
    const id = int(releaseId, 'release id');
    await this.access.requireRelease(user.id, appId, id);
    const rows = await this.prisma.releaseArtifact.findMany({
      where: { releaseId: id, uploaded: true, ...(arch ? { arch } : {}), ...(platform ? { platform } : {}) },
      orderBy: { id: 'asc' },
    });
    return { artifacts: rows.map(wireReleaseArtifact) };
  }

  @Post('apps/:appId/releases/:releaseId/artifacts')
  async createReleaseArtifact(@CurrentUser() user: User, @Param('appId') appId: string, @Param('releaseId') releaseId: string, @Req() req: Request) {
    const id = int(releaseId, 'release id');
    await this.access.requireRelease(user.id, appId, id);
    const { fields: f } = await parseMultipart(req);
    const arch = field(f, 'arch');
    const platform = platformOf(field(f, 'platform'));
    const hash = field(f, 'hash');
    const size = int(field(f, 'size'), 'size');
    const filename = f.filename ?? `${arch}.bin`;
    const canSideload = f.can_sideload === 'true';
    const podfileLockHash = f.podfile_lock_hash ?? null;

    const existing = await this.prisma.releaseArtifact.findUnique({ where: { releaseId_arch_platform: { releaseId: id, arch, platform } } });
    if (existing?.uploaded) {
      throw new ApiError(409, 'artifact_exists', `An artifact for ${platform}/${arch} already exists for release ${id}.`);
    }
    const row = existing
      ? await this.prisma.releaseArtifact.update({ where: { id: existing.id }, data: { hash, size, filename, canSideload, podfileLockHash } })
      : await this.prisma.releaseArtifact.create({
          data: {
            releaseId: id, arch, platform, hash, size, filename, canSideload, podfileLockHash,
            storageKey: `releases/${appId}/${id}/${platform}/${arch}/${filename}`,
            uploadToken: token(), downloadToken: token(),
          },
        });
    return wireCreateReleaseArtifact(row);
  }

  // ---------------------------------------------------------------- patches

  @Get('apps/:appId/releases/:releaseId/patches')
  async listReleasePatches(@CurrentUser() user: User, @Param('appId') appId: string, @Param('releaseId') releaseId: string) {
    const id = int(releaseId, 'release id');
    await this.access.requireRelease(user.id, appId, id);
    const patches = await this.prisma.patch.findMany({
      where: { releaseId: id },
      orderBy: { number: 'asc' },
      include: { artifacts: { where: { uploaded: true }, orderBy: { id: 'asc' } }, channels: { include: { channel: true } } },
    });
    return { patches: patches.map(wireReleasePatch) };
  }

  @Post('apps/:appId/patches')
  async createPatch(@CurrentUser() user: User, @Param('appId') appId: string, @Body() body: { release_id?: number; metadata?: object }) {
    if (typeof body?.release_id !== 'number') throw ApiError.badRequest('release_id is required.');
    const release = await this.access.requireRelease(user.id, appId, body.release_id);
    const app = await this.access.requireApp(user.id, appId);
    const patch = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT id FROM releases WHERE id = ${release.id} FOR UPDATE`;
      const max = await tx.patch.aggregate({ where: { releaseId: release.id }, _max: { number: true } });
      return tx.patch.create({ data: { releaseId: release.id, number: (max._max.number ?? 0) + 1, metadata: (body.metadata ?? {}) as Prisma.InputJsonValue } });
    });
    await this.audit(user, app.organizationId, 'patch.create', { app_id: appId, release_id: release.id, patch_number: patch.number });
    return wirePatch(patch);
  }

  @Post('apps/:appId/patches/:patchId/artifacts')
  async createPatchArtifact(@CurrentUser() user: User, @Param('appId') appId: string, @Param('patchId') patchId: string, @Req() req: Request) {
    const pid = int(patchId, 'patch id');
    await this.access.requireApp(user.id, appId);
    const patch = await this.prisma.patch.findFirst({ where: { id: pid, release: { appId } } });
    if (!patch) throw ApiError.notFound(`Patch ${pid} not found.`);
    const { fields: f } = await parseMultipart(req);
    const arch = field(f, 'arch');
    const platform = platformOf(field(f, 'platform'));
    const hash = field(f, 'hash');
    const size = int(field(f, 'size'), 'size');
    const existing = await this.prisma.patchArtifact.findUnique({ where: { patchId_arch_platform: { patchId: pid, arch, platform } } });
    if (existing?.uploaded) throw new ApiError(409, 'artifact_exists', `Patch artifact ${platform}/${arch} already exists.`);
    const data = { hash, size, hashSignature: f.hash_signature ?? null, podfileLockHash: f.podfile_lock_hash ?? null };
    const row = existing
      ? await this.prisma.patchArtifact.update({ where: { id: existing.id }, data })
      : await this.prisma.patchArtifact.create({
          data: { patchId: pid, arch, platform, ...data, storageKey: `patches/${appId}/${pid}/${platform}/${arch}/patch.bin`, uploadToken: token(), downloadToken: token() },
        });
    return wireCreatePatchArtifact(row);
  }

  @Post('apps/:appId/patches/promote')
  @HttpCode(204)
  async promote(@CurrentUser() user: User, @Param('appId') appId: string, @Body() body: { patch_id?: number; channel_id?: number }) {
    const app = await this.access.requireApp(user.id, appId);
    if (typeof body?.patch_id !== 'number' || typeof body.channel_id !== 'number') throw ApiError.badRequest('patch_id and channel_id are required.');
    const patch = await this.prisma.patch.findFirst({ where: { id: body.patch_id, release: { appId } } });
    const channel = await this.prisma.channel.findFirst({ where: { id: body.channel_id, appId } });
    if (!patch || !channel) throw ApiError.notFound('Patch or channel not found.');
    await this.prisma.$transaction([
      // A patch lives on exactly one channel (ReleasePatch.channel is singular upstream).
      this.prisma.patchChannel.deleteMany({ where: { patchId: patch.id } }),
      this.prisma.patchChannel.create({ data: { patchId: patch.id, channelId: channel.id } }),
    ]);
    await this.audit(user, app.organizationId, 'patch.promote', { app_id: appId, patch_id: patch.id, patch_number: patch.number, channel: channel.name });
  }

  // ----------------------------------------------------------------- uploads

  @Post('uploads/:kind/:token')
  @HttpCode(204)
  async upload(@CurrentUser() user: User, @Param('kind') kind: string, @Param('token') uploadToken: string, @Req() req: Request) {
    const isRelease = kind === 'release';
    if (!isRelease && kind !== 'patch') throw ApiError.notFound(`Unknown artifact kind ${kind}`);
    const row = isRelease
      ? await this.prisma.releaseArtifact.findUnique({ where: { uploadToken } })
      : await this.prisma.patchArtifact.findUnique({ where: { uploadToken } });
    if (!row) throw ApiError.notFound('Unknown upload URL.');
    const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'upload-'));
    const file = path.join(dir, 'file');
    try {
      const result = await parseMultipart(req, file);
      if (result.fileBytes === undefined) throw ApiError.badRequest('Upload must contain a "file" part.');
      if (BigInt(result.fileBytes) !== row.size) {
        throw new ApiError(400, 'size_mismatch', `Uploaded ${result.fileBytes} bytes, expected ${row.size}.`);
      }
      // Release hashes are sha256 of the uploaded file. Patch hashes are of the inflated
      // output on the device, so only release uploads can be verified here.
      if (isRelease && result.fileSha256 !== row.hash) {
        throw new ApiError(400, 'hash_mismatch', `Uploaded sha256 ${result.fileSha256} != declared ${row.hash}.`);
      }
      await this.storage.putFile(row.storageKey, file);
      if (isRelease) await this.prisma.releaseArtifact.update({ where: { id: row.id }, data: { uploaded: true } });
      else await this.prisma.patchArtifact.update({ where: { id: row.id }, data: { uploaded: true } });
      console.log(`stored ${kind} artifact id=${row.id} ${row.platform}/${row.arch} ${result.fileBytes} bytes -> ${row.storageKey}`);
    } finally {
      await fs.promises.rm(dir, { recursive: true, force: true });
    }
  }

  // ------------------------------------------------------------ diagnostics

  @Get('diagnostics/gcp_upload')
  gcpUpload() {
    return { upload_url: `${config.publicUrl}/api/v1/diagnostics/speedtest_upload` };
  }

  @Get('diagnostics/gcp_download')
  gcpDownload() {
    return { download_url: `${config.publicUrl}/api/v1/diagnostics/speedtest_download` };
  }

  @Post('diagnostics/speedtest_upload')
  @HttpCode(204)
  async speedtestUpload(@Req() req: Request) {
    await new Promise<void>((resolve) => req.on('end', resolve).resume());
  }

  private audit(user: User, organizationId: number, action: string, target: object) {
    return this.prisma.auditLog.create({ data: { userId: user.id, organizationId, action, target: target as Prisma.InputJsonValue } });
  }
}
