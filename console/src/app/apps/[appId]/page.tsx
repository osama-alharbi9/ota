import Link from 'next/link';
import { Seal } from '@/components/seal';
import { runtimeLabel } from '@/lib/runtime';
import { Card, Chip, Code, Crumbs, Muted, State, Table, Td, Title } from '@/components/ui';
import { api, fmtDate } from '@/lib/api';
import { DeleteApp } from './actions';

type Detail = {
  app: { id: string; display_name: string; created_at: string };
  ota_yaml: string;
  channels: { id: number; name: string }[];
  stats: { patch_checks_24h: number; events_24h: number };
  releases: {
    id: number; version: string; flutter_version: string | null; flutter_revision: string; platform_statuses: Record<string, string>;
    patch_count: number; artifact_count: number; latest_patch_number: number | null; seal_hash: string; created_at: string;
  }[];
};

export default async function AppPage({ params }: { params: Promise<{ appId: string }> }) {
  const { appId } = await params;
  const d = await api<Detail>(`/api/dashboard/apps/${appId}`);
  return (
    <>
      <Crumbs items={[{ href: '/apps', label: 'Apps' }, { label: d.app.display_name }]} />
      <div className="mb-8 flex items-end justify-between gap-4">
        <Title sub={<span className="font-mono">{d.app.id}</span>}>{d.app.display_name}</Title>
        <div className="flex items-center gap-4">
          <Link href={`/apps/${appId}/activity`}>Device activity</Link>
          <DeleteApp appId={appId} />
        </div>
      </div>
      <div className="mb-6 grid gap-4 md:grid-cols-3">
        <Card title="Last 24 hours">
          <p className="font-display text-[32px] font-semibold leading-[37px]">{d.stats.patch_checks_24h}</p>
          <Muted>update checks from devices</Muted>
          <p className="mt-4 font-display text-[32px] font-semibold leading-[37px]">{d.stats.events_24h}</p>
          <Muted>download and install events</Muted>
        </Card>
        <Card title="Channels">
          {d.channels.length ? <div className="flex flex-wrap gap-2">{d.channels.map((c) => <Chip key={c.id}>{c.name}</Chip>)}</div> : <Muted>Created on the first patch.</Muted>}
        </Card>
        <Card title="ota.yaml"><Code>{d.ota_yaml}</Code></Card>
      </div>
      <Card title="Releases">
        {d.releases.length === 0 ? (
          <Muted>No releases yet. Run <code className="font-mono">ota release android</code> in the project.</Muted>
        ) : (
          <Table head={['Release', 'Platforms', 'Runtime', 'Artifacts', 'Patches', 'Latest patch', 'Created']} numeric={[3, 4]}>
            {d.releases.map((r) => (
              <tr key={r.id}>
                <Td>
                  <Link href={`/apps/${appId}/releases/${r.id}`} className="flex items-center gap-3 text-ink">
                    <Seal hash={r.seal_hash} size={32} />
                    <span className="font-mono">{r.version}</span>
                  </Link>
                </Td>
                <Td>
                  <div className="flex flex-col gap-1">
                    {Object.entries(r.platform_statuses).map(([p, s]) => <State key={p} tone={s === 'active' ? 'live' : 'waiting'}>{p} {s}</State>)}
                  </div>
                </Td>
                <Td mono>{runtimeLabel(r)}</Td>
                <Td mono right>{r.artifact_count}</Td>
                <Td mono right>{r.patch_count}</Td>
                <Td mono>{r.latest_patch_number != null ? `#${r.latest_patch_number}` : '-'}</Td>
                <Td className="text-[13px] text-ink/60">{fmtDate(r.created_at)}</Td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </>
  );
}
