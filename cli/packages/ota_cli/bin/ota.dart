import 'dart:io';

import 'package:ota_cli/src/abi.dart';
import 'package:ota_cli/src/android_sdk.dart';
import 'package:ota_cli/src/android_studio.dart';
import 'package:ota_cli/src/artifact_builder/artifact_builder.dart';
import 'package:ota_cli/src/artifact_builder/build_trace_session.dart';
import 'package:ota_cli/src/artifact_builder/ota_tracer.dart';
import 'package:ota_cli/src/artifact_manager.dart';
import 'package:ota_cli/src/auth/auth.dart';
import 'package:ota_cli/src/cache.dart';
import 'package:ota_cli/src/checksum_checker.dart';
import 'package:ota_cli/src/code_push_client_wrapper.dart';
import 'package:ota_cli/src/code_signer.dart';
import 'package:ota_cli/src/doctor.dart';
import 'package:ota_cli/src/engine_config.dart';
import 'package:ota_cli/src/executables/executables.dart';
import 'package:ota_cli/src/http_client/http_client.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/network_checker.dart';
import 'package:ota_cli/src/os/os.dart';
import 'package:ota_cli/src/patch_diff_checker.dart';
import 'package:ota_cli/src/platform.dart';
import 'package:ota_cli/src/platform/platform.dart';
import 'package:ota_cli/src/pubspec_editor.dart';
import 'package:ota_cli/src/ota_android_artifacts.dart';
import 'package:ota_cli/src/ota_artifacts.dart';
import 'package:ota_cli/src/ota_cli_command_runner.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/ota_flutter.dart';
import 'package:ota_cli/src/ota_process.dart';
import 'package:ota_cli/src/ota_validator.dart';
import 'package:ota_cli/src/ota_version.dart';
import 'package:scoped_deps/scoped_deps.dart';

Future<void> main(List<String> args) async {
  final commandStartedAt = DateTime.now();
  final loggingStdout = runScoped(
    () => LoggingStdout(baseStdOut: stdout, logFile: currentRunLogFile),
    values: {otaEnvRef},
  );

  // Write the current command to the top of the log file.
  currentRunLogFile.writeAsStringSync('''
Command: ota ${args.join(' ')}

''', mode: FileMode.append);

  await IOOverrides.runZoned(
    () async => _flushThenExit(
      await runScoped(
        () async => OtaCliCommandRunner().run(args),
        values: {
          abiRef,
          adbRef,
          androidSdkRef,
          androidStudioRef,
          aotToolsRef,
          appleRef,
          artifactBuilderRef,
          artifactManagerRef,
          buildTraceSessionRef.overrideWith(
            () => BuildTraceSession(commandStartedAt: commandStartedAt),
          ),
          authRef,
          bundletoolRef,
          cacheRef,
          checksumCheckerRef,
          codePushClientWrapperRef,
          codeSignerRef,
          devicectlRef,
          diffRef,
          dittoRef,
          doctorRef,
          engineConfigRef,
          gitRef,
          gradlewRef,
          httpClientRef,
          idevicesyslogRef,
          iosDeployRef,
          javaRef,
          linuxRef,
          loggerRef,
          networkCheckerRef,
          openRef,
          osInterfaceRef,
          patchExecutableRef,
          patchDiffCheckerRef,
          platformRef,
          powershellRef,
          processRef,
          pubspecEditorRef,
          otaAndroidArtifactsRef,
          otaArtifactsRef,
          otaEnvRef,
          otaFlutterRef,
          otaTracerRef,
          otaToolsRef,
          otaValidatorRef,
          otaVersionRef,
          windowsRef,
          xcodeBuildRef,
        },
      ),
    ),
    stdout: () => loggingStdout,
    stderr: () => loggingStdout,
  );
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([
    stdout.close(),
    stderr.close(),
  ]).then<void>((_) => exit(status));
}
