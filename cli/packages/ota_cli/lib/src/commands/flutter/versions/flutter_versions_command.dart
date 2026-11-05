import 'package:ota_cli/src/commands/commands.dart';
import 'package:ota_cli/src/ota_command.dart';

/// {@template flutter_versions_command}
/// `ota flutter versions`
/// Manage your OTA Flutter versions.
/// {@endtemplate}
class FlutterVersionsCommand extends OtaCommand {
  /// {@macro flutter_versions_command}
  FlutterVersionsCommand() {
    addSubcommand(FlutterVersionsListCommand());
  }

  @override
  String get description => 'Manage your OTA Flutter versions.';

  @override
  String get name => 'versions';
}
