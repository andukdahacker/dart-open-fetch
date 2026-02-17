import '../diagnostic.dart';

/// Resolves schema names to valid, unique Dart identifiers.
class NameResolver {
  final List<Diagnostic> diagnostics = [];
  final Map<String, String> _classNames = {};
  final Set<String> _usedClassNames = {};
  final Set<String> _usedFileNames = {};

  /// Dart reserved words that need `$` suffix.
  static const _reservedWords = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part',
    'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
    'var', 'void', 'when', 'while', 'with', 'yield',
  };

  /// Resolve a schema name to a unique Dart class name.
  String resolveClassName(String schemaName) {
    if (_classNames.containsKey(schemaName)) {
      return _classNames[schemaName]!;
    }

    var dartName = _upperCamelCase(schemaName);
    if (_reservedWords.contains(dartName.toLowerCase())) {
      dartName = '$dartName\$';
      diagnostics.add(Diagnostic(
        message: 'Schema "$schemaName" collides with Dart reserved word, '
            'renamed to "$dartName"',
        severity: DiagnosticSeverity.warning,
      ));
    }

    if (_usedClassNames.contains(dartName)) {
      var suffix = 2;
      while (_usedClassNames.contains('$dartName$suffix')) {
        suffix++;
      }
      final original = dartName;
      dartName = '$dartName$suffix';
      diagnostics.add(Diagnostic(
        message: 'Duplicate class name "$original" from schema "$schemaName", '
            'renamed to "$dartName"',
        severity: DiagnosticSeverity.warning,
      ));
    }

    _usedClassNames.add(dartName);
    _classNames[schemaName] = dartName;
    return dartName;
  }

  /// Resolve a class name to a unique file name (snake_case.dart).
  String resolveFileName(String className) {
    var fileName = _toSnakeCase(className);
    if (_usedFileNames.contains(fileName)) {
      var suffix = 2;
      while (_usedFileNames.contains('${fileName}_$suffix')) {
        suffix++;
      }
      fileName = '${fileName}_$suffix';
    }
    _usedFileNames.add(fileName);
    return '$fileName.dart';
  }

  /// Resolve a property name to a valid Dart field name.
  static String resolveFieldName(String propertyName) {
    var name = _lowerCamelCase(propertyName);
    if (_reservedWords.contains(name)) {
      name = '$name\$';
    }
    return name;
  }

  /// Sanitize an enum value to a valid Dart identifier.
  static String resolveEnumValue(String value) {
    if (value.isEmpty) return 'empty';

    var name = _lowerCamelCase(value);

    // Leading digit → prefix with 'value'
    if (name.isNotEmpty && RegExp(r'^[0-9]').hasMatch(name)) {
      name = 'value${_upperFirst(name)}';
    }

    if (name.isEmpty) return 'empty';

    if (_reservedWords.contains(name)) {
      name = '$name\$';
    }
    return name;
  }

  /// Convert to UpperCamelCase.
  static String _upperCamelCase(String input) {
    return _splitWords(input).map(_upperFirst).join();
  }

  /// Convert to lowerCamelCase.
  static String _lowerCamelCase(String input) {
    final words = _splitWords(input);
    if (words.isEmpty) return '';
    return [
      words.first.toLowerCase(),
      ...words.skip(1).map(_upperFirst),
    ].join();
  }

  /// Convert to snake_case.
  static String _toSnakeCase(String input) {
    // Insert underscore before uppercase letters preceded by lowercase
    final result = input
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .toLowerCase();
    // Replace non-alphanumeric with underscore, collapse multiples
    return result
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Split input into words on boundaries (hyphens, underscores, spaces, camelCase).
  static List<String> _splitWords(String input) {
    // Replace non-alphanumeric with space, then split on camelCase boundaries
    final normalized = input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ');
    final withBoundaries = normalized.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    return withBoundaries
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static String _upperFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}
