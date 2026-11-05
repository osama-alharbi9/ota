import 'package:mason_logger/mason_logger.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/release_type.dart';
import 'package:ota_protocol/ota_protocol.dart';

/// Release types the OTA toolchain builds today. OTA ships its own Flutter
/// engine for Android only; other platforms need engines (and, on iOS, a
/// patch interpreter) that OTA does not build yet.
const supportedReleaseTypes = {ReleaseType.android, ReleaseType.aar};

/// Logs an error and returns false if any of [types] is unsupported.
bool checkSupportedReleaseTypes(Iterable<ReleaseType> types) {
  final unsupported = types.where((t) => !supportedReleaseTypes.contains(t));
  if (unsupported.isEmpty) return true;
  logger.err(
    '${unsupported.map((t) => t.name).join(', ')} is not supported by the '
    'OTA toolchain yet. Supported: android, aar.',
  );
  return false;
}

/// Logs an error and returns false if [platform] is not Android.
bool checkSupportedPlatform(ReleasePlatform platform) {
  if (platform == ReleasePlatform.android) return true;
  logger.err(
    '${platform.name} is not supported by the OTA toolchain yet. '
    'Supported: ${lightCyan.wrap('android')}.',
  );
  return false;
}
