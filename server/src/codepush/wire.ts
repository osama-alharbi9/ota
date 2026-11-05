import { App, Channel, Patch, PatchArtifact, Release, ReleaseArtifact } from '@prisma/client';
import { config } from '../config';
import { iso, num } from '../common/serialize';

/** Serializers for the exact JSON the ota CLI and the on-device updater parse. */
export const uploadUrl = (kind: 'release' | 'patch', token: string) => `${config.publicUrl}/api/v1/uploads/${kind}/${token}`;
export const downloadUrl = (kind: 'release' | 'patch', token: string) => `${config.publicUrl}/api/v1/artifacts/${kind}/${token}`;

export const wireApp = (a: App) => ({ id: a.id, display_name: a.displayName });

export const wireAppMetadata = (a: App, latestReleaseVersion: string | null, latestPatchNumber: number | null) => ({
  app_id: a.id,
  display_name: a.displayName,
  latest_release_version: latestReleaseVersion,
  latest_patch_number: latestPatchNumber,
  created_at: iso(a.createdAt),
  updated_at: iso(a.updatedAt),
});

export const wireChannel = (c: Channel) => ({ id: c.id, app_id: c.appId, name: c.name });

export const wireRelease = (r: Release) => ({
  id: r.id,
  app_id: r.appId,
  version: r.version,
  flutter_revision: r.flutterRevision,
  flutter_version: r.flutterVersion,
  display_name: r.displayName,
  platform_statuses: r.platformStatuses ?? {},
  created_at: iso(r.createdAt),
  updated_at: iso(r.updatedAt),
  notes: r.notes,
});

export const wireReleaseArtifact = (a: ReleaseArtifact) => ({
  id: a.id,
  release_id: a.releaseId,
  arch: a.arch,
  platform: a.platform,
  hash: a.hash,
  size: num(a.size),
  url: downloadUrl('release', a.downloadToken),
  podfile_lock_hash: a.podfileLockHash,
  can_sideload: a.canSideload,
});

export const wireCreateReleaseArtifact = (a: ReleaseArtifact) => ({
  id: a.id,
  release_id: a.releaseId,
  arch: a.arch,
  platform: a.platform,
  hash: a.hash,
  size: num(a.size),
  url: uploadUrl('release', a.uploadToken),
});

export const wirePatch = (p: Patch) => ({ id: p.id, number: p.number, notes: p.notes });

export const wirePatchArtifact = (a: PatchArtifact) => ({
  id: a.id,
  patch_id: a.patchId,
  arch: a.arch,
  platform: a.platform,
  hash: a.hash,
  size: num(a.size),
  created_at: iso(a.createdAt),
});

export const wireCreatePatchArtifact = (a: PatchArtifact) => ({
  id: a.id,
  patch_id: a.patchId,
  arch: a.arch,
  platform: a.platform,
  hash: a.hash,
  size: num(a.size),
  url: uploadUrl('patch', a.uploadToken),
});

export const wireReleasePatch = (p: Patch & { artifacts: PatchArtifact[]; channels: { channel: Channel; promotedAt: Date }[] }) => ({
  id: p.id,
  number: p.number,
  channel: [...p.channels].sort((a, b) => b.promotedAt.getTime() - a.promotedAt.getTime())[0]?.channel.name ?? null,
  artifacts: p.artifacts.map(wirePatchArtifact),
  is_rolled_back: p.isRolledBack,
  notes: p.notes,
});

export const PLATFORMS = ['android', 'ios', 'linux', 'macos', 'windows'] as const;
export const STATUSES = ['draft', 'active'] as const;
