import '../diagnostic.dart';
import '../ir/api_spec.dart';
import '../types.dart';
import 'info_parser.dart';
import 'path_parser.dart';
import 'ref_resolver.dart';
import 'schema_parser.dart';
import 'schema_reader.dart';
import 'security_parser.dart';
import 'version_detector.dart';

/// Top-level parser orchestrator: raw schema map → [ApiSpec] IR.
class OpenApiParser {
  OpenApiParser({required this.fileReader});

  final FileReader fileReader;

  /// Parse an OpenAPI schema into IR.
  ///
  /// [rawSchema] is a pre-parsed `Map<String, dynamic>` (from JSON/YAML).
  /// [basePath] is the directory containing the root schema file.
  Future<ParseResult> parse(
    Map<String, dynamic> rawSchema, {
    required String basePath,
  }) async {
    final allDiagnostics = <Diagnostic>[];

    // 1. Validate
    final reader = SchemaReader();
    reader.validate(rawSchema);

    // 2. Detect version
    final detector = VersionDetector();
    final version = detector.detect(rawSchema);

    // 3. Normalize (mutates in place for 3.1)
    detector.normalize(rawSchema, version);

    // 4. Resolve $refs (deep-converts maps internally)
    final resolver = RefResolver(
      rootSchema: rawSchema,
      basePath: basePath,
      fileReader: fileReader,
    );
    // Use the resolver's deep-converted schema for all subsequent parsing
    final schema = await resolver.resolveAll();
    allDiagnostics.addAll(resolver.diagnostics);

    // 5. Parse schemas
    final schemaParser = SchemaParser();
    final schemas = schemaParser.parseComponents(schema);
    allDiagnostics.addAll(schemaParser.diagnostics);

    // 6. Parse paths
    final pathParser = PathParser(schemaParser: schemaParser);
    final paths = pathParser.parsePaths(schema);
    allDiagnostics.addAll(pathParser.diagnostics);

    // 7. Parse info + servers
    final infoParser = InfoParser();
    final info = infoParser.parse(schema);

    // 8. Parse security schemes
    final securityParser = SecurityParser();
    final securitySchemes = securityParser.parse(schema);

    // 9. Assemble
    return ParseResult(
      spec: ApiSpec(
        info: info,
        paths: paths,
        schemas: schemas,
        securitySchemes: securitySchemes,
      ),
      diagnostics: allDiagnostics,
    );
  }
}
