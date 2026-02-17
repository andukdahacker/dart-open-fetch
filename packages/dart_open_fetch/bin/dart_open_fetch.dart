import 'dart:io';

import 'package:dart_open_fetch/src/cli_runner.dart';

Future<void> main(List<String> arguments) async {
  final exitCode = await runCli(arguments);
  exit(exitCode);
}
