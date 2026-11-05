import 'package:ota_cli/src/commands/commands.dart';
import 'package:ota_cli/src/ota_command.dart';

/// {@template cache_command}
/// `ota cache`
/// Manage the OTA cache.
/// {@endtemplate}
class CacheCommand extends OtaCommand {
  /// {@macro cache_command}
  CacheCommand() {
    addSubcommand(CleanCacheCommand());
  }

  @override
  String get description => 'Manage the OTA cache.';

  @override
  String get name => 'cache';
}
