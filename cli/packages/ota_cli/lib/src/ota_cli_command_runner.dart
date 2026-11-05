import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/commands/commands.dart';
import 'package:ota_cli/src/engine_config.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/platform.dart';
import 'package:ota_cli/src/ota_artifacts.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_flutter.dart';
import 'package:ota_cli/src/ota_process.dart';
import 'package:ota_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:ota_cli/src/version.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// The name of the executable.
const executableName = 'ota';

/// The name of the package (e.g. name in the pubspec.yaml).
const packageName = 'ota_cli';

/// The package description.
const description = 'Over-the-air updates for Flutter and React Native apps';

/// {@template ota_cli_command_runner}
/// A [CommandRunner] for the CLI.
///
/// ```sh
/// $ ota --version
/// ```
/// {@endtemplate}
class OtaCliCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro ota_cli_command_runner}
  OtaCliCommandRunner() : super(executableName, description) {
    argParser
      ..addFlag('version', negatable: false, help: 'Print the current version.')
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Noisy logging, including all shell commands executed.',
        callback: (verbose) {
          if (verbose) {
            logger.level = Level.verbose;
          }
        },
      )
      ..addOption(
        'local-engine-src-path',
        hide: true,
        help:
            'Path to your engine src directory, if you are building Flutter '
            'locally.',
      )
      ..addOption(
        'local-engine',
        hide: true,
        help:
            'Name of a build output within the engine out directory, if you '
            'are building Flutter locally.',
      )
      ..addOption(
        'local-engine-host',
        hide: true,
        help: 'The build of the local engine to use as the host platform.',
      );

    addCommand(CacheCommand());
    addCommand(CreateCommand());
    addCommand(DoctorCommand());
    addCommand(FlutterCommand());
    addCommand(InitCommand());
    addCommand(LoginCommand());
    addCommand(LogoutCommand());
    addCommand(PatchCommand());
    addCommand(PatchesCommand());
    addCommand(PreviewCommand());
    addCommand(ReleaseCommand());
    addCommand(ReleasesCommand());
  }

  @override
  void printUsage() => logger.info(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);

      final localEngineSrcPath =
          topLevelResults['local-engine-src-path'] as String?;
      final localEngine = topLevelResults['local-engine'] as String?;
      final localEngineHost = topLevelResults['local-engine-host'] as String?;

      final localEngineArgs = [
        localEngineSrcPath,
        localEngine,
        localEngineHost,
      ];
      final localEngineArgsAreNull = localEngineArgs.every(
        (arg) => arg == null,
      );
      final localEngineArgsAreNotNull = localEngineArgs.every(
        (arg) => arg != null,
      );
      final EngineConfig engineConfig;
      if (localEngineArgsAreNotNull) {
        engineConfig = EngineConfig(
          localEngineSrcPath: localEngineSrcPath,
          localEngine: localEngine,
          localEngineHost: localEngineHost,
        );
      } else if (localEngineArgsAreNull) {
        engineConfig = const EngineConfig.empty();
      } else {
        // Only some local engine args were provided, this is invalid.
        throw ArgumentError(
          '''local-engine, local-engine-src, and local-engine-host must all be provided''',
        );
      }

      final process = OtaProcess();
      final otaArtifacts = engineConfig.localEngineSrcPath != null
          ? const OtaLocalEngineArtifacts()
          : const OtaCachedArtifacts();
      return await runScoped<Future<int?>>(
            () => runCommand(topLevelResults),
            values: {
              engineConfigRef.overrideWith(() => engineConfig),
              processRef.overrideWith(() => process),
              otaArtifactsRef.overrideWith(() => otaArtifacts),
            },
          ) ??
          ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      logger
        ..err(e.message)
        ..detail('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code

      logger.err(e.message);
      if (e.message.contains('Could not find an option named')) {
        final String errorMessage;
        if (platform.isWindows) {
          errorMessage = '''
To proxy an option to the flutter command, use the '--' --<option> syntax.

Example:

${lightCyan.wrap("ota release android '--' --no-pub lib/main.dart")}''';
        } else {
          errorMessage = '''
To proxy an option to the flutter command, use the -- --<option> syntax.

Example:

${lightCyan.wrap('ota release android -- --no-pub lib/main.dart')}''';
        }

        logger.err(errorMessage);
      }

      logger
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    // Fast track completion command
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }

    // Run the command or show version
    int? exitCode;
    if (topLevelResults['version'] == true) {
      logger.info('ota CLI $packageVersion');
      // The Flutter toolchain only exists once a Flutter project has used it.
      if (otaEnv.flutterBinaryFile.existsSync()) {
        final flutterVersion = await _tryGetFlutterVersion();
        final otaFlutterPrefix = StringBuffer('Flutter');
        if (flutterVersion != null) {
          otaFlutterPrefix.write(' $flutterVersion');
        }
        logger.info('''
$otaFlutterPrefix • revision ${otaEnv.flutterRevision}
Engine • revision ${otaEnv.otaEngineRevision}''');
      }
      exitCode = ExitCode.success.code;
    } else {
      try {
        exitCode = await super.runCommand(topLevelResults);
      } on ProcessExit catch (error) {
        exitCode = error.exitCode;
      } on UsageException catch (e) {
        logger
          ..err(e.message)
          ..info(e.usage);
        // When on an usage exception we don't need to show the "if you aren't
        // sure" message, so we do an early return here.
        return ExitCode.usage.code;

        // We explicitly want to catch all exceptions here to log them and show
        // the user a friendly message.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stackTrace) {
        logger
          ..err('$error')
          ..detail('$stackTrace');
        exitCode = ExitCode.software.code;
      }
    }

    // `runCommand` returns null in when the --help flag is passed.
    if (exitCode != null &&
        exitCode != ExitCode.success.code &&
        logger.level != Level.verbose) {
      logger.info('''

If you aren't sure why this command failed, re-run with the ${lightCyan.wrap('--verbose')} flag to see more information.
Log file: ${currentRunLogFile.absolute.path}
''');
    }

    return exitCode;
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
