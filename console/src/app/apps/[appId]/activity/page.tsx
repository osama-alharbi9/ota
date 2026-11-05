import { Card, Crumbs, State, Table, Td, Title } from '@/components/ui';
import { api, fmtDate } from '@/lib/api';

type Activity = {
  patch_checks: { id: number; received_at: string; request: Record<string, unknown>; response: { patch_available: boolean; patch?: { number: number } | null; rolled_back_patch_numbers?: number[] | null } }[];
  events: { id: number; received_at: string; event: Record<string, unknown> }[];
};

const EVENT_WORDS: Record<string, string> = {
  __patch_download__: 'downloaded',
  __patch_install__: 'installed',
  __patch_install_failure__: 'install failed',
  __patch_update_failure__: 'update failed',
};

export default async function ActivityPage({ params }: { params: Promise<{ appId: string }> }) {
  const { appId } = await params;
  const [a, app] = await Promise.all([
    api<Activity>(`/api/dashboard/apps/${appId}/activity?limit=100`),
    api<{ app: { display_name: string } }>(`/api/dashboard/apps/${appId}`),
  ]);
  const s = (v: unknown) => (v == null ? '-' : String(v));
  return (
    <>
      <Crumbs items={[{ href: '/apps', label: 'Apps' }, { href: `/apps/${appId}`, label: app.app.display_name }, { label: 'Device activity' }]} />
      <div className="mb-8"><Title sub="What installed apps reported to this server.">Device activity</Title></div>
      <div className="space-y-6">
        <Card title={`Install and download events (last ${a.events.length})`}>
          <Table head={['Time', 'Event', 'Release', 'Patch', 'Platform', 'Device']}>
            {a.events.map((e) => {
              const type = s(e.event.type);
              return (
                <tr key={e.id}>
                  <Td className="text-[13px] text-ink/60">{fmtDate(e.received_at)}</Td>
                  <Td><State tone={type.includes('failure') ? 'failed' : 'live'}>{EVENT_WORDS[type] ?? type}</State></Td>
                  <Td mono>{s(e.event.release_version)}</Td>
                  <Td mono>#{s(e.event.patch_number)}</Td>
                  <Td mono>{s(e.event.platform)}/{s(e.event.arch)}</Td>
                  <Td mono>{s(e.event.client_id).slice(0, 8)}</Td>
                </tr>
              );
            })}
          </Table>
        </Card>
        <Card title={`Update checks (last ${a.patch_checks.length})`}>
          <Table head={['Time', 'Release', 'Channel', 'Platform', 'Device', 'Answer']}>
            {a.patch_checks.map((c) => (
              <tr key={c.id}>
                <Td className="text-[13px] text-ink/60">{fmtDate(c.received_at)}</Td>
                <Td mono>{s(c.request.release_version)}</Td>
                <Td>{s(c.request.channel)}</Td>
                <Td mono>{s(c.request.platform)}/{s(c.request.arch)}</Td>
                <Td mono>{s(c.request.client_id).slice(0, 8)}</Td>
                <Td>
                  <div className="flex flex-col gap-1">
                    {c.response.patch_available ? <State tone="live">patch #{c.response.patch?.number}</State> : <State tone="neutral">no update</State>}
                    {c.response.rolled_back_patch_numbers?.length ? <State tone="failed">rolled back {c.response.rolled_back_patch_numbers.join(', ')}</State> : null}
                  </div>
                </Td>
              </tr>
            ))}
          </Table>
        </Card>
      </div>
    </>
  );
}
