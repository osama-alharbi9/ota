import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:ota_cli/src/ota_cli_command_runner.dart';
import 'package:ota_client/ota_client.dart';

/// Signature for a function which takes a list of bytes and returns a hash.
typedef HashFunction = String Function(List<int> bytes);

/// Signature for a function which takes a path to a zip file.
typedef UnzipFn = Future<void> Function(String zipFilePath, String outputDir);

/// Signature for a function which builds a [CodePushClient].
typedef CodePushClientBuilder =
    CodePushClient Function({required http.Client httpClient, Uri? hostedUri});

/// Signature for a function which starts a process (e.g. [Process.start]).
typedef StartProcess =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

/// {@template ota_command}
/// A command in the OTA CLI.
/// {@endtemplate}
abstract class OtaCommand extends Command<int> {
  // We don't currently have a test involving both a CommandRunner
  // and a Command, so we can't test this getter.
  // coverage:ignore-start
  @override
  OtaCliCommandRunner? get runner =>
      testRunner ?? super.runner as OtaCliCommandRunner?;
  // coverage:ignore-end

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// The parent command runner used for testing purposes only.
  @visibleForTesting
  OtaCliCommandRunner? testRunner;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;
}

/// {@template ota_proxy_command}
/// A command in the OTA CLI that proxies to an underlying process.
/// {@endtemplate}
abstract class OtaProxyCommand extends OtaCommand {
  @override
  ArgParser get argParser => ArgParser.allowAnything();
}
