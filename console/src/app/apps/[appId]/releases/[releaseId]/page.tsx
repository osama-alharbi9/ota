import { Seal } from '@/components/seal';
import { runtimeLabel } from '@/lib/runtime';
import { Card, Chip, Crumbs, Muted, State, Table, Td } from '@/components/ui';
import { api, fmtBytes, fmtDate } from '@/lib/api';
import { PatchActions } from '../../actions';

type Detail = {
  release: { id: number; version: string; flutter_version: string | null; flutter_revision: string; platform_statuses: Record<string, string>; seal_hash: string; created_at: string; notes: string | null };
  artifacts: { id: number; arch: string; platform: string; hash: string; size: number; filename: string | null; can_sideload: boolean; uploaded: boolean; created_at: string }[];
  patches: { id: number; number: number; channel: string | null; is_rolled_back: boolean; notes: string | null; created_at: string; artifacts: { id: number; arch: string; platform: string; hash: string; size: number; uploaded: boolean; signed: boolean }[] }[];
  channels: { id: number; name: string }[];
};

export default async function ReleasePage({ params }: { params: Promise<{ appId: string; releaseId: string }> }) {
  const { appId, releaseId } = await params;
  const [d, app] = await Promise.all([
    api<Detail>(`/api/dashboard/apps/${appId}/releases/${releaseId}`),
    api<{ app: { display_name: string } }>(`/api/dashboard/apps/${appId}`),
  ]);
  const r = d.release;
  return (
    <>
      <Crumbs items={[{ href: '/apps', label: 'Apps' }, { href: `/apps/${appId}`, label: app.app.display_name }, { label: r.version }]} />
      <div className="mb-8 flex items-center gap-6">
        <Seal hash={r.seal_hash} size={96} title={`Seal of release ${r.version}`} />
        <div>
          <h1 className="font-display text-[32px] font-semibold leading-[37px] tracking-[-0.02em]">
            Release <span className="font-mono text-[28px] font-normal">{r.version}</span>
          </h1>
          <div className="mt-2 flex flex-wrap items-center gap-4 text-[13px] text-ink/60">
            <span className="font-mono">{runtimeLabel(r)}</span>
            <span>created {fmtDate(r.created_at)}</span>
            {Object.entries(r.platform_statuses).map(([p, s]) => <State key={p} tone={s === 'active' ? 'live' : 'waiting'}>{p} {s}</State>)}
          </div>
        </div>
      </div>
      <div className="space-y-6">
        <Card title={`Patches (${d.patches.length})`}>
          {d.patches.length === 0 ? (
            <Muted>No patches yet. Run <code className="font-mono">ota patch</code> for release <code className="font-mono">{r.version}</code>.</Muted>
          ) : (
            <Table head={['Patch', 'Channel', 'State', 'Artifacts', 'Created', '']}>
              {d.patches.map((p) => (
                <tr key={p.id}>
                  <Td mono>#{p.number}</Td>
                  <Td>{p.channel ? <Chip>{p.channel}</Chip> : <span className="text-ink/60">not promoted</span>}</Td>
                  <Td>{p.is_rolled_back ? <State tone="failed">rolled back</State> : <State tone="live">live</State>}</Td>
                  <Td>{p.artifacts.map((a) => <div key={a.id} className="font-mono text-[13px] leading-[20px]">{a.platform}/{a.arch} {fmtBytes(a.size)}{a.signed ? ' signed' : ''}{a.uploaded ? '' : ' pending'}</div>)}</Td>
                  <Td className="text-[13px] text-ink/60">{fmtDate(p.created_at)}</Td>
                  <Td><PatchActions appId={appId} releaseId={r.id} number={p.number} rolledBack={p.is_rolled_back} channels={d.channels.map((c) => c.name)} /></Td>
                </tr>
              ))}
            </Table>
          )}
        </Card>
        <Card title={`Release artifacts (${d.artifacts.length})`}>
          <Table head={['Platform', 'Arch', 'File', 'Size', 'sha256', 'Sideloadable', 'Uploaded']} numeric={[3]}>
            {d.artifacts.map((a) => (
              <tr key={a.id}>
                <Td>{a.platform}</Td>
                <Td mono>{a.arch}</Td>
                <Td mono>{a.filename ?? '-'}</Td>
                <Td mono right>{fmtBytes(a.size)}</Td>
                <Td mono>{a.hash.slice(0, 16)}…</Td>
                <Td>{a.can_sideload ? 'yes' : 'no'}</Td>
                <Td>{a.uploaded ? <State tone="live">yes</State> : <State tone="waiting">pending</State>}</Td>
              </tr>
            ))}
          </Table>
        </Card>
      </div>
    </>
  );
}
