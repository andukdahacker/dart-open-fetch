import 'dart:io';

import 'package:dart_open_fetch/src/schema_fetcher.dart';
import 'package:test/test.dart';

/// Resolve the path to the Petstore fixture in the core package.
String _fixturePath() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/packages/dart_open_fetch_core').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Cannot find packages/ directory');
    }
    dir = parent;
  }
  return '${dir.path}/packages/dart_open_fetch_core/test/fixtures/petstore.yaml';
}

void main() {
  group('SchemaFetcher', () {
    final fetcher = SchemaFetcher();

    test('loads YAML file', () async {
      final result = await fetcher.fetch(_fixturePath());

      expect(result.schema, isA<Map<String, dynamic>>());
      expect(result.schema['openapi'], startsWith('3.'));
      expect(result.schema['info'], isA<Map>());
      expect(result.basePath, isNotEmpty);
    });

    test('loads JSON file', () async {
      final tempDir = Directory.systemTemp.createTempSync('fetcher_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final jsonFile = File('${tempDir.path}/test.json');
      jsonFile.writeAsStringSync(
          '{"openapi": "3.0.0", "info": {"title": "Test", "version": "1.0"}, "paths": {}}');

      final result = await fetcher.fetch(jsonFile.path);
      expect(result.schema['openapi'], '3.0.0');
      expect(result.schema['info']['title'], 'Test');
    });

    test('throws for non-existent file', () async {
      expect(
        () => fetcher.fetch('/tmp/nonexistent_file_xyz.yaml'),
        throwsA(isA<SchemaFetchException>().having(
          (e) => e.message,
          'message',
          contains('File not found'),
        )),
      );
    });

    test('deep-converts YAML types to plain Dart types', () async {
      final tempDir = Directory.systemTemp.createTempSync('fetcher_yaml_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final yamlFile = File('${tempDir.path}/test.yaml');
      yamlFile.writeAsStringSync('''
openapi: "3.0.0"
info:
  title: Test
  version: "1.0"
paths: {}
components:
  schemas:
    Pet:
      type: object
      properties:
        name:
          type: string
        tags:
          type: array
          items:
            type: string
''');

      final result = await fetcher.fetch(yamlFile.path);

      // Verify the result is plain Dart Map, not YamlMap
      expect(result.schema, isA<Map<String, dynamic>>());
      final components = result.schema['components'] as Map<String, dynamic>;
      final schemas = components['schemas'] as Map<String, dynamic>;
      final pet = schemas['Pet'] as Map<String, dynamic>;
      final properties = pet['properties'] as Map<String, dynamic>;
      expect(properties, isA<Map<String, dynamic>>());
      expect(properties['name'], isA<Map<String, dynamic>>());
    });

    group('fileReader', () {
      test('reads relative files', () async {
        final tempDir = Directory.systemTemp.createTempSync('fetcher_ref_');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final refFile = File('${tempDir.path}/ref.yaml');
        refFile.writeAsStringSync('''
type: object
properties:
  id:
    type: integer
''');

        final reader = fetcher.fileReader(tempDir.path);
        final result = await reader('ref.yaml');
        expect(result, isA<Map<String, dynamic>>());
        expect(result['type'], 'object');
      });

      test('throws for non-existent reference', () async {
        final reader = fetcher.fileReader('/tmp');
        expect(
          () => reader('nonexistent.yaml'),
          throwsA(isA<SchemaFetchException>()),
        );
      });
    });
  });
}
