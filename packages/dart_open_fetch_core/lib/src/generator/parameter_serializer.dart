import '../diagnostic.dart';
import '../ir/api_parameter.dart';
import '../ir/api_schema.dart';
import 'name_resolver.dart';

/// Generates code for parameter serialization in client methods.
///
/// v0.1 supports:
/// - Path params: `style: simple` (string interpolation via Uri.encodeComponent)
/// - Query params: `style: form, explode: true` (repeated keys for arrays)
///
/// Non-default styles use default serialization with a warning.
class ParameterSerializer {
  ParameterSerializer({required this.nameResolver});

  final NameResolver nameResolver;
  final List<Diagnostic> diagnostics = [];

  /// Generate a path interpolation expression for a path parameter.
  ///
  /// Returns code that produces the URL-encoded string value of [paramName].
  String pathParamExpression(ApiParameter param) {
    final fieldName = NameResolver.resolveFieldName(param.name);

    if (param.effectiveStyle != 'simple') {
      diagnostics.add(Diagnostic(
        message:
            'Parameter "${param.name}" uses style "${param.effectiveStyle}" '
            'which is not supported in v0.1. Using default "simple" style.',
        severity: DiagnosticSeverity.warning,
      ));
    }

    return 'Uri.encodeComponent($fieldName.toString())';
  }

  /// Generate a query parameter map entry expression.
  ///
  /// Returns a list of statements that add query params to a `queryParams`
  /// map variable. Handles nullable params, array explosion, etc.
  String queryParamStatements(ApiParameter param) {
    final fieldName = NameResolver.resolveFieldName(param.name);
    final paramName = param.name;
    final isRequired = param.required_;
    final isArray = param.schema.isArray;

    if (param.effectiveStyle != 'form') {
      diagnostics.add(Diagnostic(
        message:
            'Parameter "${param.name}" uses style "${param.effectiveStyle}" '
            'which is not supported in v0.1. Using default "form" style.',
        severity: DiagnosticSeverity.warning,
      ));
    }

    final buf = StringBuffer();

    if (isArray && param.effectiveExplode) {
      // Exploded arrays: repeated keys ?a=1&a=2
      if (isRequired) {
        buf.writeln(
            "    queryParams['$paramName'] = $fieldName.map((v) => v.toString()).toList();");
      } else {
        buf.writeln('    if ($fieldName != null) {');
        buf.writeln(
            "      queryParams['$paramName'] = $fieldName.map((v) => v.toString()).toList();");
        buf.writeln('    }');
      }
    } else {
      if (isRequired) {
        buf.writeln(
            "    queryParams['$paramName'] = [$fieldName.toString()];");
      } else {
        buf.writeln('    if ($fieldName != null) {');
        buf.writeln(
            "      queryParams['$paramName'] = [$fieldName.toString()];");
        buf.writeln('    }');
      }
    }

    return buf.toString();
  }

  /// Get the Dart type for a parameter.
  String paramDartType(ApiParameter param) {
    final baseType = _schemaToType(param.schema);
    if (!param.required_) {
      return '$baseType?';
    }
    return baseType;
  }

  String _schemaToType(ApiSchema schema) {
    if (schema.isEnum && schema.name != null) {
      return nameResolver.resolveClassName(schema.name!);
    }
    if (schema.name != null && (schema.isObject || schema.isComposed)) {
      return nameResolver.resolveClassName(schema.name!);
    }
    return switch (schema.type) {
      SchemaType.string => 'String',
      SchemaType.integer => 'int',
      SchemaType.number => 'double',
      SchemaType.boolean => 'bool',
      SchemaType.array => schema.items != null
          ? 'List<${_schemaToType(schema.items!)}>'
          : 'List<dynamic>',
      SchemaType.object => 'Map<String, dynamic>',
      _ => 'dynamic',
    };
  }
}
