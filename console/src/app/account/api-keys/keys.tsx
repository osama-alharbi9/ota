'use client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Card, Code, State, Table, Td, buttonClass, inputClass, smallButtonClass } from '@/components/ui';
import { call } from '@/lib/client';

type Key = { id: number; name: string; prefix: string; created_at: string; last_used_at: string | null; revoked_at: string | null };

export function ApiKeys({ initial, publicUrl }: { initial: Key[]; publicUrl: string }) {
  const router = useRouter();
  const [name, setName] = useState('');
  const [created, setCreated] = useState<{ key: string; name: string } | null>(null);
  return (
    <Card
      title="Your keys"
      action={
        <form
          className="flex gap-2"
          onSubmit={async (e) => {
            e.preventDefault();
            const r = await call<{ key: string; name: string }>('/api/dashboard/api-keys', { method: 'POST', body: JSON.stringify({ name }) });
            setCreated(r);
            setName('');
            router.refresh();
          }}
        >
          <input className={`${inputClass} w-48`} placeholder="Key name, e.g. laptop" value={name} onChange={(e) => setName(e.target.value)} required />
          <button className={buttonClass('primary')}>Create key</button>
        </form>
      }
    >
      {created && (
        <div className="mb-6 rounded-card border border-jade/40 bg-jade/5 p-4">
          <p className="mb-3 text-[15px] font-medium">Key &ldquo;{created.name}&rdquo; created. Copy it now; it is shown only once.</p>
          <Code>{`ota login --server ${publicUrl} --api-key ${created.key}`}</Code>
        </div>
      )}
      <Table head={['Name', 'Key', 'Created', 'Last used', 'State', '']}>
        {initial.map((k) => (
          <tr key={k.id}>
            <Td>{k.name}</Td>
            <Td mono>{k.prefix}…</Td>
            <Td className="text-[13px] text-ink/60">{new Date(k.created_at).toLocaleString()}</Td>
            <Td className="text-[13px] text-ink/60">{k.last_used_at ? new Date(k.last_used_at).toLocaleString() : 'never'}</Td>
            <Td>{k.revoked_at ? <State tone="failed">revoked</State> : <State tone="live">active</State>}</Td>
            <Td>
              {!k.revoked_at && (
                <button
                  className={smallButtonClass('danger')}
                  onClick={async () => {
                    if (confirm(`Revoke "${k.name}"?`)) {
                      await call(`/api/dashboard/api-keys/${k.id}`, { method: 'DELETE' });
                      router.refresh();
                    }
                  }}
                >
                  Revoke
                </button>
              )}
            </Td>
          </tr>
        ))}
      </Table>
    </Card>
  );
}
