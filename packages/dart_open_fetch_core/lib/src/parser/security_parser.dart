import '../ir/api_security.dart';

/// Parses `components/securitySchemes` into [ApiSecurityScheme] IR nodes.
class SecurityParser {
  /// Parse all security schemes from components.
  List<ApiSecurityScheme> parse(Map<String, dynamic> schema) {
    final components = schema['components'] as Map<String, dynamic>?;
    if (components == null) return [];

    final schemes = components['securitySchemes'] as Map<String, dynamic>?;
    if (schemes == null) return [];

    return schemes.entries.map((entry) {
      return _parseScheme(entry.key, entry.value as Map<String, dynamic>);
    }).toList();
  }

  ApiSecurityScheme _parseScheme(String name, Map<String, dynamic> node) {
    final typeStr = node['type'] as String? ?? '';
    final type = _parseType(typeStr);

    Map<String, ApiOAuth2Flow>? flows;
    if (node.containsKey('flows')) {
      flows = {};
      final flowsNode = node['flows'] as Map<String, dynamic>;
      for (final entry in flowsNode.entries) {
        final flowNode = entry.value as Map<String, dynamic>;
        final scopes = <String, String>{};
        if (flowNode.containsKey('scopes')) {
          final scopesNode = flowNode['scopes'] as Map<String, dynamic>;
          for (final scopeEntry in scopesNode.entries) {
            scopes[scopeEntry.key] = scopeEntry.value as String;
          }
        }
        flows[entry.key] = ApiOAuth2Flow(
          authorizationUrl: flowNode['authorizationUrl'] as String?,
          tokenUrl: flowNode['tokenUrl'] as String?,
          refreshUrl: flowNode['refreshUrl'] as String?,
          scopes: scopes,
        );
      }
    }

    return ApiSecurityScheme(
      name: name,
      type: type,
      description: node['description'] as String?,
      location: node['in'] as String?,
      scheme: node['scheme'] as String?,
      bearerFormat: node['bearerFormat'] as String?,
      flows: flows,
      openIdConnectUrl: node['openIdConnectUrl'] as String?,
    );
  }

  SecuritySchemeType _parseType(String type) {
    switch (type) {
      case 'apiKey':
        return SecuritySchemeType.apiKey;
      case 'http':
        return SecuritySchemeType.http;
      case 'oauth2':
        return SecuritySchemeType.oauth2;
      case 'openIdConnect':
        return SecuritySchemeType.openIdConnect;
      default:
        return SecuritySchemeType.apiKey;
    }
  }
}
