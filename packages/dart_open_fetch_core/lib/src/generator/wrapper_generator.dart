import '../ir/api_operation.dart';
import '../ir/api_parameter.dart';
import '../ir/api_schema.dart';
import '../ir/api_spec.dart';
import 'name_resolver.dart';

/// A generated wrapper class with its source code.
class GeneratedWrapper {
  const GeneratedWrapper({
    required this.className,
    required this.clientClassName,
    required this.source,
  });

  final String className;
  final String clientClassName;
  final String source;
}

/// Generates thin service wrappers around generated client classes.
///
/// For each client, produces a `{Name}Service` that wraps `{Name}Client`.
/// Only wraps operations with typed responses (`Future<ApiResponse<T>>` →
/// `Future<T>`). Operations returning `Future<HttpResponse>` are skipped.
class WrapperGenerator {
  WrapperGenerator({
    required this.nameResolver,
    this.clientNameOverride,
  });

  final NameResolver nameResolver;
  final String? clientNameOverride;

  /// Generate wrapper classes from the spec.
  List<GeneratedWrapper> generateWrappers(ApiSpec spec) {
    final allOps = <_OperationWithPath>[];
    for (final path in spec.paths) {
      for (final op in path.operations) {
        allOps.add(_OperationWithPath(path.path, op));
      }
    }

    if (allOps.isEmpty) return [];

    if (clientNameOverride != null) {
      final serviceName = clientNameOverride!.endsWith('Client')
          ? '${clientNameOverride!.substring(0, clientNameOverride!.length - 6)}Service'
          : '${clientNameOverride!}Service';
      return [
        _generateWrapper(serviceName, clientNameOverride!, allOps),
      ].whereType<GeneratedWrapper>().toList();
    }

    // Group operations by tag (same logic as ClientGenerator)
    final grouped = <String, List<_OperationWithPath>>{};
    var anyHasTags = false;

    for (final entry in allOps) {
      if (entry.operation.tags.isNotEmpty) {
        anyHasTags = true;
        final tag = entry.operation.tags.first;
        grouped.putIfAbsent(tag, () => []).add(entry);
      } else {
        grouped.putIfAbsent('Default', () => []).add(entry);
      }
    }

    if (!anyHasTags) {
      final clientName = _deriveClientName(spec.info.title);
      final serviceName = clientName.endsWith('Client')
          ? '${clientName.substring(0, clientName.length - 6)}Service'
          : '${clientName}Service';
      return [
        _generateWrapper(serviceName, clientName, allOps),
      ].whereType<GeneratedWrapper>().toList();
    }

    final wrappers = <GeneratedWrapper>[];
    for (final entry in grouped.entries) {
      final tag = _upperCamelCase(entry.key);
      final clientName = '${tag}Client';
      final serviceName = '${tag}Service';
      final wrapper = _generateWrapper(serviceName, clientName, entry.value);
      if (wrapper != null) wrappers.add(wrapper);
    }
    return wrappers;
  }

  GeneratedWrapper? _generateWrapper(
    String serviceName,
    String clientClassName,
    List<_OperationWithPath> operations,
  ) {
    // Filter to only typed operations
    final typedOps = operations
        .where((e) => e.operation.successResponse?.jsonSchema != null)
        .toList();

    if (typedOps.isEmpty) return null;

    final buf = StringBuffer();

    buf.writeln(
        "import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart' as runtime;");
    buf.writeln();

    buf.writeln('/// Thin service wrapper around [$clientClassName].');
    buf.writeln('///');
    buf.writeln(
        '/// Unwraps [runtime.ApiResponse] so callers get `Future<T>` directly.');
    buf.writeln('class $serviceName {');
    buf.writeln('  $serviceName(this._client);');
    buf.writeln();
    buf.writeln('  final $clientClassName _client;');
    buf.writeln();

    for (final entry in typedOps) {
      _writeWrapperMethod(buf, entry.operation);
      buf.writeln();
    }

    buf.writeln('}');

    return GeneratedWrapper(
      className: serviceName,
      clientClassName: clientClassName,
      source: buf.toString(),
    );
  }

  void _writeWrapperMethod(StringBuffer buf, ApiOperation operation) {
    final methodName = NameResolver.resolveFieldName(operation.operationId);
    final jsonSchema = operation.successResponse!.jsonSchema!;
    final dartType = _schemaToDartType(jsonSchema);

    // Doc comment
    final docText = operation.summary ?? operation.description;
    if (docText != null && docText.isNotEmpty) {
      for (final line in docText.split('\n')) {
        buf.writeln('  /// ${line.trimRight()}');
      }
    }

    // Deprecated annotation
    if (operation.deprecated) {
      buf.writeln("  @Deprecated('Deprecated in API spec')");
    }

    // Method signature
    final params = _buildMethodParams(operation);
    final paramNames = _buildParamForwardingNames(operation);

    buf.write('  Future<$dartType> $methodName(');
    if (params.isNotEmpty) {
      buf.writeln('{');
      for (final p in params) {
        buf.writeln('    $p,');
      }
      buf.write('  }');
    }
    buf.writeln(') async {');

    // Forward to client
    buf.write('    final response = await _client.$methodName(');
    if (paramNames.isNotEmpty) {
      buf.writeln();
      for (final p in paramNames) {
        buf.writeln('      $p,');
      }
      buf.write('    ');
    }
    buf.writeln(');');
    buf.writeln('    return response.data;');
    buf.writeln('  }');
  }

  List<String> _buildMethodParams(ApiOperation operation) {
    final params = <String>[];

    for (final param in operation.parameters) {
      final dartType = _paramDartType(param);
      final fieldName = NameResolver.resolveFieldName(param.name);
      final requiredStr = param.required_ ? 'required ' : '';
      final deprecatedStr =
          param.deprecated ? "@Deprecated('Deprecated in API spec') " : '';
      params.add('$deprecatedStr$requiredStr$dartType $fieldName');
    }

    if (operation.requestBody != null) {
      final body = operation.requestBody!;
      final bodySchema = body.jsonSchema;
      if (bodySchema != null) {
        final dartType = _schemaToDartType(bodySchema);
        final requiredStr = body.required_ ? 'required ' : '';
        final nullSuffix = body.required_ ? '' : '?';
        params.add('$requiredStr$dartType$nullSuffix body');
      } else {
        final requiredStr = body.required_ ? 'required ' : '';
        final nullSuffix = body.required_ ? '' : '?';
        params.add('${requiredStr}String$nullSuffix body');
      }
    }

    return params;
  }

  List<String> _buildParamForwardingNames(ApiOperation operation) {
    final names = <String>[];

    for (final param in operation.parameters) {
      final fieldName = NameResolver.resolveFieldName(param.name);
      names.add('$fieldName: $fieldName');
    }

    if (operation.requestBody != null) {
      names.add('body: body');
    }

    return names;
  }

  String _paramDartType(ApiParameter param) {
    final dartType = _schemaToDartType(param.schema);
    return param.required_ ? dartType : '$dartType?';
  }

  String _schemaToDartType(ApiSchema schema) {
    if (schema.isCircularRef && schema.refTarget != null) {
      return nameResolver.resolveClassName(schema.refTarget!);
    }
    if (schema.name != null && !schema.isPrimitive && !schema.isArray) {
      return nameResolver.resolveClassName(schema.name!);
    }
    if (schema.isFreeFormObject) {
      return 'Map<String, dynamic>';
    }
    if (schema.isEnum && schema.name != null) {
      return nameResolver.resolveClassName(schema.name!);
    }
    if (schema.type == SchemaType.string && schema.format == 'date-time') {
      return 'DateTime';
    }
    return switch (schema.type) {
      SchemaType.string => 'String',
      SchemaType.integer => 'int',
      SchemaType.number => 'double',
      SchemaType.boolean => 'bool',
      SchemaType.array => schema.items != null
          ? 'List<${_schemaToDartType(schema.items!)}>'
          : 'List<dynamic>',
      SchemaType.object => schema.name != null
          ? nameResolver.resolveClassName(schema.name!)
          : 'Map<String, dynamic>',
      _ => 'dynamic',
    };
  }

  String _deriveClientName(String apiTitle) {
    final camel = _upperCamelCase(apiTitle);
    if (camel.endsWith('Client')) return camel;
    if (camel.endsWith('Api') || camel.endsWith('API')) return '${camel}Client';
    return '${camel}Client';
  }

  static String _upperCamelCase(String input) {
    final normalized = input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ');
    final withBoundaries = normalized.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    final words =
        withBoundaries.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join();
  }
}

class _OperationWithPath {
  const _OperationWithPath(this.pathTemplate, this.operation);
  final String pathTemplate;
  final ApiOperation operation;
}
