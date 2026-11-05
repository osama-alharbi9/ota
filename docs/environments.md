# Environments

There are two: **dev** and **production**. Each is a branch, a GitHub environment and a container image tag.

| | dev | production |
|---|---|---|
| Branch | `dev` | `main` |
| GitHub environment | `dev` | `production` |
| Server image | `ghcr.io/osama-alharbi9/ota-server:dev` | `ghcr.io/osama-alharbi9/ota-server:latest` |
| Console image | `ghcr.io/osama-alharbi9/ota-console:dev` | `ghcr.io/osama-alharbi9/ota-console:latest` |
| Settings file | `.env.dev` (from `.env.dev.example`) | `.env` (from `.env.example`) |
| Compose | `compose.yaml` + `compose.dev.yaml` | `compose.yaml` |

## How a change moves

1. Open a pull request against `dev`. CI must pass.
2. Merging to `dev` publishes the `dev` images, through the `dev` environment.
3. Open a pull request from `dev` to `main` when `dev` is good.
4. Merging to `main` publishes the `latest` images, through the `production` environment.

These images are what anyone self-hosting pulls. The project doesn't run a hosted server, so publishing the images is the deployment.

## Running each one

Dev, from your checkout:

```bash
cp .env.dev.example .env.dev
docker compose -f compose.yaml -f compose.dev.yaml --env-file .env.dev up -d --build
```

Dev images, from the registry: set `OTA_SERVER_IMAGE` and `OTA_CONSOLE_IMAGE` to the `:dev` tags in your `.env`.

Production:

```bash
cp .env.example .env
docker compose up -d
```

## Pointing the CLI at one

`ota login` remembers one server. To switch per command or in CI:

```bash
OTA_HOSTED_URL=https://ota.example.com OTA_TOKEN=ota_... ota patch react-native
```

An app talks to the server in the `base_url` of its `ota.yaml`, set when you build it. Build separate apps with separate `ota.yaml` files if you want a dev build and a production build of the same app.
