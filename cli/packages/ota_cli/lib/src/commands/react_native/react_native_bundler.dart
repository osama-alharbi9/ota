import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ota_cli/src/commands/react_native/react_native_archive.dart';
import 'package:ota_cli/src/commands/react_native/react_native_project.dart';
import 'package:ota_client/ota_client.dart';
import 'package:path/path.dart' as p;

/// A failure while building a bundle, with the output worth showing.
class ReactNativeBundleException implements Exception {
  /// Creates a [ReactNativeBundleException].
  ReactNativeBundleException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// {@template react_native_bundle}
/// A packed update: the JavaScript bundle and the assets it uses.
/// {@endtemplate}
class ReactNativeBundle {
  /// {@macro react_native_bundle}
  const ReactNativeBundle({required this.archive, required this.hash});

  /// The `.tar.gz` that devices download.
  final File archive;

  /// The SHA-256 of [archive].
  final String hash;
}

/// The bundle file name the app loads on [platform].
String reactNativeBundleName(ReleasePlatform platform) =>
    platform == ReleasePlatform.android
    ? 'index.android.bundle'
    : 'main.jsbundle';

/// Bundles the app for [platform] the way its release build does: Metro, then
/// Hermes, then packs the result.
Future<ReactNativeBundle> buildReactNativeBundle({
  required ReactNativeProject project,
  required ReleasePlatform platform,
  required String entryFile,
}) async {
  final work = Directory(
    p.join(project.root.path, 'build', 'ota', platform.name),
  );
  if (work.existsSync()) work.deleteSync(recursive: true);
  final contents = Directory(p.join(work.path, 'contents'))
    ..createSync(recursive: true);
  final bundle = File(p.join(contents.path, reactNativeBundleName(platform)));
  final hermes = project.usesHermes(platform);

  await _run(
    'npx',
    [
      'react-native',
      'bundle',
      '--platform',
      platform.name,
      '--dev',
      'false',
      '--entry-file',
      entryFile,
      '--bundle-output',
      bundle.path,
      '--assets-dest',
      contents.path,
      // Hermes does its own minification.
      if (hermes) ...['--minify', 'false'],
    ],
    workingDirectory: project.root.path,
  );

  if (hermes) {
    final compiler = project.hermesCompiler();
    if (compiler == null) {
      throw ReactNativeBundleException(
        'Could not find hermesc in node_modules. Run your package manager\'s '
        'install, then try again.',
      );
    }
    final bytecode = File('${bundle.path}.hbc');
    await _run(compiler.path, [
      '-w',
      '-O',
      '-emit-binary',
      '-out',
      bytecode.path,
      bundle.path,
    ], workingDirectory: project.root.path);
    bundle.deleteSync();
    bytecode.renameSync(bundle.path);
  }

  final bytes = packDirectory(contents);
  final archive = File(p.join(work.path, 'update.tar.gz'))
    ..writeAsBytesSync(bytes);
  return ReactNativeBundle(
    archive: archive,
    hash: sha256.convert(bytes).toString(),
  );
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    throw ReactNativeBundleException(
      '$executable ${arguments.join(' ')} failed:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}
