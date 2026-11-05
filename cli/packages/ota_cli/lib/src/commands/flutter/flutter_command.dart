import 'package:ota_cli/src/commands/commands.dart';
import 'package:ota_cli/src/ota_command.dart';

/// {@template flutter_command}
/// `ota flutter`
/// Manage your OTA Flutter installation.
/// {@endtemplate}
class FlutterCommand extends OtaCommand {
  /// {@macro flutter_command}
  FlutterCommand() {
    addSubcommand(FlutterVersionsCommand());
    addSubcommand(FlutterConfigCommand());
  }

  @override
  String get description => 'Manage the Flutter version used by ota.';

  @override
  String get name => 'flutter';
}
