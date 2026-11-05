# ota

Self-hosted over-the-air updates for React Native and Flutter apps. Fix a bug, run one command, and it reaches phones on their next launch, from a server you own.

| | Android | iOS |
|---|---|---|
| React Native | Yes | Yes |
| Flutter | Yes | Not yet |

```bash
ota init                     # register the app on your server
ota release react-native     # record what the shipped app contains
ota patch react-native       # push a change to everyone on that release
ota patches rollback --release-version 1.0+1 --patch-number 3
```

## What's in this repo

| Path | What |
|---|---|
| [`cli/`](cli) | The `ota` command line tool (Dart) |
| [`react-native/`](react-native) | `ota-react-native`, the SDK your React Native app installs |
| [`server/`](server) | The API that stores releases and answers devices (NestJS, Postgres, S3) |
| [`console/`](console) | The web dashboard (Next.js) |
| [`engine/`](engine) | Scripts that build the Flutter engine toolchain |
| [`examples/`](examples) | A React Native app and a Flutter app |

## Get started

1. **Run the server.**

   ```bash
   git clone https://github.com/osama-alharbi9/ota.git && cd ota
   cp .env.dev.example .env.dev
   docker compose -f compose.yaml -f compose.dev.yaml --env-file .env.dev up -d --build
   ```

   The API is on `http://localhost:8080`. The console is on `http://localhost:3100`. Going to production: [docs/self-hosting.md](docs/self-hosting.md).

2. **Install the CLI.** It needs git and a [Dart SDK](https://dart.dev/get-dart).

   ```bash
   ln -s "$PWD/cli/bin/ota" /usr/local/bin/ota
   ota login --server http://localhost:8080 --api-key ota_dev_token_not_for_production
   ```

3. **Follow your framework's guide:** [React Native](docs/react-native.md) or [Flutter](docs/flutter.md).

## How updates reach a phone

1. On launch, the app asks your server if there is a newer patch for its exact release.
2. It downloads the patch in the background and checks its hash.
3. The next launch runs the patch.
4. If a new patch crashes before it confirms it works, the app drops it and goes back to the last good code.

More detail: [docs/how-it-works.md](docs/how-it-works.md).

## What a patch can change

JavaScript, Dart and bundled assets. Native code, new native modules and framework upgrades need a new store release. Apple and Google both allow interpreted code updates within limits, so read their rules for your app.

## Docs

- [React Native guide](docs/react-native.md)
- [Flutter guide](docs/flutter.md)
- [Self-hosting](docs/self-hosting.md)
- [Environments: dev and production](docs/environments.md)
- [How it works](docs/how-it-works.md)
- [Clean-room log](docs/cleanroom.md): where every Flutter toolchain decision came from

## Contributing

Pull requests go to the `dev` branch. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Origin and license

The CLI and the on-device Flutter updater are forks of the open-source [Shorebird](https://github.com/shorebirdtech/shorebird) CLI and [updater](https://github.com/shorebirdtech/updater), by Code Town, Inc. The Flutter toolchain builds from [Shorebird's public Flutter fork](https://github.com/shorebirdtech/flutter) against the stock Dart SDK. This project is independent and is not affiliated with or endorsed by Shorebird.

Licensed under either of [Apache-2.0](LICENSE-APACHE) or [MIT](LICENSE-MIT), at your option. See [NOTICE](NOTICE) for what came from where.
