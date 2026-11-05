import { Card, Code, Muted, Title } from '@/components/ui';
import { api } from '@/lib/api';
import { ApiKeys } from './keys';

export const metadata = { title: 'API keys' };

export default async function ApiKeysPage() {
  const d = await api<{ keys: { id: number; name: string; prefix: string; created_at: string; last_used_at: string | null; revoked_at: string | null }[]; public_url: string }>('/api/dashboard/api-keys');
  return (
    <>
      <div className="mb-8"><Title sub="Keys let the ota CLI act on your behalf.">API keys</Title></div>
      <div className="space-y-6">
        <Card title="Use a key with the CLI">
          <div className="mb-3"><Muted>Sign in once from your terminal with a key from below. In CI, set <code className="font-mono">OTA_HOSTED_URL</code> and <code className="font-mono">OTA_TOKEN</code> instead.</Muted></div>
          <Code>{`ota login --server ${d.public_url} --api-key ota_...`}</Code>
        </Card>
        <ApiKeys initial={d.keys} publicUrl={d.public_url} />
      </div>
    </>
  );
}
