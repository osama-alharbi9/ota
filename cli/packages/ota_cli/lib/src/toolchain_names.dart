/// Names compiled into the current Flutter toolchain build.
///
/// The published engine binaries and their Flutter tool read these exact names,
/// so they can only change together with a new engine build (`engine/README.md`).
/// Every other name in the CLI is free to change.
library;

/// The file the Android engine reads from `flutter_assets` on launch.
const toolchainYamlAsset = 'revon.yaml';

/// The `flutter build` flag that writes a build trace.
const toolchainTraceFlag = 'revon-trace';

/// The environment variable the Flutter tool reads the patch public key from.
const toolchainPublicKeyEnv = 'REVON_PUBLIC_KEY';

/// The directory the Flutter tool writes link supplements to, under `build/`.
const toolchainBuildDir = 'revon';

/// The path prefix for the patch tool on the artifact server.
const toolchainArtifactPrefix = 'revon';

/// The package name of the toolchain's iOS tools in the Flutter fork.
const toolchainToolsPackage = 'revon_tools';
