import '../ir/api_info.dart';

/// Parses `info` and `servers` into [ApiInfo].
class InfoParser {
  /// Parse the info and servers sections.
  ApiInfo parse(Map<String, dynamic> schema) {
    final info = schema['info'] as Map<String, dynamic>? ?? {};

    final servers = <String>[];
    if (schema.containsKey('servers')) {
      final serverList = schema['servers'] as List;
      for (final server in serverList) {
        final serverNode = server as Map<String, dynamic>;
        var url = serverNode['url'] as String? ?? '';

        // Resolve server variables using default values
        if (serverNode.containsKey('variables')) {
          final variables = serverNode['variables'] as Map<String, dynamic>;
          for (final entry in variables.entries) {
            final varNode = entry.value as Map<String, dynamic>;
            final defaultValue = varNode['default'] as String? ?? '';
            url = url.replaceAll('{${entry.key}}', defaultValue);
          }
        }

        servers.add(url);
      }
    }

    return ApiInfo(
      title: info['title'] as String? ?? 'Untitled API',
      version: info['version'] as String? ?? '0.0.0',
      description: info['description'] as String?,
      servers: servers,
    );
  }
}
