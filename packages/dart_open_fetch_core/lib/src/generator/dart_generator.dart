import '../diagnostic.dart';
import '../ir/api_info.dart';
import '../ir/api_schema.dart';
import '../ir/api_spec.dart';
import '../types.dart';
import 'client_generator.dart';
import 'enum_deduplicator.dart';
import 'inline_schema_resolver.dart';
import 'model_generator.dart';
import 'name_resolver.dart';
import 'output_writer.dart';
import 'parameter_serializer.dart';
import 'union_generator.dart';

/// Top-level orchestrator: ApiSpec IR → generated Dart files.
///
/// Entry point: `generate(spec, outputDir)` produces models, unions,
/// clients, and a barrel export file.
class DartGenerator {
  DartGenerator({
    this.schemaSource,
    this.toolVersion = '0.2.0',
    this.packageName,
    this.stripAdditionalProperties = false,
    this.skipUnusedSchemas = false,
    this.deduplicateEnums = false,
    this.clientNameOverride,
  });

  final String? schemaSource;
  final String toolVersion;

  /// Dart package name for generating `package:` imports.
  /// When set and output is inside `lib/`, client files use
  /// `package:` imports instead of relative imports.
  final String? packageName;

  /// When true, strip `hasAdditionalProperties` from all schemas.
  final bool stripAdditionalProperties;

  /// When true, only generate schemas referenced by operations.
  final bool skipUnusedSchemas;

  /// When true, deduplicate enum schemas with identical value sets.
  final bool deduplicateEnums;

  /// Override client class name (skip tag grouping, single client).
  final String? clientNameOverride;

  /// Generate Dart code from a parsed OpenAPI spec.
  ///
  /// [spec] — the parsed IR.
  /// [outputDir] — directory to write generated files.
  /// [baseUrlOverride] — optional override for the default base URL.
  ///
  /// Returns paths of files written and diagnostics.
  Future<GenerateResult> generate(
    ApiSpec spec,
    String outputDir, {
    String? baseUrlOverride,
  }) async {
    final nameResolver = NameResolver();
    final diagnostics = <Diagnostic>[];

    // Reserve runtime type names to avoid collisions with generated models
    nameResolver.reserveNames(const [
      'ApiResponse',
      'ApiException',
      'HttpAdapter',
      'HttpRequest',
      'HttpResponse',
      'Middleware',
      'MiddlewareChain',
    ]);

    // Apply base URL override if provided
    final effectiveSpec = baseUrlOverride != null
        ? _withBaseUrlOverride(spec, baseUrlOverride)
        : spec;

    final modelGen = ModelGenerator(nameResolver: nameResolver);
    final unionGen = UnionGenerator(nameResolver: nameResolver);
    final paramSerializer = ParameterSerializer(nameResolver: nameResolver);
    final clientGen = ClientGenerator(
      nameResolver: nameResolver,
      parameterSerializer: paramSerializer,
      clientNameOverride: clientNameOverride,
    );

    final writer = OutputWriter(
      outputDir: outputDir,
      nameResolver: nameResolver,
      schemaSource: schemaSource,
      toolVersion: toolVersion,
      packageName: packageName,
    );

    final clientFileNames = <String>[];

    // 0. Resolve unnamed inline schemas (objects & enums) before generation
    final inlineResolver = InlineSchemaResolver();
    final resolvedSchemas = inlineResolver.resolve(effectiveSpec.schemas);
    var allSchemas = [...resolvedSchemas, ...inlineResolver.generatedSchemas];

    // 0a. Strip additionalProperties if requested
    if (stripAdditionalProperties) {
      allSchemas = allSchemas
          .map((s) => s.hasAdditionalProperties
              ? s.copyWith(hasAdditionalProperties: false)
              : s)
          .toList();
    }

    // 0b. Deduplicate enums if requested
    if (deduplicateEnums) {
      final deduplicator = EnumDeduplicator();
      allSchemas = deduplicator.deduplicate(allSchemas);
    }

    // 0c. Skip unused schemas if requested
    if (skipUnusedSchemas) {
      final usedNames = _collectUsedSchemaNames(effectiveSpec, allSchemas);
      allSchemas = allSchemas
          .where((s) => s.name == null || usedNames.contains(s.name))
          .toList();
    }

    // 1. Generate all models into a single models.dart file
    final modelSources = <String>[];
    for (final schema in allSchemas) {
      if (schema.name == null) continue;
      if (schema.isCircularRef) continue;

      try {
        if (schema.isComposed) {
          modelSources.add(unionGen.generateUnion(schema));
        } else if (schema.isEnum) {
          modelSources.add(modelGen.generateEnum(schema));
        } else if (schema.isObject || schema.properties.isNotEmpty) {
          modelSources.add(modelGen.generateModel(schema));
        }
      } catch (e) {
        diagnostics.add(Diagnostic(
          message: 'Failed to generate code for schema "${schema.name}": $e',
          schemaPath: schema.schemaPath,
          severity: DiagnosticSeverity.warning,
        ));
      }
    }

    String? modelsFileName;
    if (modelSources.isNotEmpty) {
      final combined = '$_equalityHelpers\n\n${modelSources.join('\n\n')}';
      final path = await writer.writeModels(combined);
      modelsFileName = _fileName(path);
    }

    // 2. Generate client classes
    final clients = clientGen.generateClients(effectiveSpec);
    for (final client in clients) {
      final headerSource = writer.addHeader(client.source);
      final path = await writer.writeClient(
        client.className,
        headerSource,
        modelsFileName: modelsFileName,
      );
      clientFileNames.add(_fileName(path));
    }

    // 3. Generate barrel export
    final barrelPackageName = _derivePackageName(effectiveSpec.info.title);
    await writer.writeBarrel(
        barrelPackageName, modelsFileName, clientFileNames);

    // Collect all diagnostics
    diagnostics.addAll(nameResolver.diagnostics);
    diagnostics.addAll(modelGen.diagnostics);
    diagnostics.addAll(unionGen.diagnostics);
    diagnostics.addAll(paramSerializer.diagnostics);
    diagnostics.addAll(clientGen.diagnostics);

    return GenerateResult(
      filesWritten: writer.writtenFiles,
      diagnostics: diagnostics,
    );
  }

  /// Recursively collect all schema names referenced from operations.
  Set<String> _collectUsedSchemaNames(
      ApiSpec spec, List<ApiSchema> allSchemas) {
    final used = <String>{};
    final schemaMap = <String, ApiSchema>{};
    for (final s in allSchemas) {
      if (s.name != null) schemaMap[s.name!] = s;
    }

    void walkSchema(ApiSchema schema) {
      if (schema.isCircularRef && schema.refTarget != null) {
        if (used.add(schema.refTarget!) &&
            schemaMap.containsKey(schema.refTarget!)) {
          walkSchema(schemaMap[schema.refTarget!]!);
        }
        return;
      }
      if (schema.name != null) {
        if (!used.add(schema.name!)) return; // already visited
      }
      for (final prop in schema.properties) {
        walkSchema(prop.schema);
      }
      if (schema.items != null) walkSchema(schema.items!);
      if (schema.additionalProperties != null) {
        walkSchema(schema.additionalProperties!);
      }
      for (final s in schema.oneOf) {
        walkSchema(s);
      }
      for (final s in schema.anyOf) {
        walkSchema(s);
      }
      for (final s in schema.allOf) {
        walkSchema(s);
      }
    }

    for (final path in spec.paths) {
      for (final op in path.operations) {
        if (op.requestBody?.jsonSchema != null) {
          walkSchema(op.requestBody!.jsonSchema!);
        }
        for (final resp in op.responses) {
          final jsonSchema = resp.jsonSchema;
          if (jsonSchema != null) walkSchema(jsonSchema);
        }
        for (final param in op.parameters) {
          walkSchema(param.schema);
        }
      }
    }

    return used;
  }

  ApiSpec _withBaseUrlOverride(ApiSpec spec, String baseUrl) {
    return ApiSpec(
      info: ApiInfo(
        title: spec.info.title,
        version: spec.info.version,
        description: spec.info.description,
        servers: [baseUrl, ...spec.info.servers.skip(1)],
      ),
      paths: spec.paths,
      schemas: spec.schemas,
      securitySchemes: spec.securitySchemes,
    );
  }

  String _derivePackageName(String apiTitle) {
    return apiTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _fileName(String path) {
    return path.split('/').last;
  }

  static const _equalityHelpers = r'''
bool _deepEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(dynamic value) {
  if (value is List) return Object.hashAll(value.map(_deepHash));
  if (value is Map) {
    return Object.hashAll(
      value.entries.map((e) => Object.hash(e.key, _deepHash(e.value))),
    );
  }
  return value.hashCode;
}
''';
}
