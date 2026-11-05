import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_flutter.dart';

/// {@template flutter_versions_list_command}
/// `ota flutter versions list`
/// List available Flutter versions.
/// {@endtemplate}
class FlutterVersionsListCommand extends OtaCommand {
  /// {@macro flutter_versions_list_command}
  FlutterVersionsListCommand();

  @override
  String get description => 'List available Flutter versions.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final progress = logger.progress('Fetching Flutter versions');

    String? currentVersion;
    try {
      currentVersion = await otaFlutter.getVersionString();
    } on ProcessException catch (error) {
      logger.detail('Unable to determine Flutter version.\n${error.message}');
    }

    final List<String> versions;
    try {
      versions = await otaFlutter.getVersions();
      progress.cancel();
    } on Exception catch (error) {
      progress.fail('Failed to fetch Flutter versions.');
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info('📦 Flutter Versions');
    for (final version in versions.reversed) {
      logger.info(
        version == currentVersion ? lightCyan.wrap('✓ $version') : '  $version',
      );
    }
    return ExitCode.success.code;
  }
}
