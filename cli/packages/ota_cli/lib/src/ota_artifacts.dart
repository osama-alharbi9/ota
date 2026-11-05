// Allowing one member abstracts for consistency/namespace/ease of testing.
// ignore_for_file: one_member_abstracts

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:ota_cli/src/cache.dart';
import 'package:ota_cli/src/engine_config.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// All OTA artifacts used explicitly by OTA.
enum OtaArtifact {
  /// The iOS analyze_snapshot executable.
  analyzeSnapshotIos,

  /// The macOS analyze_snapshot executable.
  analyzeSnapshotMacOS,

  /// The aot_tools executable or kernel file.
  aotTools,

  /// The gen_snapshot executable for iOS.
  genSnapshotIos,

  /// The gen_snapshot executable for macOS that creates arm64 snapshots.
  genSnapshotMacosArm64,

  /// The gen_snapshot executable for macOS that creates x64 snapshots.
  genSnapshotMacosX64,
}

/// A reference to a [OtaArtifacts] instance.
final otaArtifactsRef = create<OtaArtifacts>(
  OtaCachedArtifacts.new,
);

/// The [OtaArtifacts] instance available in the current zone.
OtaArtifacts get otaArtifacts => read(otaArtifactsRef);

/// {@template ota_artifacts}
/// A class that provides access to OTA artifacts.
/// {@endtemplate}
abstract class OtaArtifacts {
  /// Returns the path to the given [artifact].
  String getArtifactPath({required OtaArtifact artifact});
}

/// {@template ota_cached_artifacts}
/// A class that provides access to cached OTA artifacts.
/// {@endtemplate}
class OtaCachedArtifacts implements OtaArtifacts {
  /// {@macro ota_cached_artifacts}
  const OtaCachedArtifacts();

  @override
  String getArtifactPath({required OtaArtifact artifact}) {
    switch (artifact) {
      case OtaArtifact.analyzeSnapshotIos:
        return _analyzeSnapshotIosFile.path;
      case OtaArtifact.analyzeSnapshotMacOS:
        return _analyzeSnapshotMacosFile.path;
      case OtaArtifact.aotTools:
        return _aotToolsFile.path;
      case OtaArtifact.genSnapshotIos:
        return _genSnapshotIosFile.path;
      case OtaArtifact.genSnapshotMacosArm64:
        return _genSnapshotMacOsArm64File.path;
      case OtaArtifact.genSnapshotMacosX64:
        return _genSnapshotMacOsX64File.path;
    }
  }

  File get _analyzeSnapshotIosFile {
    return File(
      p.join(
        otaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'analyze_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotMacosFile {
    return File(
      p.join(
        otaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'analyze_snapshot',
      ),
    );
  }

  File get _aotToolsFile {
    const executableName = 'aot-tools';
    final kernelFile = File(
      p.join(
        cache.getArtifactDirectory(executableName).path,
        otaEnv.otaEngineRevision,
        '$executableName.dill',
      ),
    );
    if (kernelFile.existsSync()) {
      return kernelFile;
    }

    // We shipped aot-tools as an executable in the past, so we return that if
    // no kernel file is found.
    return File(
      p.join(
        cache.getArtifactDirectory(executableName).path,
        otaEnv.otaEngineRevision,
        executableName,
      ),
    );
  }

  File get _genSnapshotIosFile {
    return File(
      p.join(
        otaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacOsArm64File {
    return File(
      p.join(
        otaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacOsX64File {
    return File(
      p.join(
        otaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'gen_snapshot_x64',
      ),
    );
  }
}

/// {@template ota_local_engine_artifacts}
/// A class that provides access to locally built OTA artifacts.
/// {@endtemplate}
class OtaLocalEngineArtifacts implements OtaArtifacts {
  /// {@macro ota_local_engine_artifacts}
  const OtaLocalEngineArtifacts();

  @override
  String getArtifactPath({required OtaArtifact artifact}) {
    switch (artifact) {
      case OtaArtifact.analyzeSnapshotIos:
        return _analyzeSnapshotIosFile.path;
      case OtaArtifact.analyzeSnapshotMacOS:
        return _analyzeSnapshotMacosFile.path;
      case OtaArtifact.aotTools:
        return _aotToolsFile.path;
      case OtaArtifact.genSnapshotIos:
        return _genSnapshotIosFile.path;
      case OtaArtifact.genSnapshotMacosArm64:
        return _genSnapshotMacosArm64File.path;
      case OtaArtifact.genSnapshotMacosX64:
        return _genSnapshotMacosX64File.path;
    }
  }

  File get _analyzeSnapshotIosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'analyze_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotMacosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'analyze_snapshot',
      ),
    );
  }

  File get _aotToolsFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'flutter',
        'third_party',
        'dart',
        'pkg',
        'aot_tools',
        'bin',
        'aot_tools.dart',
      ),
    );
  }

  File get _genSnapshotIosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacosArm64File {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'artifacts_arm64',
        'gen_snapshot',
      ),
    );
  }

  File get _genSnapshotMacosX64File {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'artifacts_x64',
        'gen_snapshot',
      ),
    );
  }
}
