// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: implicit_dynamic_parameter, require_trailing_commas, cast_nullable_to_non_nullable, lines_longer_than_80_chars, strict_raw_type, unnecessary_lambdas

part of 'build_environment_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BuildEnvironmentMetadata _$BuildEnvironmentMetadataFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'BuildEnvironmentMetadata',
  json,
  ($checkedConvert) {
    final val = BuildEnvironmentMetadata(
      flutterRevision: $checkedConvert('flutter_revision', (v) => v as String),
      otaVersion: $checkedConvert(
        'ota_version',
        (v) => v as String,
      ),
      operatingSystem: $checkedConvert('operating_system', (v) => v as String),
      operatingSystemVersion: $checkedConvert(
        'operating_system_version',
        (v) => v as String,
      ),
      otaYaml: $checkedConvert(
        'ota_yaml',
        (v) => OtaYaml.fromJson(v as Map<String, dynamic>),
      ),
      usesOtaCodePushPackage: $checkedConvert(
        'uses_ota_code_push_package',
        (v) => v as bool,
      ),
      xcodeVersion: $checkedConvert('xcode_version', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'flutterRevision': 'flutter_revision',
    'otaVersion': 'ota_version',
    'operatingSystem': 'operating_system',
    'operatingSystemVersion': 'operating_system_version',
    'otaYaml': 'ota_yaml',
    'usesOtaCodePushPackage': 'uses_ota_code_push_package',
    'xcodeVersion': 'xcode_version',
  },
);

Map<String, dynamic> _$BuildEnvironmentMetadataToJson(
  BuildEnvironmentMetadata instance,
) => <String, dynamic>{
  'flutter_revision': instance.flutterRevision,
  'ota_version': instance.otaVersion,
  'operating_system': instance.operatingSystem,
  'operating_system_version': instance.operatingSystemVersion,
  'ota_yaml': instance.otaYaml.toJson(),
  'uses_ota_code_push_package': instance.usesOtaCodePushPackage,
  'xcode_version': instance.xcodeVersion,
};
