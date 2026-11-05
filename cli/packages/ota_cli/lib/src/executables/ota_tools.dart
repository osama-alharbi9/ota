import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/toolchain_names.dart';
import 'package:path/path.dart' as p;
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_process.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to a [OtaTools] instance.
final otaToolsRef = create(OtaTools.new);

/// The [OtaTools] instance available in the current zone.
OtaTools get otaTools => read(otaToolsRef);

/// {@template package_failed_exception}
/// An exception thrown when packaging a patch fails.
/// {@endtemplate}
class PackageFailedException implements Exception {
  /// {@macro package_failed_exception}
  PackageFailedException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => message;
}

/// A wrapper around the `ota_tools` executable.
///
/// Used to access many commands related to OTA's flutter tooling.
class OtaTools {
  /// Returns whether the current flutter version supports this tool.
  ///
  /// This should be used to check if the tool is supported before running
  /// any commands.
  bool isSupported() {
    return otaToolsDirectory.existsSync();
  }

  /// The directory containing the `ota_tools` package.
  Directory get otaToolsDirectory {
    final dir = Directory(
      p.join(otaEnv.flutterDirectory.path, 'packages', toolchainToolsPackage),
    );
    return dir;
  }

  Future<OtaProcessResult> _run(List<String> args) {
    return process.run(
      otaEnv.dartBinaryFile.path,
      ['run', toolchainToolsPackage, 'package', ...args],
      workingDirectory: otaToolsDirectory.path,
    );
  }

  /// Creates a package with the [patchPath] and writes it to [outputPath].
  ///
  /// Packages contains all the information needed by OTA for an update.
  Future<void> package({
    required String patchPath,
    required String outputPath,
  }) async {
    final packageArguments = ['-p', patchPath, '-o', outputPath];

    final result = await _run(packageArguments);

    if (result.exitCode != ExitCode.success.code) {
      throw PackageFailedException('''
Failed to create package (exit code ${result.exitCode}).
  stdout: ${result.stdout}
  stderr: ${result.stderr}''');
    }
  }
}
