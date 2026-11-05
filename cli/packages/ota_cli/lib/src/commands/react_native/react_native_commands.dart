import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/code_push_client_wrapper.dart';
import 'package:ota_cli/src/commands/react_native/react_native_bundler.dart';
import 'package:ota_cli/src/commands/react_native/react_native_project.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_validator.dart';
import 'package:ota_client/ota_client.dart';
import 'package:path/path.dart' as p;

/// The first argument that selects React Native in `ota release` and `ota patch`.
const reactNativeTarget = 'react-native';

/// Whether these arguments target a React Native app.
bool isReactNativeTarget(ArgResults results) =>
    results.rest.contains(reactNativeTarget);

/// Where the React Native setup steps are documented.
const reactNativeDocsUrl =
    'https://github.com/osama-alharbi9/ota/blob/main/docs/react-native.md';

class _Context {
  _Context(this.project, this.appId, this.platforms, this.entryFile);

  final ReactNativeProject project;
  final String appId;
  final List<ReleasePlatform> platforms;
  final String entryFile;
}

/// Shared checks. Logs the problem and returns null if the project isn't ready.
Future<_Context?> _prepare(ArgResults results) async {
  try {
    await otaValidator.validatePreconditions(checkUserIsAuthenticated: true);
  } on PreconditionFailedException {
    return null;
  }

  final project = ReactNativeProject.find();
  if (project == null) {
    logger.err(
      'Could not find a React Native project. Run this from your app.',
    );
    return null;
  }
  if (project.reactNativeVersion == null) {
    logger.err('React Native is not installed. Run your package install.');
    return null;
  }
  final otaYaml = otaEnv.getOtaYaml();
  if (otaYaml == null) {
    logger.err('Could not find ota.yaml. Run ${lightCyan.wrap('ota init')}.');
    return null;
  }
  if (!project.hasSdk) {
    logger.err(
      'This app does not depend on $reactNativeSdkPackage. '
      'See $reactNativeDocsUrl',
    );
    return null;
  }

  final entryFile =
      (results['entry-file'] as String?) ?? project.defaultEntryFile;
  if (entryFile == null) {
    logger.err('Could not find an entry file. Pass --entry-file.');
    return null;
  }
  if (!project.entryLoadsSdk(entryFile)) {
    logger.err(
      '$entryFile does not import $reactNativeSdkPackage. Without it the app '
      'cannot confirm a patch works, so every patch would roll back. '
      "Add `import '$reactNativeSdkPackage';` at the top of $entryFile.",
    );
    return null;
  }

  final requested = results['platforms'] as List<String>;
  final platforms = <ReleasePlatform>[];
  for (final name in requested) {
    final platform = ReleasePlatform.values.firstWhereOrNull(
      (candidate) => candidate.name == name,
    );
    if (platform == null || !project.platforms.contains(platform)) {
      logger.err('This app has no $name project.');
      return null;
    }
    platforms.add(platform);
  }
  return _Context(
    project,
    otaYaml.appId,
    platforms.isEmpty ? project.platforms : platforms,
    entryFile,
  );
}

Future<ReactNativeBundle?> _bundle(_Context context, ReleasePlatform platform) async {
  final progress = logger.progress('Bundling ${platform.name}');
  try {
    final bundle = await buildReactNativeBundle(
      project: context.project,
      platform: platform,
      entryFile: context.entryFile,
    );
    final size = bundle.archive.lengthSync() / 1024;
    progress.complete('Bundled ${platform.name} (${size.toStringAsFixed(1)} KB)');
    return bundle;
  } on ReactNativeBundleException catch (error) {
    progress.fail('Could not bundle ${platform.name}');
    logger.err(error.message);
    return null;
  }
}

/// `ota release react-native`: records what the shipped app contains.
Future<int> runReactNativeRelease(ArgResults results) async {
  final context = await _prepare(results);
  if (context == null) return ExitCode.usage.code;

  for (final platform in context.platforms) {
    final version =
        (results['release-version'] as String?) ??
        context.project.releaseVersion(platform);
    if (version == null) {
      logger.err(
        'Could not read the ${platform.name} app version. '
        'Pass --release-version.',
      );
      return ExitCode.usage.code;
    }

    final bundle = await _bundle(context, platform);
    if (bundle == null) return ExitCode.software.code;

    if (results['dry-run'] == true) {
      logger.info('Dry run: ${platform.name} $version was not uploaded.');
      continue;
    }

    final existing = await codePushClientWrapper.maybeGetRelease(
      appId: context.appId,
      releaseVersion: version,
    );
    if (existing != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existing,
        platform: platform,
      );
      if (existing.flutterRevision != context.project.runtime) {
        logger.err(
          'Release $version was made with ${existing.flutterRevision}. '
          'This app uses ${context.project.runtime}. Bump the app version.',
        );
        return ExitCode.software.code;
      }
    }
    final release =
        existing ??
        await codePushClientWrapper.codePushClient.createRelease(
          appId: context.appId,
          version: version,
          flutterRevision: context.project.runtime,
          flutterVersion: null,
          displayName: version,
        );

    await codePushClientWrapper.codePushClient.createReleaseArtifact(
      artifactPath: bundle.archive.path,
      appId: context.appId,
      releaseId: release.id,
      arch: reactNativeArch,
      platform: platform,
      hash: bundle.hash,
      canSideload: false,
      podfileLockHash: null,
    );
    await codePushClientWrapper.updateReleaseStatus(
      appId: context.appId,
      releaseId: release.id,
      platform: platform,
      status: ReleaseStatus.active,
    );
    logger.success('Published release $version for ${platform.name}.');
  }

  logger.info(
    '\nBuild and ship the native app as usual. Then push updates with '
    '${lightCyan.wrap('ota patch react-native')}.',
  );
  return ExitCode.success.code;
}

/// `ota patch react-native`: publishes a new bundle to apps on a release.
Future<int> runReactNativePatch(ArgResults results) async {
  final context = await _prepare(results);
  if (context == null) return ExitCode.usage.code;
  final track = results['track'] as String;

  for (final platform in context.platforms) {
    final requested = results['release-version'] as String?;
    final version = requested == null || requested == 'latest'
        ? context.project.releaseVersion(platform)
        : requested;
    if (version == null) {
      logger.err(
        'Could not read the ${platform.name} app version. '
        'Pass --release-version.',
      );
      return ExitCode.usage.code;
    }

    final release = await codePushClientWrapper.maybeGetRelease(
      appId: context.appId,
      releaseVersion: version,
    );
    if (release == null ||
        release.platformStatuses[platform] != ReleaseStatus.active) {
      logger.err(
        'No ${platform.name} release $version. Run '
        '${lightCyan.wrap('ota release react-native')} first.',
      );
      return ExitCode.usage.code;
    }
    if (release.flutterRevision != context.project.runtime &&
        results['allow-native-diffs'] != true) {
      logger.err(
        'Release $version was made with ${release.flutterRevision}, but this '
        'app now uses ${context.project.runtime}. Hermes bytecode only runs on '
        'the version it was built for. Ship a new app version instead.',
      );
      return ExitCode.software.code;
    }

    final bundle = await _bundle(context, platform);
    if (bundle == null) return ExitCode.software.code;

    final base = await codePushClientWrapper.getReleaseArtifact(
      appId: context.appId,
      releaseId: release.id,
      arch: reactNativeArch,
      platform: platform,
    );
    if (base.hash == bundle.hash) {
      logger.info(
        'No changes since release $version on ${platform.name}. Skipping.',
      );
      continue;
    }

    if (results['dry-run'] == true) {
      logger.info('Dry run: ${platform.name} patch was not uploaded.');
      continue;
    }

    final client = codePushClientWrapper.codePushClient;
    final patch = await client.createPatch(
      appId: context.appId,
      releaseId: release.id,
      metadata: {
        'runtime': context.project.runtime,
        'platform': platform.name,
      },
    );
    await client.createPatchArtifact(
      artifactPath: bundle.archive.path,
      appId: context.appId,
      patchId: patch.id,
      arch: reactNativeArch,
      platform: platform,
      hash: bundle.hash,
    );
    final channel =
        await codePushClientWrapper.maybeGetChannel(
          appId: context.appId,
          name: track,
        ) ??
        await codePushClientWrapper.createChannel(
          appId: context.appId,
          name: track,
        );
    await codePushClientWrapper.promotePatch(
      appId: context.appId,
      patchId: patch.id,
      channel: channel,
    );
    logger.success(
      'Published patch ${patch.number} for ${platform.name} $version on '
      '$track.',
    );
  }
  return ExitCode.success.code;
}

/// What `ota init` tells a React Native developer to do next.
String reactNativeNextSteps(ReactNativeProject project) {
  final relative = p.relative(project.root.path);
  final where = relative == '.' ? 'your app' : relative;
  return '''

${lightGreen.wrap('OTA initialized.')} "ota.yaml" was created in $where.

Finish the setup:

  1. npm install $reactNativeSdkPackage
  2. Add this as the first line of your entry file:
       import '$reactNativeSdkPackage';
  3. Android, MainApplication.kt:
       getDefaultReactHost(..., jsBundleFilePath = Ota.bundlePath(applicationContext))
  4. iOS, the release branch of bundleURL() in SceneDelegate.swift:
       Ota.bundleURL() ?? Bundle.main.url(forResource: "main", withExtension: "jsbundle")
  5. cd ios && pod install

Full guide: $reactNativeDocsUrl

Then: ${lightCyan.wrap('ota release react-native')}, ship the app, and push updates with ${lightCyan.wrap('ota patch react-native')}.''';
}
