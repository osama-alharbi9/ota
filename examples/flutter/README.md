# Flutter example

A small Flutter app that shows a label, so you can see a patch land. Android only.

Git ignores the Gradle wrapper, so generate it once with Flutter 3.41 or newer, then register the app:

```bash
flutter create --platforms=android --project-name ota_flutter_example --org dev.ota .
ota init --force     # registers it on your server and rewrites ota.yaml
```

Then follow [docs/flutter.md](../../docs/flutter.md), or run `scripts/run_flutter_android_loop.sh`.
