// cspell:words googleapis bryanoltman endtemplate CLI tgvek orctktiabrek
// cspell:words GOCSPX googleusercontent Pkkwp Entra
import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:ota_cli/src/http_client/http_client.dart';
import 'package:ota_cli/src/logging/logging.dart';
import 'package:ota_cli/src/platform.dart';
import 'package:ota_cli/src/ota_cli_command_runner.dart';
import 'package:ota_client/ota_client.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// A reference to an [Auth] instance.
final authRef = create(Auth.new);

/// The [Auth] instance available in the current zone.
Auth get auth => read(authRef);

/// Builds a [CodePushClient]; injectable for tests.
typedef CodePushClientBuilder =
    CodePushClient Function({required http.Client httpClient, Uri? hostedUri});

/// An HTTP client that authenticates requests using an API key.
///
/// It does not perform any token refresh or exchange: the API key is sent
/// directly in the Authorization header and the server validates it.
class ApiKeyClient extends http.BaseClient {
  /// Creates a new [ApiKeyClient].
  ApiKeyClient({required String apiKey, required http.Client httpClient})
    : _apiKey = apiKey,
      _baseClient = httpClient;

  final String _apiKey;
  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_apiKey';
    return _baseClient.send(request);
  }
}

/// Environment variable holding an API key (`sb_api_...`), overriding the
/// credentials file.
const otaTokenEnvVar = 'OTA_TOKEN';

/// Thrown when an API key is rejected by the server.
class InvalidApiKeyException implements Exception {
  @override
  String toString() => 'The server rejected this API key.';
}

/// API-key authentication against the self-hosted server.
///
/// Credentials live in `<config dir>/credentials.json` as
/// `{"hosted_url": ..., "api_key": ..., "email": ...}` and are written by
/// `ota login`. `OTA_TOKEN` in the environment overrides the stored key.
class Auth {
  /// Creates a new [Auth] instance.
  Auth({
    http.Client? httpClient,
    String? credentialsDir,
    CodePushClientBuilder? buildCodePushClient,
  }) : _httpClient = httpClient ?? _defaultHttpClient,
       _credentialsDir =
           credentialsDir ?? applicationConfigHome(executableName),
       _buildCodePushClient = buildCodePushClient ?? CodePushClient.new {
    _loadCredentials();
  }

  static http.Client get _defaultHttpClient => httpClient;

  final http.Client _httpClient;
  final String _credentialsDir;
  final CodePushClientBuilder _buildCodePushClient;
  String? _apiKey;
  String? _email;
  Uri? _hostedUri;

  /// The path to the credentials file.
  String get credentialsFilePath {
    return p.join(_credentialsDir, 'credentials.json');
  }

  /// The server URL stored by `ota login`, if any.
  Uri? get hostedUri => _hostedUri;

  /// The underlying HTTP client.
  http.Client get client {
    if (_apiKey != null) {
      return ApiKeyClient(apiKey: _apiKey!, httpClient: _httpClient);
    }
    return _httpClient;
  }

  /// Validates [apiKey] against the server at [hostedUri] and stores both.
  Future<void> login({required Uri hostedUri, required String apiKey}) async {
    final codePushClient = _buildCodePushClient(
      httpClient: ApiKeyClient(apiKey: apiKey, httpClient: _httpClient),
      hostedUri: hostedUri,
    );
    final user = await codePushClient.getCurrentUser();
    if (user == null) throw InvalidApiKeyException();
    _apiKey = apiKey;
    _email = user.email;
    _hostedUri = hostedUri;
    File(credentialsFilePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        json.encode({
          'hosted_url': hostedUri.toString(),
          'api_key': apiKey,
          'email': user.email,
        }),
      );
  }

  /// Removes stored credentials.
  Future<void> logout() async {
    _apiKey = null;
    _email = null;
    _hostedUri = null;
    final credentialsFile = File(credentialsFilePath);
    if (credentialsFile.existsSync()) credentialsFile.deleteSync();
  }

  /// The current user's email, when known.
  String? get email => _email;

  /// Whether an API key is available.
  bool get isAuthenticated => _apiKey != null;

  void _loadCredentials() {
    final credentialsFile = File(credentialsFilePath);
    if (credentialsFile.existsSync()) {
      try {
        final contents =
            json.decode(credentialsFile.readAsStringSync())
                as Map<String, dynamic>;
        _apiKey = contents['api_key'] as String?;
        _email = contents['email'] as String?;
        final url = contents['hosted_url'] as String?;
        _hostedUri = url == null ? null : Uri.tryParse(url);
      } on Exception {
        // Ignore a malformed credentials file; `ota login` rewrites it.
      }
    }
    final envToken = platform.environment[otaTokenEnvVar]?.trim();
    if (envToken != null && envToken.isNotEmpty) {
      logger.detail('[env] $otaTokenEnvVar detected');
      _apiKey = envToken;
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _httpClient.close();
  }
}

/// Thrown when an already authenticated user attempts to log in or sign up.
class UserAlreadyLoggedInException implements Exception {
  /// {@macro user_already_logged_in_exception}
  UserAlreadyLoggedInException({this.email});

  /// The email of the already authenticated user, or `null` when
  /// authenticated via an environment variable (API key / CI token).
  final String? email;
}

/// {@template user_not_found_exception}
/// Thrown when an attempt to fetch a User object results in a 404.
/// {@endtemplate}
class UserNotFoundException implements Exception {
  /// {@macro user_not_found_exception}
  UserNotFoundException({required this.email});

  /// The email used to locate the user, as derived from the stored auth
  /// credentials.
  final String email;
}
