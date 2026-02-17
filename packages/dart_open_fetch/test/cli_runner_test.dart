import 'dart:io';

import 'package:dart_open_fetch/src/cli_runner.dart';
import 'package:test/test.dart';

/// Resolve the path to the Petstore fixture in the core package.
String _fixturePath() {
  // Walk up from test working directory to find packages/
  var dir = Directory.current;
  while (!Directory('${dir.path}/packages/dart_open_fetch_core').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'Cannot find packages/ directory from ${Directory.current.path}');
    }
    dir = parent;
  }
  return '${dir.path}/packages/dart_open_fetch_core/test/fixtures/petstore.yaml';
}

/// Resolve the path to the runtime package.
String _runtimePath() {
  var dir = Directory.current;
  while (
      !Directory('${dir.path}/packages/dart_open_fetch_runtime').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Cannot find packages/ directory');
    }
    dir = parent;
  }
  return '${dir.path}/packages/dart_open_fetch_runtime';
}

void main() {
  group('CLI runner', () {
    test('shows help with --help flag', () async {
      final code = await runCli(['--help']);
      expect(code, 0);
    });

    test('shows help with -h flag', () async {
      final code = await runCli(['-h']);
      expect(code, 0);
    });

    test('returns 1 with no arguments', () async {
      final code = await runCli([]);
      expect(code, 1);
    });

    test('returns 1 for missing schema argument', () async {
      final code = await runCli(['generate']);
      expect(code, 1);
    });

    test('returns 1 for non-existent file', () async {
      final code = await runCli(['generate', '/tmp/nonexistent_schema.yaml']);
      expect(code, 1);
    });

    test('generate --help shows generate usage', () async {
      final code = await runCli(['generate', '--help']);
      expect(code, 0);
    });
  });

  group('CLI end-to-end', () {
    late Directory tempDir;
    late String fixturePath;

    setUpAll(() {
      fixturePath = _fixturePath();
    });

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dart_open_fetch_cli_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('generates code from Petstore fixture', () async {
      final outputDir = '${tempDir.path}/output';

      final code = await runCli([
        'generate',
        fixturePath,
        '-o',
        outputDir,
      ]);

      expect(code, 0);

      // Verify output files exist
      final outDir = Directory(outputDir);
      expect(outDir.existsSync(), isTrue);

      final files = outDir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceFirst(outputDir, ''))
          .toList()
        ..sort();

      // Should have models.dart, barrel, and client files
      expect(files, contains('/models.dart'));
      expect(files.any((f) => f.endsWith('.dart') && f.contains('/clients/')),
          isTrue);
    });

    test('generates code with --base-url override', () async {
      final outputDir = '${tempDir.path}/output';

      final code = await runCli([
        'generate',
        fixturePath,
        '-o',
        outputDir,
        '--base-url',
        'https://custom.api.com/v2',
      ]);

      expect(code, 0);

      // Verify a client file contains the custom base URL
      final clientsDir = Directory('$outputDir/clients');
      expect(clientsDir.existsSync(), isTrue);

      final clientFiles = clientsDir.listSync().whereType<File>().toList();
      expect(clientFiles, isNotEmpty);

      final clientSource = clientFiles.first.readAsStringSync();
      expect(clientSource, contains('https://custom.api.com/v2'));
    });

    test('generated code passes dart analyze', () async {
      final outputDir = '${tempDir.path}/gen_project/lib/api';
      final runtimePath = _runtimePath();

      // Generate code
      final code = await runCli([
        'generate',
        fixturePath,
        '-o',
        outputDir,
      ]);
      expect(code, 0);

      // Create a minimal pubspec for analysis
      final pubspec = File('${tempDir.path}/gen_project/pubspec.yaml');
      pubspec.parent.createSync(recursive: true);
      pubspec.writeAsStringSync('''
name: gen_test
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  dart_open_fetch_runtime:
    path: $runtimePath
''');

      // Run dart pub get
      final pubGet = await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: '${tempDir.path}/gen_project',
      );
      expect(pubGet.exitCode, 0, reason: 'pub get failed: ${pubGet.stderr}');

      // Run dart analyze
      final analyze = await Process.run(
        'dart',
        ['analyze'],
        workingDirectory: '${tempDir.path}/gen_project',
      );
      // Allow infos/warnings, but not errors
      final output = '${analyze.stdout}\n${analyze.stderr}';
      expect(output, isNot(contains('error -')),
          reason: 'dart analyze found errors:\n$output');
    });
  });
}
