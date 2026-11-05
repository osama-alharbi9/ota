import 'dart:io';

import 'package:ota_cli/src/ota_version.dart';
import 'package:ota_cli/src/validators/validators.dart';

/// Verifies that the currently installed version of OTA is the latest.
class OtaVersionValidator extends Validator {
  /// Creates a new [OtaVersionValidator].
  OtaVersionValidator();

  @override
  String get description => 'OTA is up-to-date';

  @override
  Future<List<ValidationIssue>> validate() async {
    final bool isOtaUpToDate;

    try {
      isOtaUpToDate = await otaVersion.isLatest();
    } on ProcessException catch (e) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to get ota version. Error: ${e.message}',
        ),
      ];
    }

    if (!isOtaUpToDate) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '''
A new version of ota is available! Run `ota upgrade` to upgrade.''',
        ),
      ];
    }

    return [];
  }
}
