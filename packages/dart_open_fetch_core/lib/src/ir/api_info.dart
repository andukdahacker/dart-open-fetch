/// API metadata from the info section and servers.
class ApiInfo {
  const ApiInfo({
    required this.title,
    required this.version,
    this.description,
    this.servers = const [],
  });

  /// API title.
  final String title;

  /// API version string.
  final String version;

  /// API description.
  final String? description;

  /// Resolved server base URLs (server variables substituted with defaults).
  final List<String> servers;

  /// The first server URL, or empty string if none.
  String get baseUrl => servers.isNotEmpty ? servers.first : '';

  @override
  String toString() => 'ApiInfo($title v$version)';
}
