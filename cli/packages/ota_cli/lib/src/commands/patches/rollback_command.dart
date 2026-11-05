import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/code_push_client_wrapper.dart';
import 'package:ota_cli/src/config/config.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_validator.dart';
import 'package:ota_client/ota_client.dart';

/// {@template rollback_command}
/// Rolls a patch back: devices drop it on their next update check and return to
/// the newest patch that is still live, or to the release.
/// {@endtemplate}
class RollbackCommand extends OtaCommand {
  /// {@macro rollback_command}
  RollbackCommand() {
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'release-version',
        help: 'The release the patch belongs to.',
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The number of the patch to roll back.',
        mandatory: true,
      )
      ..addFlag(
        'undo',
        negatable: false,
        help: 'Restore a patch that was rolled back.',
      );
  }

  @override
  String get name => 'rollback';

  @override
  String get description => 'Rolls a patch back on every device.';

  @override
  Future<int> run() async {
    try {
      await otaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkOtaInitialized: false,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final otaYaml = otaEnv.getOtaYaml();
    if (otaYaml == null) {
      logger.err('Could not find ota.yaml. Run this from your app.');
      return ExitCode.usage.code;
    }
    final patchNumber = int.tryParse(results['patch-number'] as String);
    if (patchNumber == null) {
      logger.err('--patch-number must be a number.');
      return ExitCode.usage.code;
    }

    final undo = results['undo'] == true;
    final releaseVersion = results['release-version'] as String;
    try {
      await codePushClientWrapper.codePushClient.setPatchRolledBack(
        appId: otaYaml.getAppId(flavor: results['flavor'] as String?),
        releaseVersion: releaseVersion,
        patchNumber: patchNumber,
        rolledBack: !undo,
      );
    } on CodePushException catch (error) {
      logger.err(error.message);
      return ExitCode.software.code;
    }

    logger.success(
      undo
          ? 'Restored patch $patchNumber of $releaseVersion.'
          : 'Rolled back patch $patchNumber of $releaseVersion.',
    );
    return ExitCode.success.code;
  }
}
