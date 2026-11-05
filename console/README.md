# ota console

The web dashboard for an ota server: apps, releases, patches, rollbacks, activity and API keys.

```bash
cp .env.example .env   # API_URL points at the server
pnpm install
pnpm dev               # http://localhost:3000
```

In production it runs from `compose.yaml` at the repository root.
