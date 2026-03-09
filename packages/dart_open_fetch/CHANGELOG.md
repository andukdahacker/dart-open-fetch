## 0.3.0

### New CLI flags
- `--wrapper` — Generate thin `{Name}Service` wrappers that unwrap `ApiResponse<T>` to `Future<T>`.

### Improvements
- Bumped `dart_open_fetch_core` dependency to `^0.3.0`.

## 0.2.0

### New CLI flags
- `--client-name` — Override client class name (single client, no tag grouping).
- `--no-additional-properties` — Strip `additionalProperties` from all schemas.
- `--skip-unused-schemas` — Only generate schemas referenced by operations.
- `--deduplicate-enums` — Merge enum schemas with identical value sets.

### Improvements
- Generated code now includes `///` doc comments from OpenAPI descriptions.
- `format: date-time` fields generate as `DateTime` with proper serialization.
- Typed error response parsing via `ApiException.parsedBody`.

## 0.1.0

- Initial release.
- `generate` command to produce Dart clients from OpenAPI schemas.
- Support for local file and remote URL schema sources.
- `--output` and `--base-url` options.
