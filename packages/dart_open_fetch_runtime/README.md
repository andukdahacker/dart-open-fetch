# dart_open_fetch_runtime

Runtime library for [dart_open_fetch](https://github.com/andukdahacker/dart-open-fetch) generated clients.

Add this package as a dependency in projects that use generated code from `dart_open_fetch`.

## Installation

```yaml
dependencies:
  dart_open_fetch_runtime: ^0.1.0
```

## API

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

See the [main project README](https://github.com/andukdahacker/dart-open-fetch) for full documentation and examples.
