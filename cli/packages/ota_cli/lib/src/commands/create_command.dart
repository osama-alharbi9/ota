import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_process.dart';
import 'package:ota_cli/src/ota_validator.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// {@template ota_create_command}
/// `ota create`
/// Create a new Flutter app with OTA.
/// {@endtemplate}
class CreateCommand extends OtaProxyCommand {
  @override
  String get name => 'create';

  @override
  String get description => 'Create a new Flutter project with OTA.';

  @override
  Future<int> run() async {
    try {
      await otaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final createExitCode = await process.stream('flutter', [
      'create',
      ...results.rest,
    ]);

    if (createExitCode != ExitCode.success.code) {
      return createExitCode;
    }

    if (results.rest.contains('-h') || results.rest.contains('--help')) {
      return createExitCode;
    }

    return runScoped(
      () => runner!.run(['init']),
      values: {
        otaEnvRef.overrideWith(
          () => OtaEnv(
            flutterProjectRootOverride: p.absolute(
              p.normalize(results.rest.first),
            ),
          ),
        ),
      },
    );
  }
}
