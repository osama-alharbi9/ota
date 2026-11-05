import Link from 'next/link';
import { Card, Chip, Muted, Table, Td, Title } from '@/components/ui';
import { api, fmtDate } from '@/lib/api';
import { CreateApp } from './create-app';

type AppRow = {
  id: string; display_name: string; organization: { id: number; name: string }; release_count: number;
  latest_release_version: string | null; latest_patch_number: number | null; created_at: string;
};

export const metadata = { title: 'Apps' };

export default async function AppsPage() {
  const { apps } = await api<{ apps: AppRow[] }>('/api/dashboard/apps');
  const { organizations } = await api<{ organizations: { id: number; name: string }[] }>('/api/dashboard/overview');
  return (
    <>
      <div className="mb-8 flex items-end justify-between gap-4">
        <Title sub="Every app you ship with ota.">Apps</Title>
        <CreateApp organizations={organizations} />
      </div>
      <Card>
        {apps.length === 0 ? (
          <Muted>No apps yet. Create one here, or run <code className="font-mono">ota init</code> in your project. See <Link href="/getting-started">Getting started</Link>.</Muted>
        ) : (
          <Table head={['Name', 'App id', 'Releases', 'Latest release', 'Latest patch', 'Created']} numeric={[2]}>
            {apps.map((a) => (
              <tr key={a.id}>
                <Td>
                  <Link href={`/apps/${a.id}`} className="font-medium text-ink">{a.display_name}</Link>
                  <div className="text-[13px] text-ink/60">{a.organization.name}</div>
                </Td>
                <Td mono>{a.id}</Td>
                <Td mono right>{a.release_count}</Td>
                <Td mono>{a.latest_release_version ?? <span className="font-sans text-ink/60">none</span>}</Td>
                <Td>{a.latest_patch_number != null ? <Chip><span className="font-mono">#{a.latest_patch_number}</span></Chip> : <span className="text-ink/60">none</span>}</Td>
                <Td className="text-[13px] text-ink/60">{fmtDate(a.created_at)}</Td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </>
  );
}
