import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { downloadUrl } from './wire';

export interface PatchCheckRequest {
  app_id: string;
  channel: string;
  release_version: string;
  platform: string;
  arch: string;
  client_id?: string;
  patch_number?: number;
  current_patch_number?: number;
}

export interface PatchCheckResponse {
  patch_available: boolean;
  patch: { number: number; download_url: string; hash: string; hash_signature: string | null } | null;
  rolled_back_patch_numbers: number[] | null;
}

/** Port of `_computePatchCheck` from the Dart reference server. */
@Injectable()
export class PatchCheckService {
  constructor(private readonly prisma: PrismaService) {}

  async compute(req: PatchCheckRequest): Promise<PatchCheckResponse> {
    const release = await this.prisma.release.findFirst({
      where: { appId: req.app_id, version: req.release_version },
      select: { id: true },
    });
    if (!release) return { patch_available: false, patch: null, rolled_back_patch_numbers: null };

    const rolledBack = (
      await this.prisma.patch.findMany({ where: { releaseId: release.id, isRolledBack: true }, orderBy: { number: 'asc' }, select: { number: true } })
    ).map((p) => p.number);

    const latest = await this.prisma.patch.findFirst({
      where: {
        releaseId: release.id,
        isRolledBack: false,
        channels: { some: { channel: { name: req.channel } } },
        artifacts: { some: { platform: req.platform, arch: req.arch, uploaded: true } },
      },
      orderBy: { number: 'desc' },
      include: { artifacts: { where: { platform: req.platform, arch: req.arch, uploaded: true }, take: 1 } },
    });
    if (!latest || latest.artifacts.length === 0) {
      return { patch_available: false, patch: null, rolled_back_patch_numbers: rolledBack };
    }
    // Legacy clients send `patch_number` meaning "only newer than this". Newer clients send
    // `current_patch_number`, which must not filter: the updater skips patches it already has.
    if (req.current_patch_number === undefined && req.patch_number !== undefined && latest.number <= req.patch_number) {
      return { patch_available: false, patch: null, rolled_back_patch_numbers: rolledBack };
    }
    const a = latest.artifacts[0];
    return {
      patch_available: true,
      patch: { number: latest.number, download_url: downloadUrl('patch', a.downloadToken), hash: a.hash, hash_signature: a.hashSignature },
      rolled_back_patch_numbers: rolledBack,
    };
  }
}
