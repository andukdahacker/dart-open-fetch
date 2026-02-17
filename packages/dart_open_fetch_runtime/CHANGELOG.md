## 0.1.0

- Initial release.
- `HttpAdapter` abstract class for pluggable HTTP implementations.
- `HttpRequest` and `HttpResponse` immutable value classes.
- `Middleware` and `MiddlewareChain` for composable request/response processing.
- `ApiResponse<T>` typed success wrapper.
- `ApiException` for non-2xx response errors.
