# Security

Please don't open a public issue for a security problem. Report it through [GitHub's private vulnerability reporting](https://github.com/osama-alharbi9/ota/security/advisories/new).

This is a small project, so expect a reply within about a week.

## What to keep in mind when running it

- Whoever controls your ota server can publish code that runs in your app. Protect it like your release signing keys.
- Use HTTPS. Plain HTTP lets anyone on the network replace a patch's hash and contents.
- Patch download URLs are capability URLs. Anyone holding one can download that patch, so don't put secrets in your bundle.
- React Native patches aren't signed yet. Flutter patches support signing through `--private-key-path`.
