/// A security scheme definition from components/securitySchemes.
class ApiSecurityScheme {
  const ApiSecurityScheme({
    required this.name,
    required this.type,
    this.description,
    this.location,
    this.scheme,
    this.bearerFormat,
    this.flows,
    this.openIdConnectUrl,
  });

  /// Scheme name (the key in securitySchemes).
  final String name;

  /// Type: apiKey, http, oauth2, openIdConnect.
  final SecuritySchemeType type;

  /// Description.
  final String? description;

  /// Location for apiKey: query, header, cookie.
  final String? location;

  /// Scheme for http: bearer, basic, etc.
  final String? scheme;

  /// Bearer format hint (e.g., JWT).
  final String? bearerFormat;

  /// OAuth2 flows.
  final Map<String, ApiOAuth2Flow>? flows;

  /// OpenID Connect URL.
  final String? openIdConnectUrl;

  @override
  String toString() => 'ApiSecurityScheme($name, $type)';
}

/// OAuth2 flow configuration.
class ApiOAuth2Flow {
  const ApiOAuth2Flow({
    this.authorizationUrl,
    this.tokenUrl,
    this.refreshUrl,
    this.scopes = const {},
  });

  final String? authorizationUrl;
  final String? tokenUrl;
  final String? refreshUrl;
  final Map<String, String> scopes;
}

/// Security scheme types.
enum SecuritySchemeType {
  apiKey,
  http,
  oauth2,
  openIdConnect,
}
