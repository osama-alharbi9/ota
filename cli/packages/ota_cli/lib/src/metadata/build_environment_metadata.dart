import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:ota_cli/src/config/config.dart';

part 'build_environment_metadata.g.dart';

/// {@template build_environment_metadata}
/// Information about the environment used to build a release or patch.
///
/// Collection of this information is done to help OTA users debug any
/// later failures in their builds.
///
/// We do not collect Personally Identifying Information (e.g. no paths,
/// argument lists, etc.) in accordance with our privacy policy:
/// {@endtemplate}
@JsonSerializable()
class BuildEnvironmentMetadata extends Equatable {
  /// {@macro build_environment_metadata}
  const BuildEnvironmentMetadata({
    required this.flutterRevision,
    required this.otaVersion,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.otaYaml,
    required this.usesOtaCodePushPackage,
    this.xcodeVersion,
  });

  /// coverage:ignore-start
  /// Creates a [BuildEnvironmentMetadata] with overridable default values for
  /// testing purposes.
  factory BuildEnvironmentMetadata.forTest({
    String flutterRevision = '853d13d954df3b6e9c2f07b72062f33c52a9a64b',
    String otaVersion = '4.5.6',
    String operatingSystem = 'macos',
    String operatingSystemVersion = '1.2.3',
    OtaYaml otaYaml = const OtaYaml(appId: '123'),
    bool usesOtaCodePushPackage = false,
    String? xcodeVersion = '15.0',
  }) => BuildEnvironmentMetadata(
    flutterRevision: flutterRevision,
    otaVersion: otaVersion,
    operatingSystem: operatingSystem,
    operatingSystemVersion: operatingSystemVersion,
    otaYaml: otaYaml,
    usesOtaCodePushPackage: usesOtaCodePushPackage,
    xcodeVersion: xcodeVersion,
  );
  // coverage:ignore-end

  /// Converts a `Map<String, dynamic>` to a [BuildEnvironmentMetadata]
  factory BuildEnvironmentMetadata.fromJson(Map<String, dynamic> json) =>
      _$BuildEnvironmentMetadataFromJson(json);

  /// Converts a [BuildEnvironmentMetadata] to a `Map<String, dynamic>`
  Map<String, dynamic> toJson() => _$BuildEnvironmentMetadataToJson(this);

  /// Creates a copy of this [BuildEnvironmentMetadata] with the given fields
  /// replaced by the new values.
  BuildEnvironmentMetadata copyWith({
    String? flutterRevision,
    String? otaVersion,
    String? operatingSystem,
    String? operatingSystemVersion,
    OtaYaml? otaYaml,
    bool? usesOtaCodePushPackage,
    String? xcodeVersion,
  }) => BuildEnvironmentMetadata(
    flutterRevision: flutterRevision ?? this.flutterRevision,
    otaVersion: otaVersion ?? this.otaVersion,
    operatingSystem: operatingSystem ?? this.operatingSystem,
    operatingSystemVersion:
        operatingSystemVersion ?? this.operatingSystemVersion,
    otaYaml: otaYaml ?? this.otaYaml,
    usesOtaCodePushPackage:
        usesOtaCodePushPackage ?? this.usesOtaCodePushPackage,
    xcodeVersion: xcodeVersion ?? this.xcodeVersion,
  );

  /// The revision of Flutter used to run the command.
  ///
  /// Reason: often times we want to track things like link percentage
  /// which are tied to a flutter revision as opposed to an OTA version.
  final String flutterRevision;

  /// The version of OTA used to run the command.
  ///
  /// Reason: each version of ota has new features and bug fixes. Users
  /// using an older version may be running into issues that have already been
  /// fixed.
  final String otaVersion;

  /// The operating system used to run the release command.
  ///
  /// Reason: issues may occur on some OSes and not others (especially Windows
  /// vs non-Windows).
  final String operatingSystem;

  /// The version of [operatingSystem].
  ///
  /// Reason: issues may occur on some OS versions and not others.
  final String operatingSystemVersion;

  /// The ota.yaml file for this project.
  final OtaYaml otaYaml;

  /// Whether the project uses package:ota_code_push.
  ///
  /// Reason: this helps us understand which projects are using the OTA
  /// CodePush package and better support customers who encounter issues.
  final bool usesOtaCodePushPackage;

  /// The version of Xcode used to build the patch. Only provided for iOS
  /// patches.
  ///
  /// Reason: Xcode behavior can change between versions. Ex: the
  /// `ota preview` mechanism changed entirely between Xcode 14 and 15.
  final String? xcodeVersion;

  @override
  List<Object?> get props => [
    flutterRevision,
    otaVersion,
    operatingSystem,
    operatingSystemVersion,
    otaYaml,
    usesOtaCodePushPackage,
    xcodeVersion,
  ];
}
