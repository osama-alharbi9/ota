/** What a release runs on. React Native releases store `react-native@<version>` as the revision. */
export function runtimeLabel(release: { flutter_version: string | null; flutter_revision: string }): string {
  const prefix = 'react-native@';
  if (release.flutter_revision.startsWith(prefix)) return `React Native ${release.flutter_revision.slice(prefix.length)}`;
  return `Flutter ${release.flutter_version ?? release.flutter_revision.slice(0, 10)}`;
}
