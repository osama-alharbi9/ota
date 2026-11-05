import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/auth/auth.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/ota_command.dart';

/// {@template logout_command}
///
/// `ota logout`
/// Forget the stored server URL and API key.
/// {@endtemplate}
class LogoutCommand extends OtaCommand {
  @override
  String get description => 'Forget the stored server URL and API key';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = logger.progress('Removing stored credentials');
    await auth.logout();
    logoutProgress.complete();

    logger.info('${lightGreen.wrap('You are now logged out.')}');

    return ExitCode.success.code;
  }
}
