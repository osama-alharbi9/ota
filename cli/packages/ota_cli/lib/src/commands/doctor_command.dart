import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/android_sdk.dart';
import 'package:ota_cli/src/android_studio.dart';
import 'package:ota_cli/src/doctor.dart';
import 'package:ota_cli/src/executables/executables.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/network_checker.dart';
import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_flutter.dart';
import 'package:ota_cli/src/version.dart';

/// {@template doctor_command}
/// `ota doctor`
/// A command that checks for potential issues with the current ota
/// environment.
/// {@endtemplate}
class DoctorCommand extends OtaCommand {
  /// {@macro doctor_command}
  DoctorCommand() {
    argParser
      ..addFlag(
        'fix',
        abbr: 'f',
        help: 'Fix issues where possible.',
        negatable: false,
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Enable verbose output.',
        negatable: false,
      );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    final verbose = results['verbose'] == true;
    final shouldFix = results['fix'] == true;
    final flutterVersion = await _tryGetFlutterVersion();
    final output = StringBuffer();
    final otaFlutterPrefix = StringBuffer('Flutter');

    if (flutterVersion != null) {
      otaFlutterPrefix.write(' $flutterVersion');
    }
    output.writeln('''
OTA CLI $packageVersion
$otaFlutterPrefix • revision ${otaEnv.flutterRevision}
Engine • revision ${otaEnv.otaEngineRevision}''');

    if (verbose) {
      final notDetected = red.wrap('not detected');
      var javaVersion = notDetected;

      final javaExe = java.executable;
      if (javaExe != null) {
        final result = java.version;
        if (result != null) {
          javaVersion = result
              .split(Platform.lineTerminator)
              // Adds empty space to the version will be padded with the
              // JAVA_VERSION label.
              .join('${Platform.lineTerminator}                  ');
        }
      }

      String? gradlewVersion;
      if (gradlew.exists(Directory.current.path)) {
        gradlewVersion = await gradlew.version(Directory.current.path);
      }

      output.writeln('''

Logs: ${otaEnv.logsDirectory.path}
Android Toolchain
  • Android Studio: ${androidStudio.path ?? notDetected}
  • Android SDK: ${androidSdk.path ?? notDetected}
  • ADB: ${androidSdk.adbPath ?? notDetected}
  • JAVA_HOME: ${java.home ?? notDetected}
  • JAVA_EXECUTABLE: ${javaExe ?? notDetected}
  • JAVA_VERSION: $javaVersion
  • Gradle: ${gradlewVersion ?? notDetected}''');
    }

    logger
      ..info(output.toString())
      ..info('URL Reachability');
    await networkChecker.checkReachability();
    logger.info('');

    if (verbose) {
      logger.info('Network Speed');
      final uploadProgress = logger.progress('Measuring GCP upload speed');

      try {
        final uploadSpeed = await networkChecker.performGCPUploadSpeedTest();
        uploadProgress.complete(
          'GCP Upload Speed: ${uploadSpeed.toStringAsFixed(2)} MB/s',
        );
      } on NetworkCheckerException catch (error) {
        uploadProgress.fail('GCP upload speed test failed: ${error.message}');
      } on Exception catch (error) {
        uploadProgress.fail('GCP upload speed test failed: $error');
      }

      final downloadProgress = logger.progress('Measuring GCP download speed');

      try {
        final downloadSpeed = await networkChecker
            .performGCPDownloadSpeedTest();
        downloadProgress.complete(
          'GCP Download Speed: ${downloadSpeed.toStringAsFixed(2)} MB/s',
        );
      } on NetworkCheckerException catch (error) {
        downloadProgress.fail(
          'GCP download speed test failed: ${error.message}',
        );
      } on Exception catch (error) {
        downloadProgress.fail('GCP download speed test failed: $error');
      }
      logger.info('');
    }

    await doctor.runValidators(doctor.generalValidators, applyFixes: shouldFix);

    return ExitCode.success.code;
  }

  Future<String?> _tryGetFlutterVersion() async {
    try {
      return await otaFlutter.getVersionString();
    } on Exception catch (error) {
      logger.detail('Unable to determine Flutter version.\n$error');
      return null;
    }
  }
}
