# ota CLI

The command line tool for [ota](../README.md): over-the-air updates for React Native and Flutter apps.

```bash
ota login --server https://your-ota-server --api-key ota_...
ota init
ota release react-native     # or: ota release android
ota patch react-native       # or: ota patch android --release-version 1.0.0+1
```

Run `ota --help` for all commands.

`bin/ota` builds the CLI on first use and again after any commit that touches this directory. It uses the Dart SDK on your `PATH`, or `OTA_DART`. In a Flutter project it also downloads the Flutter toolchain, described in [docs/flutter.md](../docs/flutter.md).

## Origin

A fork of the open-source Shorebird CLI, release 1.6.93, by Code Town, Inc., licensed MIT OR Apache-2.0 (see `COPYRIGHT`, `LICENSE-MIT`, `LICENSE-APACHE`). Upstream copyright notices are kept as those licenses require.
