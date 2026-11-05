// cspell:words swiftobjective ckotlinjava havent
import 'package:mason_logger/mason_logger.dart';

/// Link to the project's documentation.
const docsUrl = 'https://github.com/osama-alharbi9/ota/tree/main/docs';

/// Link to the Flutter guide, which covers versions and troubleshooting.
const flutterVersionUrl =
    'https://github.com/osama-alharbi9/ota/blob/main/docs/flutter.md';

/// Link to the supported Flutter versions.
const supportedFlutterVersionsUrl = flutterVersionUrl;

/// Link to troubleshooting help.
const troubleshootingUrl = flutterVersionUrl;

/// Link to help with an unsupported class file version.
const unsupportedClassFileVersionUrl = troubleshootingUrl;

/// Link to help with running the app in VS Code after installing the CLI.
const cannotRunInVSCodeUrl = troubleshootingUrl;

/// Link to what causes the asset changes warning and what to do about it.
const assetChangesTroubleshootingUrl = troubleshootingUrl;

/// Link to what causes the native code changes warning and what to do about it.
const nativeChangesTroubleshootingUrl = troubleshootingUrl;

/// Extension to convert a string to a CLI link.
extension ToLink on String {
  /// Wraps the string in a link.
  String toLink() => link(uri: Uri.parse(this));
}
