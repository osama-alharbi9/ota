'use client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { buttonClass, inputClass } from '@/components/ui';
import { call } from '@/lib/client';

export function CreateApp({ organizations }: { organizations: { id: number; name: string }[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState('');
  const [org, setOrg] = useState(organizations[0]?.id);
  const [error, setError] = useState<string | null>(null);
  if (!open) return <button className={buttonClass('primary')} onClick={() => setOpen(true)}>New app</button>;
  return (
    <form
      className="flex flex-wrap items-center gap-2"
      onSubmit={async (e) => {
        e.preventDefault();
        try {
          const r = await call<{ app: { id: string } }>('/api/dashboard/apps', { method: 'POST', body: JSON.stringify({ display_name: name, organization_id: org }) });
          router.push(`/apps/${r.app.id}`);
          router.refresh();
        } catch (err) {
          setError((err as Error).message);
        }
      }}
    >
      <input autoFocus className={`${inputClass} w-56`} placeholder="App name" value={name} onChange={(e) => setName(e.target.value)} required />
      {organizations.length > 1 && (
        <select className={`${inputClass} w-auto`} value={org} onChange={(e) => setOrg(Number(e.target.value))}>
          {organizations.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
        </select>
      )}
      <button className={buttonClass('primary')}>Create</button>
      <button type="button" className={buttonClass('secondary')} onClick={() => setOpen(false)}>Cancel</button>
      {error && <span className="text-[13px] text-rose">{error}</span>}
    </form>
  );
}
