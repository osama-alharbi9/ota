# Self-hosting

The server is four containers: the API, the console, Postgres and MinIO. A small VM with 2 GB of RAM is enough to start. `compose.yaml` runs them all.

## Start

```bash
cp .env.example .env     # fill in every value
docker compose up -d
```

This pulls the published images. `OTA_SERVER_IMAGE` and `OTA_CONSOLE_IMAGE` in `.env` pick the version. Add `--build` to build from your checkout instead.

Database migrations run when the API starts.

## HTTPS

Put a reverse proxy in front. Android and iOS block plain HTTP in release builds, and API keys travel in headers. Caddy needs only this:

```
ota.example.com {
  reverse_proxy localhost:8080
}
console.ota.example.com {
  reverse_proxy localhost:3100
}
```

Set `PUBLIC_URL` to the API address and `WEB_ORIGIN` to the console address.

`PUBLIC_URL` is built into every app you release through `ota.yaml`. Choose a domain you will keep. Moving it means shipping a new store release.

## Accounts and keys

The first admin comes from `BOOTSTRAP_EMAIL` and `BOOTSTRAP_PASSWORD`. Anyone who can reach the console can also register their own account and organization, so keep it behind your network or proxy if you don't want that.

Create API keys in the console, under API keys. In CI, set `OTA_HOSTED_URL` and `OTA_TOKEN` instead of running `ota login`.

## Storage

MinIO is the default. For hosted S3, point the API at it with `S3_ENDPOINT`, `S3_PORT`, `S3_USE_SSL`, `S3_REGION`, `S3_FORCE_PATH_STYLE=false`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` and `S3_BUCKET`.

## Backups

Back up the `pgdata` and `miniodata` volumes together. If you lose them, installed apps keep running their current code, but you can't patch those releases again.

## Reset a local server

```bash
docker compose -f compose.yaml -f compose.dev.yaml --env-file .env.dev down -v
```

This deletes all data.
