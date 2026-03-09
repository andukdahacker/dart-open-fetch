## 0.3.0

### Features
- **`HttpRequest.copyWith`:** Create modified copies of immutable requests. `copyWith(body: null)` keeps the existing body (standard Dart convention).
- **`ApiException.parsedBodyAs<T>()`:** Type-safe accessor for `parsedBody`. Returns `null` instead of requiring manual `is`/`as` checks.
- **`HttpClientAdapter`:** Built-in `HttpAdapter` implementation backed by `package:http`. No longer need to write your own adapter for standard HTTP usage.
- **`BearerAuthMiddleware`:** Built-in middleware that injects `Authorization: Bearer <token>` headers. The `token` field is mutable for easy refresh.

## 0.2.0

- Add optional `parsedBody` field to `ApiException` for typed error response data.

## 0.1.0

- Initial release.
- `HttpAdapter` abstract class for pluggable HTTP implementations.
- `HttpRequest` and `HttpResponse` immutable value classes.
- `Middleware` and `MiddlewareChain` for composable request/response processing.
- `ApiResponse<T>` typed success wrapper.
- `ApiException` for non-2xx response errors.
