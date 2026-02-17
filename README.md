# dart_open_fetch

Generate fully-typed Dart HTTP clients from OpenAPI 3.0/3.1 specifications.

[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.5.0-blue)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![style: lints](https://img.shields.io/badge/style-lints-blue)](https://pub.dev/packages/lints)

## Features

- Generates typed clients from **OpenAPI 3.0** and **3.1** specs (YAML or JSON)
- Fully typed request parameters, bodies, and responses
- Composable middleware (logging, auth, retry, etc.)
- Pluggable HTTP adapter — bring your own HTTP library
- `fromJson` / `toJson`, `copyWith`, `==` / `hashCode` on all models
- `oneOf` / `anyOf` / `allOf` composition support (sealed classes)
- Null safety, circular `$ref` handling
- Zero reflection — works with AOT / tree-shaking

## Quick Start

Install the CLI from Git:

```bash
dart pub global activate --source git https://github.com/andukdahacker/dart-open-fetch.git --git-path packages/dart_open_fetch
```

Generate a client from an OpenAPI spec:

```bash
dart_open_fetch generate petstore.yaml -o lib/api/
```

Use the generated client:

```dart
import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:my_app/api/swagger_petstore.dart';

Future<void> main() async {
  final adapter = MyHttpAdapter();      // your HttpAdapter implementation
  final client = PetClient(
    adapter: adapter,
    middleware: [LoggingMiddleware()],
  );

  try {
    final response = await client.getPetById(petId: 1);
    print('Pet: ${response.data}');
  } on ApiException catch (e) {
    print('Error ${e.statusCode}: ${e.body}');
  }
}
```

## Packages

| Package | Description |
|---|---|
| `dart_open_fetch` | CLI tool — parses specs and generates Dart code |
| `dart_open_fetch_core` | Parser + code generator library |
| `dart_open_fetch_runtime` | Runtime library — users add this as a dependency |

## Installation

Add the runtime dependency to your `pubspec.yaml`:

```yaml
dependencies:
  dart_open_fetch_runtime:
    git:
      url: https://github.com/andukdahacker/dart-open-fetch.git
      path: packages/dart_open_fetch_runtime
```

Install the CLI globally from Git:

```bash
dart pub global activate --source git https://github.com/andukdahacker/dart-open-fetch.git --git-path packages/dart_open_fetch
```

Or run it from a local checkout:

```bash
dart run packages/dart_open_fetch/bin/dart_open_fetch.dart generate <schema>
```

## Usage

### Generate code

```bash
dart_open_fetch generate <schema> [options]
```

| Option | Default | Description |
|---|---|---|
| `-o`, `--output` | `lib/api/` | Output directory for generated code |
| `--base-url` | *(from schema)* | Override the server base URL |
| `-h`, `--help` | | Show usage help |

The schema can be a local file or a remote URL:

```bash
# Local file
dart_open_fetch generate ./petstore.yaml -o lib/api/

# Remote URL
dart_open_fetch generate https://petstore3.swagger.io/api/v3/openapi.yaml -o lib/api/

# Override base URL
dart_open_fetch generate petstore.yaml -o lib/api/ --base-url https://api.example.com
```

### Create an HttpAdapter

Implement `HttpAdapter` to bridge to any HTTP library. Here's an example using `package:http`:

```dart
import 'package:http/http.dart' as http;
import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';

class HttpClientAdapter implements HttpAdapter {
  HttpClientAdapter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final httpRequest = http.Request(request.method, request.url);
    httpRequest.headers.addAll(request.headers);
    if (request.body != null) {
      httpRequest.body = request.body!;
    }

    final streamedResponse = await _client.send(httpRequest);
    final body = await streamedResponse.stream.bytesToString();

    return HttpResponse(
      statusCode: streamedResponse.statusCode,
      headers: streamedResponse.headers,
      body: body,
    );
  }

  void close() => _client.close();
}
```

### Add middleware

Middleware intercepts requests and responses. They execute in order on the way out and in reverse on the way back.

```dart
class LoggingMiddleware implements Middleware {
  @override
  Future<HttpResponse> handle(HttpRequest request, Next next) async {
    print('--> ${request.method} ${request.url}');

    final sw = Stopwatch()..start();
    final response = await next(request);
    sw.stop();

    print('<-- ${response.statusCode} (${sw.elapsedMilliseconds}ms)');
    return response;
  }
}
```

### Use the generated client

```dart
import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:my_app/api/swagger_petstore.dart';

Future<void> main() async {
  final adapter = HttpClientAdapter();
  final logging = LoggingMiddleware();

  final petClient = PetClient(
    adapter: adapter,
    middleware: [logging],
  );

  try {
    // Typed responses — data is already deserialized
    final response = await petClient.findPetsByStatus(status: 'available');
    final pets = response.data; // List<Pet>

    for (final pet in pets) {
      print('${pet.name} (id: ${pet.id})');
    }
  } on ApiException catch (e) {
    print('API error: status ${e.statusCode}, body: ${e.body}');
  } finally {
    adapter.close();
  }
}
```

### Generated output structure

```
lib/api/
  models.dart                  # All models, enums, and union types
  clients/
    pet_client.dart            # PetClient class
    store_client.dart          # StoreClient class
    user_client.dart           # UserClient class
  swagger_petstore.dart        # Barrel export (import this)
```

Generated clients accept `adapter`, `middleware`, and `baseUrl` in their constructor. Each method returns `Future<ApiResponse<T>>` and throws `ApiException` on non-2xx responses.

Generated models include:
- `fromJson` factory constructor
- `toJson()` method
- `copyWith()` for immutable updates
- `==` / `hashCode` for value equality
- `toString()` for debugging

## Runtime API Reference

| Type | Description |
|---|---|
| `HttpAdapter` | Abstract class — implement `send(HttpRequest)` to plug in any HTTP library |
| `HttpRequest` | Immutable request value object (`method`, `url`, `headers`, `body`) |
| `HttpResponse` | Immutable response value object (`statusCode`, `headers`, `body`) |
| `Middleware` | Abstract class — implement `handle(HttpRequest, Next)` to intercept requests |
| `Next` | `typedef Future<HttpResponse> Function(HttpRequest)` — calls the next middleware or adapter |
| `MiddlewareChain` | Composes a list of `Middleware` with an `HttpAdapter` into a single send pipeline |
| `ApiResponse<T>` | Typed success wrapper (`data`, `statusCode`, `headers`) |
| `ApiException` | Thrown on non-2xx responses (`statusCode`, `body`, `headers`) |

## OpenAPI Feature Support

**Spec versions:** OpenAPI 3.0.x, OpenAPI 3.1.x

**Schema types:** `string`, `integer`, `number`, `boolean`, `array`, `object`

**Formats:** `date-time`, `uuid`, `email`, `uri`, `int32`, `int64`, `float`, `double`

**Parameters:** `query`, `path`, `header`, `cookie` — with `required`, `style`, `explode`, `deprecated`

**Request bodies:** `application/json` content type with schema references

**Responses:** Per-status-code response schemas, `default` responses, response headers

**Composition:** `allOf` (merged classes), `oneOf` / `anyOf` (sealed union classes with discriminator support)

**References:** Local `$ref` pointers, relative file `$ref` resolution, circular `$ref` detection

**Security schemes:** `apiKey`, `http` (bearer/basic), `oauth2`, `openIdConnect`

## Examples

### Console application

A Dart console app demonstrating the generated Petstore client with a custom `HttpAdapter` and `LoggingMiddleware`.

See [`examples/dart_console/`](examples/dart_console/).

### Flutter application

A Flutter app demonstrating the generated client in a mobile/web context.

See [`examples/flutter_app/`](examples/flutter_app/).

## Development

### Prerequisites

- Dart SDK >= 3.5.0
- [Melos](https://melos.invertase.dev/) (`dart pub global activate melos`)

### Setup

```bash
git clone https://github.com/andukdahacker/dart-open-fetch.git
cd dart-open-fetch
melos bootstrap
```

### Commands

```bash
melos analyze        # Run dart analyze on all packages
melos test           # Run tests in all packages
melos format-check   # Check formatting of all packages
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Make your changes and ensure tests pass (`melos test`)
4. Run analysis and formatting checks (`melos analyze && melos format-check`)
5. Commit your changes (`git commit -m 'Add my feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
