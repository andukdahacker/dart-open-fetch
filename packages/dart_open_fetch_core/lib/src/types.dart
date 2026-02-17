import 'diagnostic.dart';
import 'ir/api_spec.dart';

/// Callback to read a file relative to the schema base path.
/// The CLI provides the implementation; core stays free of dart:io.
typedef FileReader = Future<Map<String, dynamic>> Function(String relativePath);

/// Result of parsing an OpenAPI schema.
class ParseResult {
  const ParseResult({
    required this.spec,
    this.diagnostics = const [],
  });

  /// The parsed IR.
  final ApiSpec spec;

  /// Non-fatal diagnostics collected during parsing.
  final List<Diagnostic> diagnostics;
}

/// Result of code generation.
class GenerateResult {
  const GenerateResult({
    this.filesWritten = const [],
    this.diagnostics = const [],
  });

  /// Paths of files written.
  final List<String> filesWritten;

  /// Non-fatal diagnostics collected during generation.
  final List<Diagnostic> diagnostics;
}
