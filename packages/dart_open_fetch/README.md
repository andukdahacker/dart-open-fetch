# dart_open_fetch

CLI tool that generates fully-typed Dart HTTP clients from OpenAPI 3.0/3.1 specifications.

## Installation

```bash
dart pub global activate dart_open_fetch
```

## Usage

```bash
dart_open_fetch generate <schema> [options]
```

| Option | Default | Description |
|---|---|---|
| `-o`, `--output` | `lib/api/` | Output directory for generated code |
| `--base-url` | *(from schema)* | Override the server base URL |

```bash
dart_open_fetch generate petstore.yaml -o lib/api/
dart_open_fetch generate https://api.example.com/openapi.yaml --base-url https://api.example.com
```

See the [main project README](https://github.com/andukdahacker/dart-open-fetch) for full documentation and examples.
