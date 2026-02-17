/// Non-fatal diagnostic — collected, NOT thrown.
class Diagnostic {
  const Diagnostic({
    required this.message,
    this.schemaPath,
    required this.severity,
  });

  /// Human-readable diagnostic message.
  final String message;

  /// JSON pointer to the location in the schema.
  final String? schemaPath;

  /// Severity level.
  final DiagnosticSeverity severity;

  @override
  String toString() {
    final location = schemaPath != null ? ' at $schemaPath' : '';
    return '${severity.name}: $message$location';
  }
}

/// Diagnostic severity levels.
enum DiagnosticSeverity {
  warning,
  info,
}
