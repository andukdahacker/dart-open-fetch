/// Reports progress messages to stdout during CLI execution.
class ProgressReporter {
  void fetching(String source) => _print('Fetching schema from $source...');
  void parsing() => _print('Parsing schema...');
  void generating(int modelCount, int clientCount) {
    _print('Generating $modelCount models, $clientCount clients...');
  }

  void writing(String outputDir) => _print('Writing files to $outputDir...');

  void done(int fileCount) =>
      _print('Done. Generated $fileCount files.');

  void warning(String message) => _print('  Warning: $message');

  void _print(String message) => print(message);
}
