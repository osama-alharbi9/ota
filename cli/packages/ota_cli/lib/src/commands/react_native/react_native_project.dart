import 'dart:convert';
import 'dart:io';

import 'package:ota_client/ota_client.dart';
import 'package:path/path.dart' as p;

/// The name of the SDK apps install to receive updates.
const reactNativeSdkPackage = 'ota-react-native';

/// The architecture patches are stored under: a bundle runs on every CPU.
const reactNativeArch = 'js';

/// The prefix of the runtime stored on a React Native release, followed by the
/// React Native version. Hermes bytecode only runs on the version it was built
/// for, so patches must match it.
const reactNativeRuntimePrefix = 'react-native@';

/// {@template react_native_project}
/// A React Native app on disk.
/// {@endtemplate}
class ReactNativeProject {
  /// {@macro react_native_project}
  ReactNativeProject(this.root);

  /// The nearest React Native project at or above [cwd], or null if none.
  static ReactNativeProject? find({Directory? cwd}) {
    Directory? previous;
    var dir = cwd ?? Directory.current;
    while (previous?.path != dir.path) {
      final project = ReactNativeProject(dir);
      if (project._dependencies.containsKey('react-native')) return project;
      previous = dir;
      dir = dir.parent;
    }
    return null;
  }

  /// The project root, where `package.json` lives.
  final Directory root;

  File _file(String relativePath) => File(p.join(root.path, relativePath));

  Map<String, dynamic> get _packageJson {
    final file = _file('package.json');
    if (!file.existsSync()) return const {};
    try {
      return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException {
      return const {};
    }
  }

  Map<String, dynamic> get _dependencies =>
      (_packageJson['dependencies'] as Map<String, dynamic>?) ?? const {};

  /// The `name` in `package.json`.
  String get name => (_packageJson['name'] as String?) ?? p.basename(root.path);

  /// Whether the app depends on the SDK.
  bool get hasSdk => _dependencies.containsKey(reactNativeSdkPackage);

  /// The React Native version installed in `node_modules`.
  String? get reactNativeVersion {
    final file = _file(p.join('node_modules', 'react-native', 'package.json'));
    if (!file.existsSync()) return null;
    final package = json.decode(file.readAsStringSync()) as Map;
    return package['version'] as String?;
  }

  /// The value stored on a release to pin patches to this React Native version.
  String get runtime => '$reactNativeRuntimePrefix$reactNativeVersion';

  /// The platforms this app has a native project for.
  List<ReleasePlatform> get platforms => [
    if (Directory(p.join(root.path, 'android')).existsSync())
      ReleasePlatform.android,
    if (Directory(p.join(root.path, 'ios')).existsSync()) ReleasePlatform.ios,
  ];

  /// The first existing entry file, or null if none exists.
  String? get defaultEntryFile {
    for (final candidate in const ['index.js', 'index.ts', 'index.tsx']) {
      if (_file(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Whether [entryFile] loads the SDK. Without that import a booted patch is
  /// never confirmed, so every patch rolls back on the following launch.
  bool entryLoadsSdk(String entryFile) {
    final file = _file(entryFile);
    return file.existsSync() &&
        file.readAsStringSync().contains(reactNativeSdkPackage);
  }

  /// The version the native app reports on [platform], or null if unknown.
  String? releaseVersion(ReleasePlatform platform) {
    switch (platform) {
      case ReleasePlatform.android:
        for (final name in const ['build.gradle', 'build.gradle.kts']) {
          final file = _file(p.join('android', 'app', name));
          if (file.existsSync()) {
            return parseAndroidVersion(file.readAsStringSync());
          }
        }
        return null;
      case ReleasePlatform.ios:
        final ios = Directory(p.join(root.path, 'ios'));
        if (!ios.existsSync()) return null;
        for (final entry in ios.listSync()) {
          if (entry is Directory && entry.path.endsWith('.xcodeproj')) {
            final file = File(p.join(entry.path, 'project.pbxproj'));
            if (file.existsSync()) {
              return parseIosVersion(file.readAsStringSync());
            }
          }
        }
        return null;
      case ReleasePlatform.linux:
      case ReleasePlatform.macos:
      case ReleasePlatform.windows:
        return null;
    }
  }

  /// Whether the build for [platform] compiles JavaScript to Hermes bytecode.
  bool usesHermes(ReleasePlatform platform) {
    if (platform == ReleasePlatform.android) {
      final file = _file(p.join('android', 'gradle.properties'));
      if (!file.existsSync()) return true;
      return !RegExp(
        r'^\s*hermesEnabled\s*=\s*false',
        multiLine: true,
      ).hasMatch(file.readAsStringSync());
    }
    final file = _file(p.join('ios', 'Podfile'));
    if (!file.existsSync()) return true;
    return !RegExp(
      r':hermes_enabled\s*=>\s*false',
    ).hasMatch(file.readAsStringSync());
  }

  /// The `hermesc` compiler React Native ships for this machine, or null.
  File? hermesCompiler() {
    final String binDir;
    if (Platform.isMacOS) {
      binDir = 'osx-bin';
    } else if (Platform.isLinux) {
      binDir = 'linux64-bin';
    } else {
      binDir = 'win64-bin';
    }
    final executable = Platform.isWindows ? 'hermesc.exe' : 'hermesc';
    for (final package in const [
      ['hermes-compiler', 'hermesc'],
      ['react-native', 'sdks', 'hermesc'],
    ]) {
      final file = _file(
        p.joinAll(['node_modules', ...package, binDir, executable]),
      );
      if (file.existsSync()) return file;
    }
    return null;
  }
}

/// Reads `versionName` and `versionCode` from a Gradle build file as
/// `name+code`, the form the app reports at runtime.
String? parseAndroidVersion(String gradle) {
  final name = RegExp(r'''versionName\s*=?\s*["']([^"']+)["']''');
  final code = RegExp(r'versionCode\s*=?\s*(\d+)');
  final versionName = name.firstMatch(gradle)?.group(1);
  final versionCode = code.firstMatch(gradle)?.group(1);
  if (versionName == null || versionCode == null) return null;
  return '$versionName+$versionCode';
}

/// Reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from an Xcode project
/// as `name+build`, the form the app reports at runtime.
String? parseIosVersion(String pbxproj) {
  String? setting(String key) => RegExp(
    '$key\\s*=\\s*"?([^";]+)"?;',
  ).firstMatch(pbxproj)?.group(1)?.trim();
  final name = setting('MARKETING_VERSION');
  final build = setting('CURRENT_PROJECT_VERSION');
  if (name == null || build == null) return null;
  return '$name+$build';
}
