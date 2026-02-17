import '../diagnostic.dart';
import '../types.dart';

/// Marker key indicating a circular `$ref` was detected.
const String circularRefMarker = '_circular_ref';

/// Marker key holding the original `$ref` target for circular references.
const String refTargetMarker = '_ref_target';

/// Resolves `$ref` pointers in OpenAPI schemas.
///
/// Handles local (`#/components/schemas/Pet`) and relative file refs.
/// Remote URL refs are skipped with a diagnostic.
class RefResolver {
  /// Creates a resolver for `$ref` pointers.
  ///
  /// [rootSchema] **must** contain mutable `Map<String, dynamic>` and
  /// `List<dynamic>` instances because `resolveAll` resolves non-schema
  /// `$ref`s by replacing map values in place. Callers that load from YAML
  /// or JSON must convert to mutable maps before passing them here.
  RefResolver({
    required this.rootSchema,
    required this.basePath,
    required this.fileReader,
  });

  final Map<String, dynamic> rootSchema;
  final String basePath;
  final FileReader fileReader;

  final List<Diagnostic> diagnostics = [];
  final Map<String, Map<String, dynamic>> _fileCache = {};
  final Set<String> _resolving = {};
  final Map<String, Map<String, dynamic>> _resolvedCache = {};

  /// Deep-convert all nested maps/lists to mutable `Map<String, dynamic>` / `List<dynamic>`.
  static Map<String, dynamic> _deepConvert(Map<String, dynamic> source) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      result[entry.key] = _deepConvertValue(entry.value);
    }
    return result;
  }

  static dynamic _deepConvertValue(dynamic value) {
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        result[entry.key.toString()] = _deepConvertValue(entry.value);
      }
      return result;
    } else if (value is List) {
      return value.map(_deepConvertValue).toList();
    }
    return value;
  }

  /// Resolve non-schema `$ref`s in the schema tree in place, returning the root.
  ///
  /// Component schema `$ref`s (`#/components/schemas/X`) are left as-is —
  /// they are resolved at IR level by [SchemaParser] using a pointer-sharing
  /// registry, which avoids the deep-copy memory explosion on large specs.
  Future<Map<String, dynamic>> resolveAll() async {
    // Main tree walk — resolves non-schema $refs in paths, parameters, etc.
    // Component schema $refs are skipped (handled by SchemaParser).
    await _resolveNode(rootSchema, '#', skipComponentSchemas: true);
    return rootSchema;
  }

  Future<void> _resolveNode(
    Object? node,
    String path, {
    bool skipComponentSchemas = false,
  }) async {
    if (node is Map<String, dynamic>) {
      if (node.containsKey(r'$ref')) {
        return; // Handled by parent when it encounters $ref child
      }

      final keys = node.keys.toList();
      for (final key in keys) {
        // Skip component schema definitions so they stay pristine for
        // lookups in _resolveRef. They get resolved on-demand via $ref.
        if (skipComponentSchemas &&
            path == '#/components' &&
            key == 'schemas') {
          continue;
        }

        final value = node[key];
        final childPath = '$path/$key';

        if (value is Map<String, dynamic> && value.containsKey(r'$ref')) {
          final ref = value[r'$ref'] as String;
          final resolved = await _resolveRef(ref, childPath);
          if (resolved != null) {
            node[key] = resolved;
          }
        } else {
          await _resolveNode(value, childPath,
              skipComponentSchemas: skipComponentSchemas);
        }
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        final value = node[i];
        final childPath = '$path/$i';

        if (value is Map<String, dynamic> && value.containsKey(r'$ref')) {
          final ref = value[r'$ref'] as String;
          final resolved = await _resolveRef(ref, childPath);
          if (resolved != null) {
            node[i] = resolved;
          }
        } else {
          await _resolveNode(value, childPath,
              skipComponentSchemas: skipComponentSchemas);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _resolveRef(String ref, String path) async {
    // Remote URL refs
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      diagnostics.add(Diagnostic(
        message: 'Remote URL \$ref not supported in v0.1, skipping: $ref',
        schemaPath: path,
        severity: DiagnosticSeverity.warning,
      ));
      return null;
    }

    // Component schema refs are resolved at IR level by SchemaParser.
    // Leave them as-is in the map tree to avoid expensive deep-copy.
    if (ref.startsWith('#/components/schemas/')) {
      return null;
    }

    // Return cached result — same shared instance for all reference sites
    if (_resolvedCache.containsKey(ref)) {
      return _resolvedCache[ref]!;
    }

    // Circular detection — return a lightweight marker instead of
    // deep-copying the target (which is very expensive for large schemas).
    // SchemaParser handles these markers as stub ApiSchema nodes.
    if (_resolving.contains(ref)) {
      return {circularRefMarker: true, refTargetMarker: ref};
    }

    _resolving.add(ref);
    try {
      final target = await _lookupTarget(ref, path);

      if (target == null) {
        diagnostics.add(Diagnostic(
          message: '\$ref target not found: $ref',
          schemaPath: path,
          severity: DiagnosticSeverity.warning,
        ));
        return null;
      }

      // If the target is itself a $ref, follow the chain.
      if (target.containsKey(r'$ref')) {
        final innerRef = target[r'$ref'] as String;
        final resolved = await _resolveRef(innerRef, path);
        if (resolved != null) {
          _resolvedCache[ref] = resolved;
        }
        return resolved;
      }

      // Deep-copy once so we don't mutate rootSchema (needed for correct
      // circular ref markers and pristine lookups). Resolve nested $refs
      // in the copy, cache it, and return the same instance to all sites.
      final copy = _deepConvert(target);
      await _resolveNode(copy, path);
      _resolvedCache[ref] = copy;
      return copy;
    } finally {
      _resolving.remove(ref);
    }
  }

  /// Look up the target map for a $ref without resolving it.
  Future<Map<String, dynamic>?> _lookupTarget(String ref, String path) async {
    if (ref.startsWith('#/')) {
      return _resolvePointer(rootSchema, ref, ref);
    } else if (ref.contains('#/')) {
      final parts = ref.split('#');
      final filePath = parts[0];
      final pointer = '#${parts[1]}';
      final fileSchema = await _loadFile(filePath);
      if (fileSchema != null) {
        return _resolvePointer(fileSchema, pointer, path);
      }
      return null;
    } else {
      return await _loadFile(ref);
    }
  }

  Map<String, dynamic>? _resolvePointer(
    Map<String, dynamic> doc,
    String pointer,
    String errorPath,
  ) {
    final segments = pointer
        .replaceFirst('#/', '')
        .split('/')
        .map((s) => s.replaceAll('~1', '/').replaceAll('~0', '~'))
        .toList();

    dynamic current = doc;
    for (final segment in segments) {
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(segment)) return null;
        current = current[segment];
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }

    if (current is Map<String, dynamic>) return current;
    return null;
  }

  Future<Map<String, dynamic>?> _loadFile(String relativePath) async {
    if (_fileCache.containsKey(relativePath)) {
      return _fileCache[relativePath];
    }

    try {
      final content = await fileReader(relativePath);
      _fileCache[relativePath] = content;
      return content;
    } catch (e) {
      diagnostics.add(Diagnostic(
        message: 'Failed to load file ref "$relativePath": $e',
        schemaPath: relativePath,
        severity: DiagnosticSeverity.warning,
      ));
      return null;
    }
  }
}
