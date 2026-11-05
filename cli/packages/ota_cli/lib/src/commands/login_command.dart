import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/auth/auth.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_env.dart';

/// {@template login_command}
/// `ota login`
/// Store the server URL and an API key.
/// {@endtemplate}
class LoginCommand extends OtaCommand {
  /// {@macro login_command}
  LoginCommand() {
    argParser
      ..addOption(
        'server',
        help: 'URL of your OTA server, e.g. https://ota.example.com',
      )
      ..addOption(
        'api-key',
        help: 'An API key created in the console (Account > API keys).',
      );
  }

  @override
  String get description => 'Sign in with an API key from your OTA console.';

  @override
  String get name => 'login';

  @override
  Future<int> run() async {
    if (auth.isAuthenticated) {
      logger
        ..info('You are already logged in as <${auth.email ?? 'API key'}>.')
        ..info('Run ${lightCyan.wrap('ota logout')} to log out first.');
      return ExitCode.success.code;
    }

    final serverInput =
        results['server'] as String? ??
        logger.prompt(
          'Server URL:',
          defaultValue: otaEnv.hostedUri.toString(),
        );
    final hostedUri = Uri.tryParse(serverInput.trim());
    if (hostedUri == null || !hostedUri.hasScheme) {
      logger.err('Invalid server URL: $serverInput');
      return ExitCode.usage.code;
    }
    final apiKey =
        results['api-key'] as String? ??
        logger.prompt('API key:', hidden: true);
    if (apiKey.trim().isEmpty) {
      logger.err('An API key is required.');
      return ExitCode.usage.code;
    }

    final progress = logger.progress('Checking the key with $hostedUri');
    try {
      await auth.login(hostedUri: hostedUri, apiKey: apiKey.trim());
    } on Exception catch (error) {
      progress.fail(error.toString());
      return ExitCode.software.code;
    }
    progress.complete();

    logger.info('''

🎉 ${lightGreen.wrap('You are now logged in as <${auth.email}>.')}

🔑 Credentials are stored in ${lightCyan.wrap(auth.credentialsFilePath)}.
🚪 To log out use: "${lightCyan.wrap('ota logout')}".''');
    return ExitCode.success.code;
  }
}
