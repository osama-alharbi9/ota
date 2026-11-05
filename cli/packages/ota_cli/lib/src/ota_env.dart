import 'dart:convert';
import 'dart:io' hide Platform;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:cli_util/cli_util.dart';
import 'package:crypto/crypto.dart';
import 'package:ota_cli/src/toolchain_names.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:ota_cli/src/config/ota_yaml.dart';
import 'package:ota_cli/src/platform.dart';
import 'package:ota_cli/src/ota_cli_command_runner.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// Exception thrown when a required file in the OTA cache is missing or
/// unreadable, indicating a corrupted installation.
class CacheCorruptedException implements Exception {
  /// Creates a [CacheCorruptedException] for the given [filePath].
  const CacheCorruptedException(this.filePath);

  /// The path to the missing or unreadable file.
  final String filePath;

  @override
  String toString() =>
      'Could not read $filePath. Your OTA installation may be '
      "corrupted. Try running 'ota cache clean' and retrying.";
}

/// A reference to a [OtaEnv] instance.
final otaEnvRef = create(OtaEnv.new);

/// The [OtaEnv] instance available in the current zone.
OtaEnv get otaEnv => read(otaEnvRef);

/// {@template ota_env}
/// A class that provides access to ota environment metadata.
/// {@endtemplate}
class OtaEnv {
  /// {@macro ota_env}
  const OtaEnv({
    String? flutterRevisionOverride,
    String? flutterProjectRootOverride,
  }) : _flutterRevisionOverride = flutterRevisionOverride,
       _flutterProjectRootOverride = flutterProjectRootOverride;

  /// Copy the [OtaEnv] and optionally override the flutter revision.
  OtaEnv copyWith({String? flutterRevisionOverride}) => OtaEnv(
    flutterRevisionOverride:
        flutterRevisionOverride ?? _flutterRevisionOverride,
  );

  final String? _flutterRevisionOverride;
  final String? _flutterProjectRootOverride;

  /// The application config directory for the OTA CLI.
  Directory get configDirectory {
    return Directory(applicationConfigHome(executableName));
  }

  /// The directory where ota logs are stored.
  Directory get logsDirectory {
    return Directory(p.join(configDirectory.path, 'logs'));
  }

  /// The root directory of the OTA install.
  ///
  /// Assumes we are running from $ROOT/bin/cache.
  Directory get otaRoot {
    return File(platform.script.toFilePath()).parent.parent.parent;
  }

  /// The OTA engine revision.
  String get otaEngineRevision {
    final file = File(
      p.join(flutterDirectory.path, 'bin', 'internal', 'engine.version'),
    );
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      throw CacheCorruptedException(file.path);
    }
  }

  /// Get the OTA Flutter revision.
  String get flutterRevision {
    if (_flutterRevisionOverride != null) return _flutterRevisionOverride;
    final file = File(
      p.join(otaRoot.path, 'bin', 'internal', 'flutter.version'),
    );
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      throw CacheCorruptedException(file.path);
    }
  }

  /// Whether the project uses package:ota_code_push.
  bool get usesOtaCodePushPackage {
    final pubspec = getPubspecYaml();
    return pubspec?.dependencies.containsKey('ota_code_push') ?? false;
  }

  /// The root of the OTA-vended Flutter git checkout.
  Directory get flutterDirectory {
    return Directory(
      p.join(otaRoot.path, 'bin', 'cache', 'flutter', flutterRevision),
    );
  }

  /// The OTA-vended Flutter binary.
  File get flutterBinaryFile {
    final flutter = platform.isWindows ? 'flutter.bat' : 'flutter';
    return File(p.join(flutterDirectory.path, 'bin', flutter));
  }

  /// The OTA-vended Dart binary.
  File get dartBinaryFile {
    final dart = platform.isWindows ? 'dart.bat' : 'dart';
    return File(p.join(flutterDirectory.path, 'bin', dart));
  }

  /// The Cocoapods lockfile for this project's iOS app.
  File get iosPodfileLockFile {
    return File(p.join(getFlutterProjectRoot()!.path, 'ios', 'Podfile.lock'));
  }

  /// The hash of the Podfile.lock file for this project's iOS app. Will be null
  /// if the file does not exist.
  String? get iosPodfileLockHash {
    if (!iosPodfileLockFile.existsSync()) return null;
    return sha256.convert(iosPodfileLockFile.readAsBytesSync()).toString();
  }

  /// The Cocoapods lockfile for this project's macOS app.
  File get macosPodfileLockFile {
    return File(p.join(getFlutterProjectRoot()!.path, 'macos', 'Podfile.lock'));
  }

  /// The hash of the Podfile.lock file for this project's macOS app. Will be
  /// null if the file does not exist.
  String? get macosPodfileLockHash {
    if (!macosPodfileLockFile.existsSync()) return null;
    return sha256.convert(macosPodfileLockFile.readAsBytesSync()).toString();
  }

  /// The build directory of the current ota project.
  Directory get buildDirectory {
    return Directory(p.join(getFlutterProjectRoot()!.path, 'build'));
  }

  /// Where the link supplement files are stored.
  // TODO(eseidel): Make this not iOS specific.
  Directory get iosSupplementDirectory =>
      Directory(p.join(buildDirectory.path, 'ios', toolchainBuildDir));

  /// The `ota.yaml` file for this project (what developers edit).
  File getOtaYamlFile({required Directory cwd}) {
    return File(p.join(cwd.path, 'ota.yaml'));
  }

  /// OTA's artifact server: engine artifacts, the Maven repository and the
  /// patch tool. `OTA_ARTIFACTS_URL`, else `bin/internal/artifacts_url`.
  Uri get artifactsUri {
    final fromEnv = platform.environment['OTA_ARTIFACTS_URL'];
    if (fromEnv != null && fromEnv.isNotEmpty) return Uri.parse(fromEnv);
    return Uri.parse(_internalSetting('artifacts_url'));
  }

  /// OTA's git host for the Flutter fork. `OTA_FLUTTER_GIT_URL`, else
  /// `bin/internal/flutter_git_url`.
  String get flutterGitUrl {
    final fromEnv = platform.environment['OTA_FLUTTER_GIT_URL'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return _internalSetting('flutter_git_url');
  }

  String _internalSetting(String name) {
    final file = File(p.join(otaRoot.path, 'bin', 'internal', name));
    return file.readAsStringSync().trim();
  }

  /// The `pubspec.yaml` file for this project.
  File getPubspecYamlFile({required Directory cwd}) {
    return File(p.join(cwd.path, 'pubspec.yaml'));
  }

  /// Finds nearest ancestor file
  /// relative to the [cwd] that satisfies [where].
  File? findNearestAncestor({
    required File? Function(String path) where,
    Directory? cwd,
  }) {
    Directory? prev;
    var dir = cwd ?? Directory.current;
    while (prev?.path != dir.path) {
      final file = where(dir.path);
      if (file?.existsSync() ?? false) return file;
      prev = dir;
      dir = dir.parent;
    }
    return null;
  }

  /// Returns the root directory of the nearest OTA project.
  Directory? getOtaProjectRoot() {
    final file = findNearestAncestor(
      where: (path) => getOtaYamlFile(cwd: Directory(path)),
    );
    if (file == null || !file.existsSync()) return null;
    return Directory(p.dirname(file.path));
  }

  /// Returns the root directory of the nearest Flutter project.
  Directory? getFlutterProjectRoot() {
    if (_flutterProjectRootOverride != null) {
      return Directory(_flutterProjectRootOverride);
    }
    final file = findNearestAncestor(
      where: (path) => getPubspecYamlFile(cwd: Directory(path)),
    );
    if (file == null || !file.existsSync()) return null;
    return Directory(p.dirname(file.path));
  }

  /// The `ota.yaml` file for this project, parsed into a [OtaYaml]
  /// object.
  ///
  /// Returns `null` if the file does not exist.
  /// Throws a [ParsedYamlException] if the file exists but is invalid.
  OtaYaml? getOtaYaml() {
    final root = getOtaProjectRoot();
    if (root == null) return null;
    final yaml = getOtaYamlFile(cwd: root).readAsStringSync();
    return checkedYamlDecode(yaml, (m) => OtaYaml.fromJson(m!));
  }

  /// The `pubspec.yaml` file for this project, parsed into a [Pubspec] object.
  ///
  /// Returns `null` if the file does not exist.
  /// Throws a [ParsedYamlException] if the file exists but is invalid.
  Pubspec? getPubspecYaml() {
    final root = getFlutterProjectRoot();
    if (root == null) return null;
    try {
      final yaml = getPubspecYamlFile(cwd: root).readAsStringSync();
      return Pubspec.parse(yaml, lenient: true);
    } on Exception {
      return null;
    }
  }

  /// Whether the current project has a `ota.yaml` file.
  bool get hasOtaYaml => getOtaYaml() != null;

  /// Whether the current project has a `pubspec.yaml` file.
  bool get hasPubspecYaml => getPubspecYaml() != null;

  /// Whether the current project's `pubspec.yaml` file contains a reference to
  /// `ota.yaml` in its `assets` section.
  bool get pubspecContainsOtaYaml {
    final pubspec = getPubspecYaml();
    if (pubspec == null) return false;
    if (pubspec.flutter == null) return false;
    if (pubspec.flutter!['assets'] == null) return false;
    final assets = pubspec.flutter!['assets'] as List;
    return assets.contains('ota.yaml');
  }

  /// Returns the Android package name from the pubspec.yaml file of a Flutter
  /// module.
  String? get androidPackageName {
    final pubspec = getPubspecYaml();
    final module = pubspec?.flutter?['module'] as Map?;
    return module?['androidPackage'] as String?;
  }

  /// The base URL of the OTA server. In order: `OTA_HOSTED_URL`, `base_url`
  /// in `ota.yaml`, the server stored by `ota login`, then localhost.
  Uri get hostedUri {
    final fromEnv = platform.environment['OTA_HOSTED_URL'];
    if (fromEnv != null) return Uri.parse(fromEnv);
    try {
      final fromYaml = getOtaYaml()?.baseUrl;
      if (fromYaml != null) return Uri.parse(fromYaml);
    } on Exception {
      // Fall through.
    }
    final stored = _storedCredentials()?['hosted_url'] as String?;
    if (stored != null) return Uri.parse(stored);
    return Uri.parse('http://localhost:8080');
  }

  /// The console (dashboard) URL: `OTA_CONSOLE_URL`, else stored by login,
  /// else localhost.
  Uri get consoleUri {
    final fromEnv = platform.environment['OTA_CONSOLE_URL'];
    if (fromEnv != null) return Uri.parse(fromEnv);
    final stored = _storedCredentials()?['console_url'] as String?;
    if (stored != null) return Uri.parse(stored);
    return Uri.parse('http://localhost:3100');
  }

  Map<String, dynamic>? _storedCredentials() {
    final file = File(p.join(configDirectory.path, 'credentials.json'));
    if (!file.existsSync()) return null;
    try {
      return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    } on Exception {
      return null;
    }
  }

  /// Whether the CLI can accept user input via stdin.
  bool get canAcceptUserInput => stdin.hasTerminal && !isRunningOnCI;

  /// Whether platform.environment indicates that we are running on a CI
  /// platform. This implementation is intended to behave similar to the Flutter
  /// tool's:
  /// https://github.com/flutter/flutter/blob/0c10e1ca54ae74043909059e2ff56bf5dd0c3d23/packages/flutter_tools/lib/src/base/bot_detector.dart#L48-L69
  bool get isRunningOnCI =>
      platform.environment['BOT'] == 'true'
      // https://docs.travis-ci.com/user/environment-variables/#Default-Environment-Variables
      ||
      platform.environment['TRAVIS'] == 'true' ||
      platform.environment['CONTINUOUS_INTEGRATION'] == 'true' ||
      platform.environment.containsKey('CI') // Travis and AppVeyor
      // https://www.appveyor.com/docs/environment-variables/
      ||
      platform.environment.containsKey('APPVEYOR')
      // https://cirrus-ci.org/guide/writing-tasks/#environment-variables
      ||
      platform.environment.containsKey('CIRRUS_CI')
      // https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-env-vars.html
      ||
      (platform.environment.containsKey('AWS_REGION') &&
          platform.environment.containsKey('CODEBUILD_INITIATOR'))
      // https://wiki.jenkins.io/display/JENKINS/Building+a+software+project#Buildingasoftwareproject-belowJenkinsSetEnvironmentVariables
      ||
      platform.environment.containsKey('JENKINS_URL')
      // https://help.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables
      ||
      platform.environment.containsKey('GITHUB_ACTIONS')
      // https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml
      ||
      platform.environment.containsKey('TF_BUILD');
}
