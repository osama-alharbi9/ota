import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:ota_cli/src/archive/directory_archive.dart';
import 'package:ota_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:ota_cli/src/artifact_builder/artifact_builder.dart';
import 'package:ota_cli/src/artifact_manager.dart';
import 'package:ota_cli/src/code_push_client_wrapper.dart';
import 'package:ota_cli/src/commands/patch/patch.dart';
import 'package:ota_cli/src/doctor.dart';
import 'package:ota_cli/src/executables/aot_tools.dart';
import 'package:ota_cli/src/executables/xcodebuild.dart';
import 'package:ota_cli/src/extensions/arg_results.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/metadata/metadata.dart';
import 'package:ota_cli/src/patch_diff_checker.dart';
import 'package:ota_cli/src/platform/platform.dart';
import 'package:ota_cli/src/release_type.dart';
import 'package:ota_cli/src/ota_artifacts.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_validator.dart';
import 'package:ota_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:ota_client/ota_client.dart';

/// {@template ios_framework_patcher}
/// Functions to patch an iOS Framework release.
/// {@endtemplate}
class IosFrameworkPatcher extends Patcher {
  /// {@macro ios_framework_patcher}
  IosFrameworkPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  String get _aotOutputPath => p.join(otaEnv.buildDirectory.path, 'out.aot');

  String get _vmcodeOutputPath =>
      p.join(otaEnv.buildDirectory.path, 'out.vmcode');

  String get _appDillCopyPath =>
      p.join(otaEnv.buildDirectory.path, 'app.dill');

  @override
  String get primaryReleaseArtifactArch => 'xcframework';

  @override
  String? get supplementaryReleaseArtifactArch => 'ios_framework_supplement';

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  /// The last build's link metadata.
  @visibleForTesting
  Map<String, dynamic>? lastBuildLinkMetadata;

  @override
  double? get linkPercentage => lastBuildLinkPercentage;

  /// The last build link percentage.
  @visibleForTesting
  double? lastBuildLinkPercentage;

  @override
  Future<void> assertPreconditions() async {
    try {
      await otaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkOtaInitialized: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<void> assertArgsAreValid() async {
    if (!argResults.wasParsed('release-version')) {
      logger.err('Missing required argument: --release-version');
      throw ProcessExit(ExitCode.usage.code);
    }
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) => patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
    localArchive: patchArchive,
    releaseArchive: releaseArchive,
    archiveDiffer: const AppleArchiveDiffer(),
    allowAssetChanges: allowAssetDiffs,
    allowNativeChanges: allowNativeDiffs,
  );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final buildArgs = [...argResults.forwardedArgs, ...extraBuildArgs];
    final buildResult = await artifactBuilder.buildIosFramework(
      args: buildArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );

    if (splitDebugInfoPath != null) {
      Directory(splitDebugInfoPath!).createSync(recursive: true);
    }
    await artifactBuilder.buildElfAotSnapshot(
      appDillPath: buildResult.kernelFile.path,
      outFilePath: _aotOutputPath,
      genSnapshotArtifact: OtaArtifact.genSnapshotIos,
      additionalArgs: [
        ...IosPatcher.splitDebugInfoArgs(splitDebugInfoPath),
        ...obfuscationGenSnapshotArgs,
      ],
    );

    // Copy the kernel file to the build directory so that it can be used
    // to generate a patch.
    buildResult.kernelFile.copySync(_appDillCopyPath);

    return Directory(
      p.join(
        artifactManager.getAppXcframeworkDirectory().path,
        ArtifactManager.appXcframeworkName,
      ),
    ).zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) async {
    final unzipProgress = logger.progress('Extracting release artifact');
    late final String releaseXcframeworkPath;
    {
      final tempDir = Directory.systemTemp.createTempSync();
      await artifactManager.extractZip(
        zipFile: releaseArtifact,
        outputDirectory: tempDir,
      );
      releaseXcframeworkPath = tempDir.path;
    }

    final releaseSupplementDir =
        supplementDirectory ?? Directory.systemTemp.createTempSync();

    unzipProgress.complete(
      'Extracted release artifact to $releaseXcframeworkPath',
    );
    final releaseArtifactFile = File(
      p.join(releaseXcframeworkPath, 'ios-arm64', 'App.framework', 'App'),
    );

    final aotSnapshotFile = File(
      p.join(otaEnv.getOtaProjectRoot()!.path, 'build', 'out.aot'),
    );
    // TODO(eseidel): Drop support for builds before the linker.
    final useLinker = AotTools.usesLinker(otaEnv.flutterRevision);
    if (useLinker) {
      apple.copySupplementFilesToSnapshotDirs(
        releaseSupplementDir: releaseSupplementDir,
        releaseSnapshotDir: releaseArtifactFile.parent,
        patchSupplementDir: otaEnv.iosSupplementDirectory,
        patchSnapshotDir: otaEnv.buildDirectory,
      );

      final result = await apple.runLinker(
        kernelFile: File(_appDillCopyPath),
        releaseArtifact: releaseArtifactFile,
        splitDebugInfoArgs: [
          ...IosPatcher.splitDebugInfoArgs(splitDebugInfoPath),
          ...obfuscationGenSnapshotArgs,
        ],
        aotOutputFile: File(_aotOutputPath),
        vmCodeFile: File(_vmcodeOutputPath),
      );
      final linkPercentage = result.linkPercentage;
      final exitCode = result.exitCode;
      if (exitCode != ExitCode.success.code) throw ProcessExit(exitCode);
      if (linkPercentage != null &&
          linkPercentage < Patcher.linkPercentageWarningThreshold) {
        logger.warn(Patcher.lowLinkPercentageWarning(linkPercentage));
      }
      lastBuildLinkPercentage = linkPercentage;
      lastBuildLinkMetadata = result.linkMetadata;
    }

    final patchBuildFile = useLinker
        ? File(_vmcodeOutputPath)
        : aotSnapshotFile;
    final File patchFile;
    if (await aotTools.isGeneratePatchDiffBaseSupported()) {
      final patchBaseProgress = logger.progress('Generating patch diff base');
      final analyzeSnapshotPath = otaArtifacts.getArtifactPath(
        artifact: OtaArtifact.analyzeSnapshotIos,
      );

      final File patchBaseFile;
      try {
        // If the aot_tools executable supports the dump_blobs command, we
        // can generate a stable diff base and use that to create a patch.
        patchBaseFile = await aotTools.generatePatchDiffBase(
          analyzeSnapshotPath: analyzeSnapshotPath,
          releaseSnapshot: releaseArtifactFile,
        );
        patchBaseProgress.complete();
      } on Exception catch (error) {
        patchBaseProgress.fail('$error');
        throw ProcessExit(ExitCode.software.code);
      }

      patchFile = File(
        await artifactManager.createDiff(
          releaseArtifactPath: patchBaseFile.path,
          patchArtifactPath: patchBuildFile.path,
        ),
      );
    } else {
      patchFile = patchBuildFile;
    }

    final patchFileSize = patchFile.statSync().size;
    final hash = sha256.convert(patchBuildFile.readAsBytesSync()).toString();
    final hashSignature = await signHash(hash);

    return {
      Arch.arm64: PatchArtifactBundle(
        arch: 'aarch64',
        path: patchFile.path,
        hash: hash,
        size: patchFileSize,
        hashSignature: hashSignature,
      ),
    };
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    // Not implemented - release version must be specified by the user.
    throw UnimplementedError(
      'Release version must be specified using --release-version.',
    );
  }

  @override
  Future<CreatePatchMetadata> updatedCreatePatchMetadata(
    CreatePatchMetadata metadata,
  ) async => metadata.copyWith(
    linkPercentage: lastBuildLinkPercentage,
    linkMetadata: lastBuildLinkMetadata,
    environment: metadata.environment.copyWith(
      xcodeVersion: await xcodeBuild.version(),
    ),
  );
}
