import 'dart:async';

import 'package:ota_cli/src/ota_command.dart';
import 'package:ota_cli/src/ota_process.dart';

/// {@template flutter_config_command}
/// `ota flutter config`
/// Manage your OTA Flutter Config.
/// {@endtemplate}
class FlutterConfigCommand extends OtaProxyCommand {
  @override
  String get description =>
      '''Configure Flutter settings. This proxies to the underlying `flutter config` command.''';

  @override
  String get name => 'config';

  @override
  FutureOr<int> run() => process.stream('flutter', ['config', ...results.rest]);
}
