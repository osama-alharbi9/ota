import 'package:ota_cli/src/commands/releases/releases.dart';
import 'package:ota_cli/src/ota_command.dart';

/// {@template releases_command}
/// Commands for managing OTA releases.
/// {@endtemplate}
class ReleasesCommand extends OtaCommand {
  /// {@macro releases_command}
  ReleasesCommand() {
    addSubcommand(GetApksCommand());
  }

  @override
  String get name => 'releases';

  @override
  String get description => 'Manage OTA releases';
}
