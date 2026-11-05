import 'package:ota_cli/src/pubspec_editor.dart';
import 'package:ota_cli/src/ota_env.dart';
import 'package:ota_cli/src/validators/validators.dart';

/// Verifies that ota.yaml is found in pubspec.yaml assets.
class OtaYamlAssetValidator extends Validator {
  @override
  String get description => 'ota.yaml found in pubspec.yaml assets';

  @override
  bool canRunInCurrentContext() => otaEnv.hasPubspecYaml;

  @override
  String get incorrectContextMessage => '''
The pubspec.yaml file does not exist.
The command you are running must be run within a Flutter app project.''';

  @override
  Future<List<ValidationIssue>> validate() async {
    if (!canRunInCurrentContext()) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'No pubspec.yaml file found',
        ),
      ];
    }

    if (otaEnv.pubspecContainsOtaYaml) {
      return [];
    }

    return [
      ValidationIssue(
        severity: ValidationIssueSeverity.error,
        message: 'No ota.yaml found in pubspec.yaml assets',
        fix: () => pubspecEditor.addOtaYamlToPubspecAssets(),
      ),
    ];
  }
}
