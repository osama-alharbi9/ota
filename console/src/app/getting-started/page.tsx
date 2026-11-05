import Link from 'next/link';
import { Card, Code, Title } from '@/components/ui';
import { api } from '@/lib/api';

export const metadata = { title: 'Getting started' };

const Step = ({ n, title, children }: { n: number; title: string; children: React.ReactNode }) => (
  <Card title={`${n}. ${title}`}>
    <div className="space-y-3 text-ink/85">{children}</div>
  </Card>
);

export default async function GettingStarted() {
  const { public_url } = await api<{ public_url: string }>('/api/dashboard/overview');
  return (
    <>
      <div className="mb-8"><Title sub="Ship an app, then update it over the air from this server.">Getting started</Title></div>
      <div className="space-y-6">
        <Step n={1} title="Sign in from your terminal">
          <p>Create a key on the <Link href="/account/api-keys">API keys</Link> page, then:</p>
          <Code>{`ota login --server ${public_url} --api-key ota_...`}</Code>
          <p className="text-[13px] text-ink/60">In CI, set <code className="font-mono">OTA_HOSTED_URL</code> and <code className="font-mono">OTA_TOKEN</code> instead.</p>
        </Step>
        <Step n={2} title="Register your app">
          <p>Inside your project. This creates the app here and writes <code className="font-mono">ota.yaml</code> with this server&apos;s address.</p>
          <Code>{`cd my_app\nota init`}</Code>
          <p className="text-[13px] text-ink/60">The address is built into the app. If it changes, release again.</p>
        </Step>
        <Step n={3} title="Release">
          <p>Records what the shipped app contains. Install that exact build on your device, or upload it to the store.</p>
          <Code>{`ota release react-native   # React Native: Android and iOS\nota release android        # Flutter: Android`}</Code>
        </Step>
        <Step n={4} title="Patch">
          <p>Change your code, then publish a patch. Devices download it on their next launch and run it on the launch after.</p>
          <Code>{`ota patch react-native\nota patch android --release-version 1.0.0+1`}</Code>
        </Step>
        <Step n={5} title="Roll back">
          <p>Open the release under <Link href="/apps">Apps</Link> and choose <b>Roll back</b> on a patch, or run <code className="font-mono">ota patches rollback</code>. Devices drop it at their next check. <b>Restore</b> undoes it.</p>
        </Step>
        <Card title="Rules">
          <ul className="list-disc space-y-1 pl-5 text-ink/85">
            <li>Only JavaScript, Dart and bundled assets can be patched. Native code needs a new release.</li>
            <li>A patch uses the same React Native version or Flutter revision as its release. The CLI enforces this.</li>
            <li>Android and iOS releases are separate. A patch targets one platform.</li>
          </ul>
        </Card>
      </div>
    </>
  );
}
