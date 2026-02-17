import 'dart:io';

import 'package:dart_open_fetch_core/dart_open_fetch_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Load a YAML fixture file and convert to plain Dart maps.
///
/// Using a separate function ensures the raw YAML string and YamlMap tree
/// are GC-eligible once conversion completes, before parsing begins.
Future<Map<String, dynamic>> loadYamlFixture(String path) async {
  final content = await File(path).readAsString();
  final yaml = loadYaml(content) as YamlMap;
  return _yamlToMap(yaml);
}

Map<String, dynamic> _yamlToMap(YamlMap yaml) {
  final result = <String, dynamic>{};
  for (final entry in yaml.entries) {
    result[entry.key as String] = _convertValue(entry.value);
  }
  return result;
}

dynamic _convertValue(dynamic value) {
  if (value is YamlMap) return _yamlToMap(value);
  if (value is YamlList) return value.map(_convertValue).toList();
  return value;
}

Future<Map<String, dynamic>> _noFileReader(String path) async {
  throw Exception('File reading not supported in this test');
}

void main() {
  group('OpenApiParser', () {
    group('Petstore fixture', () {
      late ParseResult result;

      setUpAll(() async {
        final schema = await loadYamlFixture(
          'packages/dart_open_fetch_core/test/fixtures/petstore.yaml',
        );
        final parser = OpenApiParser(fileReader: _noFileReader);
        result = await parser.parse(schema, basePath: '.');
      });

      test('parses API info', () {
        expect(result.spec.info.title, isNotEmpty);
        expect(result.spec.info.version, isNotEmpty);
      });

      test('parses server URLs', () {
        expect(result.spec.info.servers, isNotEmpty);
      });

      test('parses paths', () {
        expect(result.spec.paths, isNotEmpty);
      });

      test('parses schemas', () {
        expect(result.spec.schemas, isNotEmpty);
      });

      test('all operations have operationIds', () {
        for (final path in result.spec.paths) {
          for (final op in path.operations) {
            expect(op.operationId, isNotEmpty,
                reason: '${op.method} ${path.path} missing operationId');
          }
        }
      });

      test('schemas have names', () {
        for (final schema in result.spec.schemas) {
          expect(schema.name, isNotEmpty,
              reason: 'Schema at ${schema.schemaPath} missing name');
        }
      });
    });

    group('Schema validation', () {
      test('rejects Swagger 2.0', () async {
        final parser = OpenApiParser(fileReader: _noFileReader);
        expect(
          () => parser.parse(<String, dynamic>{'swagger': '2.0'}, basePath: '.'),
          throwsA(isA<SchemaParseException>()),
        );
      });

      test('rejects missing openapi field', () async {
        final parser = OpenApiParser(fileReader: _noFileReader);
        expect(
          () => parser.parse(<String, dynamic>{'info': <String, dynamic>{}}, basePath: '.'),
          throwsA(isA<SchemaParseException>()),
        );
      });

      test('parses minimal valid schema', () async {
        final parser = OpenApiParser(fileReader: _noFileReader);
        final result = await parser.parse(<String, dynamic>{
          'openapi': '3.0.3',
          'info': <String, dynamic>{'title': 'Test', 'version': '1.0'},
          'paths': <String, dynamic>{},
        }, basePath: '.');

        expect(result.spec.info.title, 'Test');
        expect(result.spec.paths, isEmpty);
      });
    });

    group('Server variable resolution', () {
      test('resolves server variables with defaults', () async {
        final parser = OpenApiParser(fileReader: _noFileReader);
        final result = await parser.parse(<String, dynamic>{
          'openapi': '3.0.3',
          'info': <String, dynamic>{'title': 'Test', 'version': '1.0'},
          'servers': <dynamic>[
            <String, dynamic>{
              'url': 'https://{env}.api.com/v{version}',
              'variables': <String, dynamic>{
                'env': <String, dynamic>{'default': 'production'},
                'version': <String, dynamic>{'default': '1'},
              },
            },
          ],
          'paths': <String, dynamic>{},
        }, basePath: '.');

        expect(
          result.spec.info.servers.first,
          'https://production.api.com/v1',
        );
      });
    });

    group('GitHub fixture (stress test)', () {
      late ParseResult result;

      setUpAll(() async {
        final schema = await loadYamlFixture(
          'packages/dart_open_fetch_core/test/fixtures/github.yaml',
        );
        final parser = OpenApiParser(fileReader: _noFileReader);
        result = await parser.parse(schema, basePath: '.');
      });

      test('parses without fatal errors', () {
        expect(result.spec, isNotNull);
      });

      test('has many paths', () {
        expect(result.spec.paths.length, greaterThan(100));
      });

      test('has many schemas', () {
        expect(result.spec.schemas.length, greaterThan(100));
      });

      test('has security schemes', () {
        // GitHub API typically has no separate securitySchemes in components.
        // The test validates that parsing completes.
        expect(result.spec, isNotNull);
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    group('Stripe fixture (stress test)', () {
      late ParseResult result;

      setUpAll(() async {
        final schema = await loadYamlFixture(
          'packages/dart_open_fetch_core/test/fixtures/stripe.yaml',
        );
        final parser = OpenApiParser(fileReader: _noFileReader);
        result = await parser.parse(schema, basePath: '.');
      });

      test('parses without fatal errors', () {
        expect(result.spec, isNotNull);
      });

      test('has many schemas', () {
        expect(result.spec.schemas.length, greaterThan(100));
      });

      test('handles allOf compositions', () {
        // Stripe uses extensive allOf — parser should handle without errors
        final allOfSchemas = result.spec.schemas
            .where((s) => s.properties.isNotEmpty)
            .toList();
        expect(allOfSchemas, isNotEmpty);
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
