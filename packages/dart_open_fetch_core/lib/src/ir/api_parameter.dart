import 'api_schema.dart';

/// A parameter for an API operation.
class ApiParameter {
  const ApiParameter({
    required this.name,
    required this.location,
    required this.schema,
    this.required_ = false,
    this.description,
    this.style,
    this.explode,
    this.deprecated = false,
  });

  /// Parameter name.
  final String name;

  /// Where the parameter goes.
  final ParameterLocation location;

  /// The parameter's type schema.
  final ApiSchema schema;

  /// Whether the parameter is required.
  final bool required_;

  /// Parameter description.
  final String? description;

  /// Serialization style (simple, form, label, matrix, etc.).
  final String? style;

  /// Whether to explode array/object params.
  final bool? explode;

  /// Whether this parameter is deprecated.
  final bool deprecated;

  /// Effective style (default depends on location).
  String get effectiveStyle {
    if (style != null) return style!;
    switch (location) {
      case ParameterLocation.path:
        return 'simple';
      case ParameterLocation.query:
      case ParameterLocation.cookie:
        return 'form';
      case ParameterLocation.header:
        return 'simple';
    }
  }

  /// Effective explode (default depends on style).
  bool get effectiveExplode {
    if (explode != null) return explode!;
    return effectiveStyle == 'form';
  }

  @override
  String toString() => 'ApiParameter($name in $location)';
}

/// Where a parameter is located.
enum ParameterLocation {
  query,
  path,
  header,
  cookie,
}
