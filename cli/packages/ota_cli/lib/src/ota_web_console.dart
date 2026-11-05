import 'package:ota_cli/src/ota_env.dart';

/// OTA console URLs.
class OtaWebConsole {
  /// Returns a [Uri] for a console page.
  static Uri uri(String path) {
    return Uri.parse('${otaEnv.consoleUri}/$path');
  }

  /// Returns a [Uri] for a release page in the console.
  static Uri appReleaseUri(String appId, int releaseId) {
    return OtaWebConsole.uri('apps/$appId/releases/$releaseId');
  }
}
