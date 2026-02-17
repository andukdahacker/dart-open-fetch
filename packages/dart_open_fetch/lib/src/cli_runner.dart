import 'package:args/args.dart';
import 'package:dart_open_fetch_core/dart_open_fetch_core.dart';

import 'progress_reporter.dart';
import 'schema_fetcher.dart';

/// Run the CLI with the given arguments. Returns an exit code.
Future<int> runCli(List<String> arguments) async {
  final parser = ArgParser()
    ..addCommand('generate')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage help.');

  final generateParser = parser.commands['generate']!
    ..addOption('output',
        abbr: 'o', defaultsTo: 'lib/api/', help: 'Output directory.')
    ..addOption('base-url', help: 'Override the server base URL.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage help.');

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    print('Error: ${e.message}');
    _printUsage(parser);
    return 1;
  }

  if (results.flag('help') || results.command == null) {
    _printUsage(parser);
    return results.flag('help') ? 0 : 1;
  }

  if (results.command!.name != 'generate') {
    print('Error: Unknown command "${results.command!.name}".');
    _printUsage(parser);
    return 1;
  }

  final generateResults = results.command!;
  if (generateResults.flag('help')) {
    print('Usage: dart_open_fetch generate <schema> [options]\n');
    print(generateParser.usage);
    return 0;
  }

  if (generateResults.rest.isEmpty) {
    print('Error: Missing required <schema> argument.');
    print('Usage: dart_open_fetch generate <schema> [options]\n');
    print(generateParser.usage);
    return 1;
  }

  final schemaPath = generateResults.rest.first;
  final outputDir = generateResults.option('output')!;
  final baseUrl = generateResults.option('base-url');

  return _runGenerate(
    schemaPath: schemaPath,
    outputDir: outputDir,
    baseUrl: baseUrl,
  );
}

Future<int> _runGenerate({
  required String schemaPath,
  required String outputDir,
  String? baseUrl,
}) async {
  final reporter = ProgressReporter();
  final fetcher = SchemaFetcher();

  // 1. Fetch & parse schema
  reporter.fetching(schemaPath);
  final SchemaFetchResult fetchResult;
  try {
    fetchResult = await fetcher.fetch(schemaPath);
  } on SchemaFetchException catch (e) {
    print('Error: $e');
    return 1;
  }

  // 2. Parse into IR
  reporter.parsing();
  final parser = OpenApiParser(
    fileReader: fetcher.fileReader(fetchResult.basePath),
  );

  final ParseResult parseResult;
  try {
    parseResult = await parser.parse(
      fetchResult.schema,
      basePath: fetchResult.basePath,
    );
  } on OpenFetchException catch (e) {
    print('Error: ${e.message}');
    return 1;
  }

  for (final d in parseResult.diagnostics) {
    reporter.warning(d.message);
  }

  // 3. Generate code
  final spec = parseResult.spec;
  final modelCount =
      spec.schemas.where((s) => s.name != null && !s.isCircularRef).length;
  final clientCount = spec.paths.length;
  reporter.generating(modelCount, clientCount);
  reporter.writing(outputDir);

  final generator = DartGenerator(
    schemaSource: schemaPath,
    toolVersion: '0.1.0',
  );

  final generateResult = await generator.generate(
    spec,
    outputDir,
    baseUrlOverride: baseUrl,
  );

  for (final d in generateResult.diagnostics) {
    reporter.warning(d.message);
  }

  // 4. Report results
  reporter.done(generateResult.filesWritten.length);

  return 0;
}

void _printUsage(ArgParser parser) {
  print(
      'dart_open_fetch — Generate typed Dart HTTP clients from OpenAPI schemas.\n');
  print('Usage: dart_open_fetch <command> [options]\n');
  print('Commands:');
  print('  generate <schema>    Generate Dart code from an OpenAPI schema\n');
  print('Global options:');
  print(parser.usage);
}
