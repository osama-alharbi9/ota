# Flutter

Update the Dart code of a Flutter app without a store release. Android only.

Flutter iOS needs a linker that upstream keeps in a private repository, so it is not supported. See the [clean-room log](cleanroom.md).

## The toolchain

A patched Flutter app needs a patched engine. The CLI downloads it the first time you run `ota` inside a Flutter project:

| File in `cli/bin/internal/` | Override | What |
|---|---|---|
| `flutter.version` | | The commit of the Flutter fork to use |
| `flutter_git_url` | `OTA_FLUTTER_GIT_URL` | Where to clone that fork from |
| `artifacts_url` | `OTA_ARTIFACTS_URL` | Where to download engine files and the patch tool from |

To host your own, build it with [`engine/`](../engine). That takes well over 100 GB of disk.

The toolchain builds release mode only. Keep stock Flutter for debug runs and `flutter test`.

## Ship

```bash
cd my_flutter_app
ota init                     # registers the app, writes ota.yaml, adds it to pubspec assets
ota release android          # builds the app bundle and records the release
ota preview --platform android   # installs that release on a connected device
```

Upload the bundle from `build/app/outputs` to the store. Then, when you have a fix:

```bash
ota patch android --release-version 1.0.0+1
```

Phones download the patch on their next launch and run it on the launch after.

## Roll back

```bash
ota patches rollback --release-version 1.0.0+1 --patch-number 3
```

## Rules

- Only Dart code can be patched. Native code and plugins with native code need a store release.
- A patch must use the same Flutter revision as its release. The CLI enforces this.

## Test it

`scripts/run_flutter_android_loop.sh` runs release, patch and rollback on a running emulator.
