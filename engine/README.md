# engine/: the Flutter engine toolchain

Builds OTA's branch of the Flutter fork (engine + framework) against the
stock Dart SDK, and serves the results from OTA's artifact server, so
`ota release/patch android` never downloads anything from Shorebird. Why each
piece exists: [../docs/cleanroom.md](../docs/cleanroom.md).

| File | Purpose |
|---|---|
| `gclient.template` | `.gclient` for the fork, pointing at our git host |
| `scripts/env.sh` | pins, paths and the engine/stable branch helpers, sourced by everything else |
| `scripts/setup.sh` | clone the fork and updater from our git host |
| `scripts/sync.sh` | `gclient sync` (large download of stock dependencies) |
| `scripts/build_host.sh` | host Dart SDK from source, host tools (impellerc, font-subset, const_finder), and upstream's archive targets (flutter_patched_sdk_product, artifacts, font-subset) |
| `scripts/build_android.sh <arm64\|arm\|x64>` | an Android release engine; fails on any `shorebird` string. arm64 also zips the `sky_engine` and `flutter_gpu` packages |
| `scripts/build_patch_tool.sh` | the `patch` tool from our updater branch |
| `scripts/publish_fork.sh` | create `ota/stable` (the engine.version commit, made with git plumbing so the build tree is untouched) and push to our git host |
| `scripts/make_mirror.sh` | assemble the artifact server root from our build outputs only: all three ABIs, the Maven repo, the Dart SDK and host-tools zips (packed with upstream's `build/zip.py`), `engine_stamp.json` (`et stamp`). `MIRROR_ANDROID_OUTS` limits it to some ABIs for a trial |
| `scripts/serve_artifacts.sh`, `artifact_server.py` | OTA's artifact server: SERVE / PLACEHOLDER / GOOGLE / MISS, all logged |
| `mirror_google_allow.txt`, `mirror_placeholders.txt` | the only two exceptions to "serve only what we built" (CLEANROOM T1-17), each rule with its reason |

Workspace (outside this repo): `~/engine-src/{depot_tools,flutter,updater,mirror}`. A full build takes well over 100 GB of disk and several hours. These scripts were last run end to end before the forks moved to their public home, so expect to fix small things.

Build order: `setup.sh`, `sync.sh`, `build_host.sh`, `build_android.sh arm64`,
`build_android.sh arm`, `build_android.sh x64`, `build_patch_tool.sh`,
`publish_fork.sh` (then put its output in `cli/bin/internal/flutter.version` and
commit it in `cli/`), `make_mirror.sh`, `serve_artifacts.sh`.

The build and mirror scripts check that HEAD is `ota/engine` and that the
working tree's `bin/internal/engine.version` holds that commit (a build-time
edit, never committed on `ota/engine`); they print the command to fix it.
After a new commit on `ota/engine`, run `sync.sh` if DEPS changed, then all
builds again: the engine hash is baked into every binary and Maven version.

The toolchain is release-only: debug runs, profile builds and `flutter test`
need artifacts it does not build (placeholders, CLEANROOM T1-17).
