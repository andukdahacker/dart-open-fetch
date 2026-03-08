## 0.2.0

### Bug fixes
- Fix `required` keyword on constructor params for non-required nullable fields.
  Previously a field not in the OpenAPI `required` array could still get `required this.field` in the constructor.

### Features
- **DateTime support:** `format: date-time` string schemas now generate `DateTime` fields with `DateTime.parse()` / `toIso8601String()` serialization.
- **Doc comments:** Emit `///` doc comments on classes, fields, enums, and client methods from OpenAPI `description` and `summary` fields.
- **Typed error responses:** Client methods with 4xx/5xx responses that define JSON schemas now parse the error body into a typed model, available via `ApiException.parsedBody`.
- **`--skip-unused-schemas`:** Only generate model classes for schemas referenced by operations.
- **`--no-additional-properties`:** Strip `additionalProperties` from all schemas before generation.
- **`--deduplicate-enums`:** Merge enum schemas that share identical value sets into a single canonical enum.
- **`--client-name`:** Override the generated client class name and skip tag-based grouping, producing a single client class.
- **Enum deduplicator:** New `EnumDeduplicator` pre-processing pass that groups enum schemas by sorted value set, picks the shortest name as canonical, and rewrites all references.

## 0.1.0

- Initial release.
- OpenAPI 3.0 and 3.1 schema parsing.
- Code generation for typed models, enums, and sealed union classes.
- Client generation with typed methods grouped by tags.
- `$ref` resolution including circular reference detection.
- `allOf`, `oneOf`, and `anyOf` composition support.
