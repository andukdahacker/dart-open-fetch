@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_open_fetch_core/dart_open_fetch_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Deep-converts YamlMap/YamlList to plain Dart Map/List.
dynamic _deepConvert(dynamic value) {
  if (value is YamlMap) {
    return value.map((k, v) => MapEntry(k.toString(), _deepConvert(v)));
  }
  if (value is YamlList) {
    return value.map(_deepConvert).toList();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), _deepConvert(v)));
  }
  return value;
}

Map<String, dynamic> _loadYaml(String path) {
  final content = File(path).readAsStringSync();
  if (content.trimLeft().startsWith('{')) {
    return json.decode(content) as Map<String, dynamic>;
  }
  return _deepConvert(loadYaml(content)) as Map<String, dynamic>;
}

void main() {
  group('Compile test', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dart_open_fetch_compile_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Petstore generated code passes dart analyze', () async {
      // Parse Petstore fixture
      final rawSchema = _loadYaml(
        'test/fixtures/petstore.yaml',
      );

      final parser = OpenApiParser(
        fileReader: (path) async => _loadYaml(path),
      );
      final parseResult = await parser.parse(rawSchema, basePath: '.');
      expect(parseResult.spec.paths, isNotEmpty,
          reason: 'Petstore should have paths');

      // Generate code
      final dartGen = DartGenerator(
        schemaSource: 'petstore.yaml',
        toolVersion: '0.1.0-test',
      );
      final outputDir = '${tempDir.path}/lib/api';
      final genResult =
          await dartGen.generate(parseResult.spec, outputDir);
      expect(genResult.filesWritten, isNotEmpty,
          reason: 'Should have written files');

      // Create a pubspec.yaml in the temp dir for dart analyze
      final pubspec = '''
name: compile_test
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  dart_open_fetch_runtime:
    path: ${Directory.current.parent.path}/dart_open_fetch_runtime
''';
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(pubspec);

      // Run dart pub get
      final pubGetResult = await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: tempDir.path,
      );
      expect(pubGetResult.exitCode, 0,
          reason: 'dart pub get should succeed:\n'
              '${pubGetResult.stderr}');

      // Run dart analyze
      final analyzeResult = await Process.run(
        'dart',
        ['analyze', outputDir],
        workingDirectory: tempDir.path,
      );

      if (analyzeResult.exitCode != 0) {
        // Print generated files for debugging
        final genFiles = Directory(outputDir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));
        for (final f in genFiles) {
          print('=== ${f.path} ===');
          print(f.readAsStringSync());
        }
      }

      expect(analyzeResult.exitCode, 0,
          reason:
              'dart analyze should pass:\n${analyzeResult.stdout}\n${analyzeResult.stderr}');
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}
