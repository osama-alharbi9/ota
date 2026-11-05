import 'package:ota_cli/src/commands/patches/patches.dart';
import 'package:ota_cli/src/ota_command.dart';

/// {@template patches_command}
/// Commands for managing OTA patches.
/// {@endtemplate}
class PatchesCommand extends OtaCommand {
  /// {@macro patches_command}
  PatchesCommand() {
    addSubcommand(PromoteCommand());
    addSubcommand(SetTrackCommand());
  }

  @override
  String get name => 'patches';

  @override
  String get description => 'Manage OTA patches';
}
