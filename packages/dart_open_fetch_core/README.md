# dart_open_fetch_core

Schema parser and code generator for [dart_open_fetch](https://github.com/andukdahacker/dart-open-fetch).

Parses OpenAPI 3.0/3.1 specifications into an intermediate representation and generates typed Dart clients and models.

## Usage

This package is used internally by the `dart_open_fetch` CLI. Most users should use the CLI directly rather than depending on this package.

```dart
import 'package:dart_open_fetch_core/dart_open_fetch_core.dart';

final parser = OpenApiParser(fileReader: myFileReader);
final result = await parser.parse(schema, basePath: '.');

final generator = DartGenerator(
  schemaSource: 'petstore.yaml',
  toolVersion: '0.1.0',
);
final output = await generator.generate(result.spec, 'lib/api/');
```

See the [main project README](https://github.com/andukdahacker/dart-open-fetch) for full documentation.
