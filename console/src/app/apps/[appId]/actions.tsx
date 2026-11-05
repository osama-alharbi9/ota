'use client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { inputClass, smallButtonClass } from '@/components/ui';
import { call } from '@/lib/client';

export function DeleteApp({ appId }: { appId: string }) {
  const router = useRouter();
  return (
    <button
      className={smallButtonClass('danger')}
      onClick={async () => {
        if (!confirm('Delete this app with all its releases, patches and artifacts?')) return;
        await call(`/api/dashboard/apps/${appId}`, { method: 'DELETE' });
        router.push('/apps');
        router.refresh();
      }}
    >
      Delete app
    </button>
  );
}

export function PatchActions({ appId, releaseId, number, rolledBack, channels }: { appId: string; releaseId: number; number: number; rolledBack: boolean; channels: string[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [promoting, setPromoting] = useState(false);
  const [channel, setChannel] = useState(channels[0] ?? 'stable');
  const base = `/api/dashboard/apps/${appId}/releases/${releaseId}/patches/${number}`;
  const run = async (path: string, body?: object) => {
    setBusy(true);
    try {
      await call(path, { method: 'POST', body: body ? JSON.stringify(body) : undefined });
      router.refresh();
    } catch (e) {
      alert((e as Error).message);
    } finally {
      setBusy(false);
      setPromoting(false);
    }
  };
  return (
    <div className="flex flex-wrap items-center justify-end gap-2">
      {rolledBack ? (
        <button className={smallButtonClass('secondary')} disabled={busy} onClick={() => run(`${base}/unrollback`)}>Restore</button>
      ) : (
        <button className={smallButtonClass('danger')} disabled={busy} onClick={() => confirm(`Roll back patch ${number}? Devices delete it at their next check and return to the release.`) && run(`${base}/rollback`)}>Roll back</button>
      )}
      {promoting ? (
        <>
          <input list={`channels-${number}`} className={`${inputClass} w-32 py-1.5 text-[13px]`} value={channel} onChange={(e) => setChannel(e.target.value)} />
          <datalist id={`channels-${number}`}>{channels.map((c) => <option key={c} value={c} />)}</datalist>
          <button className={smallButtonClass('secondary')} disabled={busy} onClick={() => run(`${base}/promote`, { channel })}>Promote</button>
          <button className={smallButtonClass('secondary')} onClick={() => setPromoting(false)}>Cancel</button>
        </>
      ) : (
        <button className={smallButtonClass('secondary')} disabled={busy} onClick={() => setPromoting(true)}>Promote…</button>
      )}
    </div>
  );
}
