import 'package:json_annotation/json_annotation.dart';

part 'ota_yaml.g.dart';

/// The patch verification mode for the app.
@JsonEnum(fieldRename: FieldRename.snake)
enum PatchVerification {
  /// Verify the patch signature and hash before installing and loading.
  strict,

  /// Verify the patch signature and hash before installing, but not when
  /// loading from cache.
  installOnly,
}

/// {@template ota_yaml}
/// An OTA configuration file which contains metadata about the app.
/// {@endtemplate}
@JsonSerializable(anyMap: true, disallowUnrecognizedKeys: true)
class OtaYaml {
  /// {@macro ota_yaml}
  const OtaYaml({
    required this.appId,
    this.flavors,
    this.baseUrl,
    this.autoUpdate,
    this.patchVerification,
    this.channel,
  });

  /// Creates a [OtaYaml] from a JSON map.
  factory OtaYaml.fromJson(Map<dynamic, dynamic> json) =>
      _$OtaYamlFromJson(json);

  /// Converts this [OtaYaml] to a JSON map.
  Map<String, dynamic> toJson() => _$OtaYamlToJson(this);

  /// The base app id.
  ///
  /// Example:
  /// `"8d3155a8-a048-4820-acca-824d26c29b71"`
  final String appId;

  /// A map of flavor names to app ids.
  ///
  /// Will be `null` for apps with no flavors.
  ///
  /// Example:
  /// ```json
  /// {
  ///   "development": "8d3155a8-a048-4820-acca-824d26c29b71",
  ///   "production": "d458e87a-7362-4386-9eeb-629db2af413a"
  /// }
  /// ```
  final Map<String, String>? flavors;

  /// The base url used to check for updates.
  final String? baseUrl;

  /// Whether or not to automatically update the app.
  final bool? autoUpdate;

  /// The patch verification mode for the app.
  final PatchVerification? patchVerification;

  /// The channel this build of the app follows. Defaults to `stable`.
  final String? channel;
}

/// Extension on [OtaYaml] to get the app id for a specific flavor.
extension AppIdExtension on OtaYaml {
  /// Returns the app id for the given flavor.
  String getAppId({String? flavor}) {
    if (flavor == null || flavors == null) return appId;
    return flavors![flavor] ?? appId;
  }
}
