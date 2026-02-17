---
title: 'Dart Open Fetch'
slug: 'dart-open-fetch'
created: '2026-02-16'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack: ['dart', 'package:args', 'package:yaml', 'package:http', 'package:code_builder', 'package:dart_style', 'package:test', 'melos']
files_to_modify: []
code_patterns: ['mono-repo', 'adapter-pattern', 'middleware-chain', 'intermediate-representation', 'golden-file-tests', 'code-builder-emission', 'custom-parser']
test_patterns: ['golden-file-snapshot', 'fixture-schema-corpus', 'mock-adapter-injection', 'dart-analyze-gate']
---

# Tech-Spec: Dart Open Fetch

**Created:** 2026-02-16

## Overview

### Problem Statement

The Dart/Flutter ecosystem lacks a lightweight, dependency-minimal OpenAPI client generator. Existing solutions either depend on the heavy Java-based openapi-generator-cli or force opinionated dependencies like retrofit/freezed. Developers need a simple CLI that points at a schema and produces ready-to-use, strictly typed Dart code.

### Solution

A standalone Dart CLI tool that fetches or reads OpenAPI 3.0/3.1 schemas (from URL or local file path), resolves `$ref` references across multiple files, and generates plain Dart data classes with `fromJson`/`toJson`, a thin strictly-typed HTTP client that wraps any underlying HTTP library, and optional modular plugins for auth, middleware/interceptors, and retry logic.

### Scope

**In Scope:**

- CLI tool accepting URL endpoint or local file path (JSON/YAML)
- OpenAPI 3.0 and 3.1 schema parsing with full `$ref` resolution (multi-file)
- Data class generation (plain Dart, `fromJson`/`toJson`)
- Typed HTTP client generation with method wrappers per endpoint
- HTTP library-agnostic design (user plugs in `http`, `dio`, or custom)
- Modular, optional auth helpers
- Modular, optional middleware/interceptor system
- Modular, optional retry logic

**Out of Scope:**

- Swagger 2.0 support (parser must detect and reject with clear error: "Swagger 2.0 is not supported. Please convert to OpenAPI 3.0+")
- `build_runner` integration
- Dependencies on `freezed`, `json_serializable`, or `retrofit`
- Server stub generation (client-only)
- UI/Flutter-specific code generation
- Non-JSON request/response body serialization (`multipart/form-data`, `application/x-www-form-urlencoded`, `application/octet-stream`, `text/plain`). v0.1 supports `application/json` only. Non-JSON content types are silently skipped during generation with a warning logged to stderr.
- Remote `$ref` resolution over HTTP (v0.1 supports local `$ref` only — `#/...` and relative file paths). Remote URL refs emit a warning and are skipped.

## Context for Development

### Architecture — Mono-Repo with Three Packages

```
packages/
  dart_open_fetch/         # CLI entry point (published name for `dart pub global activate`)
  dart_open_fetch_core/    # Schema parser + code generator
  dart_open_fetch_runtime/ # User-facing runtime library (ships with generated code)
```

- **`dart_open_fetch_core`** — The schema parser + code generator. Accepts a pre-loaded `Map<String, dynamic>` (already parsed from JSON/YAML) and a base directory path for resolving relative file `$ref`s. Produces an intermediate representation (IR) then generates Dart code. No HTTP dependency, no direct file fetching — the CLI layer handles I/O and passes parsed data in. Fully testable in isolation.
- **`dart_open_fetch`** — Thin CLI shell. Arg parsing via `package:args`, schema fetching (URL via `package:http` or file via `dart:io`), JSON/YAML parsing, and invoking the core with the resulting `Map<String, dynamic>`. Entry point users install globally via `dart pub global activate`. **The CLI owns all I/O** — it reads files, fetches URLs, and passes parsed maps to core.
- **`dart_open_fetch_runtime`** — The tiny runtime library that ships with generated code. Contains the `HttpAdapter` interface, `HttpRequest`/`HttpResponse` value classes, and `Middleware` chain interface. Pure Dart, zero external dependencies. Users add this as a dependency — everything else is dev-time only. **v0.1 ships interfaces only — no built-in middleware implementations (auth, retry, logging). Implementations come in v0.2.**

**Core ↔ CLI contract:** The CLI parses the schema file/URL into a `Map<String, dynamic>` and passes it to `core`'s `OpenApiParser.parse(Map<String, dynamic> schema, {required String basePath})`. The `basePath` is the directory containing the root schema file, used by the `$ref` resolver for relative file resolution. For relative file `$ref`s, the core calls a `FileReader` callback (`Future<Map<String, dynamic>> Function(String path)`) injected by the CLI, keeping the core free of `dart:io` imports.

**Generated client ↔ runtime contract:** The generated client class constructor takes `HttpAdapter adapter` (required) and `List<Middleware> middleware` (optional, defaults to `[]`). Internally, the constructor composes them into a `MiddlewareChain` instance stored as a private field. All generated methods call `_chain.send(request)` — the client owns the chain lifecycle.

Workspace managed with `melos` for mono-repo coordination.

### Codebase Patterns

Greenfield project. Patterns to be established:

- Pure Dart packages (not Flutter-dependent)
- CLI entry point using `package:args`
- Generated code must be human-readable, idiomatic Dart, and `dart format` clean
- HTTP client abstraction via adapter pattern — users plug in any HTTP library
- Middleware chain via decorator pattern for composable request/response processing
- Modular plugin architecture for optional features (auth, middleware, retry)
- Intermediate representation (IR) decouples schema parsing from code generation

### Key Design Patterns

#### HttpRequest / HttpResponse (runtime value classes)

```dart
class HttpRequest {
  HttpRequest({
    required this.method,
    required this.url,
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  final String method;           // GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
  final Uri url;                 // Fully constructed URL including query params
  final Map<String, String> headers;  // Unmodifiable — middleware must create new HttpRequest to change headers
  final String? body;            // null (no body) or String (JSON-serialized). Always String for v0.1.
}

class HttpResponse {
  HttpResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    required this.body,
  }) : headers = Map.unmodifiable(headers);

  final int statusCode;
  final Map<String, String> headers;  // Unmodifiable (adapters merge multi-value with comma before constructing)
  final String body;             // Response body as string (adapters decode bytes)
}
```

Both are truly immutable value classes — headers are wrapped in `Map.unmodifiable()` at construction, preventing mutation after creation. Middleware that needs to modify headers must create a new `HttpRequest` instance (copy-on-write pattern). `==`/`hashCode` use `MapEquality` for headers comparison. `toString` included for debugging.

**Body type is `String?`** (not `Object?`) in v0.1 — all request bodies are JSON-serialized strings. This removes ambiguity for adapter implementers. Binary body support (`List<int>`) deferred to v0.2.

#### HTTP Adapter (runtime)

```dart
/// Users implement this to plug in any HTTP library
abstract class HttpAdapter {
  Future<HttpResponse> send(HttpRequest request);
}
```

#### Middleware Chain (runtime)

```dart
typedef Next = Future<HttpResponse> Function(HttpRequest request);

abstract class Middleware {
  Future<HttpResponse> handle(HttpRequest request, Next next);
}

class MiddlewareChain {
  MiddlewareChain(this._adapter, [this._middleware = const []]);

  final HttpAdapter _adapter;
  final List<Middleware> _middleware;

  Future<HttpResponse> send(HttpRequest request) { /* compose chain */ }
}
```

Auth, retry, and logging are all middleware implementations. The generated client constructor takes an `HttpAdapter` (required) and an optional `List<Middleware>`. It internally constructs a `MiddlewareChain` and stores it as a private field. All generated methods call `_chain.send(request)`.

Optional adapter packages (e.g., `dart_open_fetch_dio_adapter`, `dart_open_fetch_http_adapter`) can be shipped separately. The core runtime defines only interfaces — zero coupling.

### CLI Design & Developer Experience

```bash
# Zero-config happy path — one command, done
dart_open_fetch generate https://api.example.com/openapi.json

# Local file with output directory
dart_open_fetch generate ./specs/api.yaml -o lib/api/
```

**DX Principles:**

- No Java runtime, no Docker, no config file required
- Minimal steps to working client: install tool → run generate → add runtime dep → implement adapter → use client. (Note: user must implement `HttpAdapter` for their chosen HTTP library — this is a conscious trade-off for HTTP-library freedom)
- Meaningful error messages: if a schema has unsupported constructs, report *what* and *where* with suggestions. If schema version is Swagger 2.0, reject with clear message.
- Progress feedback for large schemas: `Parsing schema... Resolving refs... Generating 47 models... Generating 23 endpoints... Done.`
- Generated code must look like a human wrote it — proper `dart format`, logical file organization, class names derived directly from schema names

### Competitive Positioning

| | openapi_generator | openapi_retrofit_generator | **dart_open_fetch** |
|---|---|---|---|
| Requires Java | Yes | No | **No** |
| External deps in generated code | Many | freezed + retrofit + dio | **1 (lightweight runtime only)** |
| Install complexity | High | Medium | **`dart pub global activate`** |
| Generated code readability | Low | Medium | **High (human-like)** |
| HTTP library lock-in | Yes (dio) | Yes (retrofit/dio) | **None (adapter pattern)** |
| Plugin system | No | No | **Yes (middleware chain)** |

**Differentiators:** Zero-config simplicity, dependency-light output, HTTP library freedom, and a proper plugin system. No one else in the Dart ecosystem offers all four.

### Files to Reference

| File | Purpose |
| ---- | ------- |

_No existing files — greenfield project._

### Technical Decisions

- **Dependency-light philosophy**: Generated code imports only `dart_open_fetch_runtime` — zero external deps
- **HTTP library agnostic**: Generated client wraps a user-provided `HttpAdapter`, not a specific HTTP library
- **Plain Dart data classes**: No codegen dependencies (`freezed`, `json_serializable`) — generate `fromJson`/`toJson` directly
- **Modular optional features**: Auth, middleware, and retry are opt-in middleware implementations, not baked into the core client
- **Intermediate Representation**: Parser produces an IR (AST-like model) to decouple parsing from code emission — enables future emitter swaps
- **Mono-repo with melos**: Three focused packages with clear dependency boundaries
- **Custom parser (no third-party OpenAPI libs)**: Build OpenAPI parser from scratch using `package:yaml` + `dart:convert` for full control over schema handling, `$ref` resolution, and 3.0/3.1 compatibility
- **Pointer-sharing `$ref` resolution (ogen-inspired)**: Component schema `$ref`s are resolved at IR level by `SchemaParser` using a registry cache — each schema is parsed once and the same `ApiSchema` instance is shared everywhere. `RefResolver` only handles non-schema `$ref`s (parameters, responses, etc.) which are small enough to deep-copy safely. This avoids the deep-copy memory explosion that is the #1 cause of OOM across OpenAPI tooling (swagger-parser, Redoc, Spectral). Peak memory reduced from ~200-250MB to ~55MB on GitHub's 8.6MB spec. See: [`refactor-ref-resolver-pointer-sharing.md`](./refactor-ref-resolver-pointer-sharing.md)
- **`package:code_builder` for code emission**: Use `code_builder` + `DartEmitter.scoped()` for structured, maintainable code generation with automatic import management. Format output with `package:dart_style` (`DartFormatter`)
- **CLI minimal deps**: `package:args` + `package:http` (for URL fetching only)
- **Core deps**: `dart:convert` + `package:yaml` + `package:code_builder` + `package:dart_style`
- **Dart SDK constraint**: Minimum `^3.0.0`. Sealed classes and pattern matching (used for `oneOf` unions) require Dart 3.0+. All `pubspec.yaml` files must specify `environment: sdk: '>=3.0.0 <4.0.0'`.
- **`allOf` composition → flattening (not inheritance)**: When a schema uses `allOf`, the generator flattens all member properties into a single class. No Dart `extends` is generated from `allOf`. Rationale: flattening is simpler, avoids diamond inheritance issues, and works consistently regardless of `allOf` member count. If two `allOf` members define the same property name with the same type, deduplicate. If types conflict, use `dynamic` and log a warning.
- **`additionalProperties` → `Map` types**: Schema `{ type: object, additionalProperties: { type: string } }` generates `Map<String, String>`. Schema `{ type: object }` with no `properties` and no `additionalProperties` constraint generates `Map<String, dynamic>` (free-form JSON). Schema with both `properties` AND `additionalProperties` generates a class with named fields plus an `additionalProperties` `Map` field.
- **`oneOf` without discriminator → ordered try-parse**: When no discriminator is present, `fromJson` attempts to deserialize each variant in the order they appear in the schema. First successful parse wins. Each variant's `fromJson` must throw `FormatException` on type mismatch (not return null). If no variant matches, throw `FormatException` listing all attempted types. This is O(n) by design — `oneOf` without discriminator is uncommon and inherently ambiguous.
- **`copyWith` with nullable fields → `Wrapped` sentinel pattern**: Generate a private `_Undefined` sentinel class as a `const` singleton. `copyWith` parameters use specific nullable types (not `Object?`) with default `_Undefined()` via a type cast trick: `T Function(T)? transform` pattern for each nullable field, e.g., `String? Function()? name`. If the parameter is not provided (null callback), the field is unchanged. If provided, the callback's return value is used (can return null). This avoids the `Object?` ambiguity entirely — each field uses its own typed callback. For non-nullable fields, `copyWith` uses simple optional parameters with defaults.
- **Response content type handling**: Generated client methods only deserialize `application/json` responses. If a response has multiple content types, the generator uses the `application/json` schema and ignores others. If a response has no `application/json` content type, the method returns the raw `HttpResponse` instead of a typed model.
- **Response status code handling**: The generated method's return type is determined by the **2xx success response** schema (prefer `200`, then `201`, then first 2xx found). The method returns `ApiResponse<T>` (a runtime class) containing `T data` (deserialized success body), `int statusCode`, and `Map<String, String> headers`. For non-2xx responses, the method throws `ApiException` (a runtime class) containing `int statusCode`, `String body` (raw), and `Map<String, String> headers`. This gives consumers typed success paths and catch-able error paths. `ApiResponse` and `ApiException` are defined in the runtime package.
- **Server variable handling**: v0.1 treats server URLs as static strings. Server variables (`{environment}` in `https://{environment}.api.com`) are resolved using their `default` value at generation time. The generated client has a `baseUrl` constructor parameter (String) defaulting to the resolved first server URL. Users override at construction time. Server variable enums and runtime substitution are deferred to v0.2.
- **Tag-based client grouping**: Operations with one or more tags are grouped into client classes named `{Tag}Client` (e.g., `PetsClient`, `UsersClient`). Operations with **no tags** go into a `DefaultClient` class. Operations with **multiple tags** are placed in the **first tag's** client class only (no duplication). If no operations have tags, a single client class named `{ApiTitle}Client` is generated.
- **`additionalProperties` + named properties `toJson` merge**: `toJson` produces a flat JSON object. Named properties are serialized first, then `additionalProperties` entries are spread into the same object. If an `additionalProperties` key collides with a named property key, the named property wins (additional property is silently dropped). `fromJson` extracts known property keys first, then collects remaining keys into `additionalProperties`.
- **URL construction**: Base URL and path template are joined with path normalization: trailing slash on base URL is stripped, leading slash on path template is ensured, producing `{baseUrl}/{path}`. Path params are interpolated via `Uri.encodeComponent()`. Query params with `null` values are omitted. Array-valued query params with `explode: true` (default) produce repeated keys: `?a=1&a=2`. The full URL is constructed as a `Uri` object ensuring proper encoding.
- **Parameter serialization**: v0.1 supports `style: simple` for path params and `style: form, explode: true` for query params (the OpenAPI defaults). Other styles (`label`, `matrix`, `spaceDelimited`, `pipeDelimited`, `deepObject`) are not supported in v0.1 — params with non-default styles are serialized using default style with a warning. Path params use simple string interpolation. Query params use `Uri` query parameter encoding.
- **Runtime semver strategy**: `dart_open_fetch_runtime` follows semver strictly. Generated code includes a `// requires: dart_open_fetch_runtime ^0.1.0` comment in the header. The runtime's `HttpAdapter`, `HttpRequest`, `HttpResponse`, and `Middleware` interfaces are the stability contract — any breaking change to these is a major version bump.

### Code Generation Strategy

Use `package:code_builder` for structural scaffolding (class declarations, method signatures, imports, field definitions) with `DartEmitter.scoped()` for automatic import management. For complex deserialization logic in `fromJson`/`toJson` bodies (e.g., `List<Map<String, List<SomeModel>>>`), use `Code()` blocks with raw expressions where the builder API becomes more verbose than helpful. This hybrid approach avoids fighting `code_builder`'s API for expression-level code while retaining its benefits for structural code.

### Generated Code Conventions

- **Class names must match schema names exactly.** If the schema says `CreateUserRequest`, the class is `CreateUserRequest` — not `CreateUserRequestModel`, not `CreateUserReq`.
- **Generated files must include a header comment:** source schema path/URL, generation timestamp, and `dart_open_fetch` version. This allows developers to trace generated code back to its source when debugging.
- **All generated code must pass `dart format` and `dart analyze` with zero warnings.**
- **Deprecated handling:** OpenAPI `deprecated: true` on operations, parameters, and schema properties generates Dart `@Deprecated('Deprecated in API spec')` annotations on the corresponding methods, parameters, and fields.

#### Name Collision Resolution

- **Dart reserved words:** If a schema name, enum value, or operationId collides with a Dart reserved word (`class`, `default`, `switch`, etc.), append a `$` suffix (e.g., `class` → `class$`). The `fromJson`/`toJson` methods use the original string value.
- **Enum value sanitization:** Enum values that are not valid Dart identifiers are transformed: hyphens/spaces to camelCase (`in-progress` → `inProgress`), leading digits prefixed with `value` (`404` → `value404`), empty string becomes `empty`. Original string values preserved in `fromJson`/`toJson` serialization.
- **Duplicate class names:** If two schemas resolve to the same Dart class name (e.g., from different `$ref` paths), the generator appends a numeric suffix (`User`, `User2`). A warning is logged to stderr.
- **File name collisions:** Generated file names are lowercased with underscores (`CreateUserRequest` → `create_user_request.dart`). If two schemas produce the same file name on case-insensitive file systems, the numeric suffix from class deduplication ensures unique file names.

### Error Handling Strategy

The core package defines a structured error hierarchy:

```dart
/// Base class for all dart_open_fetch fatal errors (thrown)
class OpenFetchException implements Exception {
  final String message;
  final String? schemaPath;  // JSON pointer to location in schema (e.g., "#/paths/~1users/get")
}

/// Schema is structurally invalid or uses unsupported version
class SchemaParseException extends OpenFetchException {}

/// $ref target not found or circular ref detected
class RefResolutionException extends OpenFetchException {}

/// Code generation failed for a specific schema/operation
class GenerationException extends OpenFetchException {}

/// Non-fatal diagnostic (collected, NOT thrown). Separate from Exception hierarchy.
class Diagnostic {
  final String message;
  final String? schemaPath;
  final DiagnosticSeverity severity;  // warning, info
}

enum DiagnosticSeverity { warning, info }
```

**Error behavior:**
- **Fatal errors** (invalid schema structure, missing required fields, unsupported version): throw exception, halt, report location in schema with clear message
- **Non-fatal warnings** (unsupported parameter style, non-JSON content type, remote `$ref`, deprecated constructs): log to stderr with schema path, continue generation, include warning summary at end
- **All errors include the JSON pointer path** (`#/components/schemas/Pet/properties/name`) so users can locate the issue in their schema
- **Swagger 2.0 detection**: if `swagger` field exists instead of `openapi`, throw `SchemaParseException` with message: "Swagger 2.0 is not supported. Please convert to OpenAPI 3.0+ using https://converter.swagger.io"

### OpenAPI 3.0 vs 3.1 Compatibility Notes

Parser must handle these version differences:

| Feature | OpenAPI 3.0 | OpenAPI 3.1 |
|---|---|---|
| **Nullable** | `nullable: true` property | `type: [string, "null"]` (JSON Schema array) |
| **`$ref` resolution** | Can resolve during parse | Must parse full document first (JSON Schema Draft 2020-12) |
| **`exclusiveMinimum`/`exclusiveMaximum`** | Boolean values | Numeric values |
| **Examples** | `example` (single value) | `examples` (array) |
| **Schema alignment** | OpenAPI-specific Schema Object | Full JSON Schema Draft 2020-12 compatibility |

The parser must detect schema version from `openapi` field and normalize both formats into a unified IR.

**3.1 multi-type arrays beyond nullable:** OpenAPI 3.1 (JSON Schema Draft 2020-12) allows `type: [string, integer]` — meaning "string or integer." The normalizer handles:
- `type: [T, "null"]` → normalized to `type: T, nullable: true`
- `type: [T1, T2]` (no null) → normalized to an inline `oneOf: [{type: T1}, {type: T2}]` so the union generator handles it
- `type: [T1, T2, "null"]` → normalized to `oneOf: [{type: T1}, {type: T2}], nullable: true`

### Milestone Dependencies & Sequencing

Everything depends on the IR. The IR class hierarchy must be the first deliverable — before any parsing or generation code. Milestones must follow this strict dependency order:

1. **IR design + runtime interfaces** (adapter, middleware) — independently testable
2. **Parser** (OpenAPI → IR) + parser tests against fixture schemas — depends on IR
3. **Code generator** (IR → Dart via `code_builder`) + golden file tests — depends on IR
4. **CLI shell** wrapping it all together + integration tests — depends on parser + generator

No milestone can start its core work until the previous milestone's output exists.

### Risk Flags

| Source | Concern | Severity | Mitigation |
|---|---|---|---|
| Architect | Custom parser is 60-70% of total effort — highest scope risk | **High** | Test-drive against real schemas from day one; time-box `$ref` resolution |
| Architect | IR design must be detailed before implementation, not deferred | **High** | Define complete IR class hierarchy as first milestone deliverable |
| Dev | `code_builder` gets verbose for `fromJson`/`toJson` body expressions | **Medium** | Use `Code()` blocks for expression-level deserialization logic |
| Test Architect | Must test against Stripe spec (~80k lines) early, not just Petstore | **High** | Download Petstore, GitHub, Stripe specs into `test/fixtures/` on day one |
| Test Architect | Golden file updates become maintenance burden without tooling | **Medium** | Implement `--update-goldens` flag on test runner from the start |
| PM | MVP scope creep — ship interfaces not implementations for v0.1 | **Medium** | v0.1 = parser + models + client + runtime interfaces only; middleware implementations = v0.2 |
| Scrum Master | IR is critical path blocker — everything depends on it | **High** | Make IR design milestone 1; gate all other work behind it |
| Tech Writer | Generated class names must match schema exactly; include generation header | **Low** | Enforce naming convention in code generator; add header template |

### MVP Scope (v0.1)

**v0.1 ships:**
- CLI that accepts schema URL or local file path
- Custom OpenAPI 3.0/3.1 parser with `$ref` resolution
- Data class generation (plain Dart, `fromJson`/`toJson`)
- Typed HTTP client generation with method wrappers per endpoint
- Runtime package with `HttpAdapter` and `Middleware` **interfaces only**

**v0.1 does NOT ship:**
- Built-in auth middleware implementation
- Built-in retry middleware implementation
- Built-in logging middleware implementation
- Adapter packages (`dart_open_fetch_dio_adapter`, etc.)
- `dart_open_fetch init` config scaffolding (v0.2 — format TBD)
- Non-JSON content type serialization (`multipart/form-data`, `application/x-www-form-urlencoded`)
- Remote URL `$ref` resolution
- Non-default parameter serialization styles (`label`, `matrix`, `spaceDelimited`, `pipeDelimited`, `deepObject`)
- `readOnly`/`writeOnly` schema property handling (v0.1 ignores these flags — all properties appear in both request and response models. v0.2 can generate separate request/response model variants)
- Server variable runtime substitution (v0.1 resolves using `default` value at generation time)

## Implementation Plan

### Milestone 1: Project Scaffolding + IR Design + Runtime Interfaces

- [x] Task 1: Initialize mono-repo workspace
  - File: `melos.yaml` (create)
  - File: `packages/dart_open_fetch_core/pubspec.yaml` (create)
  - File: `packages/dart_open_fetch/pubspec.yaml` (create)
  - File: `packages/dart_open_fetch_runtime/pubspec.yaml` (create)
  - File: `analysis_options.yaml` (create at root, shared strict lints)
  - Action: Set up melos workspace with three packages, configure dependencies per package as specified in Dependencies section, add shared `analysis_options.yaml` with `package:lints/recommended.yaml`. All packages must specify `environment: sdk: '>=3.0.0 <4.0.0'` in `pubspec.yaml`.
  - Notes: Run `melos bootstrap` to link local packages. Dart 3.0+ required for sealed classes and pattern matching used in `oneOf` union generation.

- [x] Task 2: Download and commit version-pinned test fixture schemas
  - File: `packages/dart_open_fetch_core/test/fixtures/petstore.yaml` (create)
  - File: `packages/dart_open_fetch_core/test/fixtures/github.yaml` (create)
  - File: `packages/dart_open_fetch_core/test/fixtures/stripe.yaml` (create)
  - File: `packages/dart_open_fetch_core/test/fixtures/README.md` (create — document source URLs, versions, download dates)
  - Action: Download and **commit** specific versioned OpenAPI specs. Pin to exact versions for reproducible tests:
    - Petstore: `https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/examples/v3.0/petstore.yaml`
    - GitHub: Use a specific tagged release from `github/rest-api-description` repo
    - Stripe: Use a specific tagged release from `stripe/openapi` repo
  - Notes: Commit the fixture files to the repo — do NOT download at test time. Record exact source URL, commit hash, and download date in `README.md`. When updating fixtures, update golden files simultaneously.

- [x] Task 3: Design and implement IR class hierarchy
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_spec.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_info.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_path.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_operation.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_parameter.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_request_body.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_response.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_schema.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/ir/api_security.dart` (create)
  - Action: Define the complete intermediate representation as immutable Dart classes. This is the contract between the parser and the code generator.
  - Notes: **Critical path — all other milestones depend on this.**
    - `ApiSpec` — Root node. Contains `ApiInfo`, list of `ApiPath`, list of `ApiSchema` (components), list of `ApiSecurityScheme`
    - `ApiInfo` — Title, version, description, base URL(s)
    - `ApiPath` — URL path template, list of `ApiOperation`
    - `ApiOperation` — HTTP method, operationId, summary, list of `ApiParameter`, optional `ApiRequestBody`, map of status code to `ApiResponse`, list of security requirements, tags
    - `ApiParameter` — Name, location (query/path/header/cookie), required flag, `ApiSchema` for type, `style` (simple/form/label/matrix/etc.), `explode` flag, `deprecated` flag
    - `ApiRequestBody` — Required flag, map of content type to `ApiSchema`
    - `ApiResponse` — Status code, description, map of content type to `ApiSchema`, headers
    - `ApiSchema` — The type system. Must represent: primitives (string, int, double, bool), arrays (with item type), objects (with named properties + required list), **`additionalProperties` (schema for map value type, or `true` for `Map<String, dynamic>`, or `false`/absent for no additional props)**, enums (with raw string values), `allOf` (composition — flattened into merged properties), `oneOf` (union with optional discriminator), `anyOf` (union), `$ref` (resolved to target schema), nullable flag, format hints (date-time, uuid, email, uri, etc.), default values, `deprecated` flag
    - `ApiSecurityScheme` — Type (apiKey, http, oauth2, openIdConnect), location, scheme name

- [x] Task 3b: Implement error hierarchy and diagnostics
  - File: `packages/dart_open_fetch_core/lib/src/errors.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/diagnostic.dart` (create)
  - Action: Define `OpenFetchException` base class (extends `Exception`) with `message` and `schemaPath` fields. Define subclasses: `SchemaParseException` (invalid schema structure), `RefResolutionException` (`$ref` target not found or circular), `GenerationException` (code gen failure). Separately, define `Diagnostic` class (NOT an Exception — it is a collected value, never thrown) with `message`, `schemaPath`, and `DiagnosticSeverity` enum (`warning`, `info`). These are accumulated in `List<Diagnostic>` by parser and generator, returned in `ParseResult` and `GenerateResult`.
  - Notes: Fatal errors are Exceptions (thrown). Diagnostics are values (collected). CLI formats both for user output — exceptions as errors, diagnostics as warnings in a summary table.

- [x] Task 4: Implement runtime value classes and interfaces
  - File: `packages/dart_open_fetch_runtime/lib/src/http_adapter.dart` (create)
  - File: `packages/dart_open_fetch_runtime/lib/src/http_request.dart` (create)
  - File: `packages/dart_open_fetch_runtime/lib/src/http_response.dart` (create)
  - File: `packages/dart_open_fetch_runtime/lib/src/api_response.dart` (create)
  - File: `packages/dart_open_fetch_runtime/lib/src/api_exception.dart` (create)
  - Action: Define `HttpAdapter` abstract class with `Future<HttpResponse> send(HttpRequest request)`. Define `HttpRequest` as truly immutable value class: `String method`, `Uri url`, `Map<String, String> headers` (wrapped in `Map.unmodifiable()` at construction), `String? body` (null or JSON string — no `Object?` ambiguity). Define `HttpResponse` as truly immutable value class: `int statusCode`, `Map<String, String> headers` (unmodifiable), `String body`. Define `ApiResponse<T>` as typed success wrapper: `T data`, `int statusCode`, `Map<String, String> headers`. Define `ApiException` as error class extending `Exception`: `int statusCode`, `String body` (raw), `Map<String, String> headers`. Both `HttpRequest`/`HttpResponse` include `==` (using `MapEquality` for headers), `hashCode`, `toString`.
  - Notes: Pure Dart, zero deps except `package:collection` for `MapEquality`. Middleware that needs to modify headers must create a new `HttpRequest` (copy-on-write). `ApiResponse<T>` is what generated client methods return on success. `ApiException` is thrown on non-2xx responses.

- [x] Task 5: Implement runtime `Middleware` interface
  - File: `packages/dart_open_fetch_runtime/lib/src/middleware.dart` (create)
  - File: `packages/dart_open_fetch_runtime/lib/src/middleware_chain.dart` (create)
  - Action: Define `Middleware` abstract class with `handle(request, next)` pattern. Implement `MiddlewareChain` that composes a `List<Middleware>` + final `HttpAdapter` into a single callable chain.
  - Notes: ~30 lines of code. This is the extension point architecture — ship the interface, not implementations.

- [x] Task 6: Create runtime package barrel exports
  - File: `packages/dart_open_fetch_runtime/lib/dart_open_fetch_runtime.dart` (create)
  - Action: Export all public APIs: `HttpAdapter`, `HttpRequest`, `HttpResponse`, `Middleware`, `MiddlewareChain`, `ApiResponse`, `ApiException`
  - Notes: This is what generated code imports.

- [x] Task 7: Write unit tests for runtime
  - File: `packages/dart_open_fetch_runtime/test/middleware_chain_test.dart` (create)
  - File: `packages/dart_open_fetch_runtime/test/http_request_test.dart` (create)
  - File: `packages/dart_open_fetch_runtime/test/http_response_test.dart` (create)
  - Action: Test middleware chain ordering (middleware A → B → adapter), request/response pass-through, middleware short-circuiting, empty middleware list (direct to adapter)
  - Notes: Use mock `HttpAdapter` and test `Middleware` implementations

### Milestone 2: OpenAPI Parser (Schema → IR)

- [x] Task 8: Implement schema reader (raw map → validated map)
  - File: `packages/dart_open_fetch_core/lib/src/parser/schema_reader.dart` (create)
  - Action: Accept a pre-parsed `Map<String, dynamic>` (provided by CLI after JSON/YAML parsing). Validate it has an `openapi` field. If `swagger` field found instead, throw `SchemaParseException` with Swagger 2.0 rejection message. Return validated map for downstream parsing.
  - Notes: **Core does NOT do file I/O or URL fetching.** The CLI handles all I/O (file reading, YAML/JSON parsing, URL fetching) and passes the resulting `Map<String, dynamic>` to core. This keeps core free of `dart:io` and `package:http` dependencies.

- [x] Task 9: Implement version detector and normalizer
  - File: `packages/dart_open_fetch_core/lib/src/parser/version_detector.dart` (create)
  - Action: Read `openapi` field from loaded schema map. Detect 3.0.x vs 3.1.x. Normalize 3.0 constructs to 3.1 equivalents (e.g., `nullable: true` → type array with `"null"`, `example` → `examples` array, boolean `exclusiveMinimum` → numeric).
  - Notes: Normalization happens before parsing so the parser only deals with one format internally.

- [x] Task 10: Implement `$ref` resolver
  - File: `packages/dart_open_fetch_core/lib/src/parser/ref_resolver.dart` (create)
  - Action: Resolve non-schema `$ref` pointers in the raw map tree: relative file (`./models.yaml#/Pet`), local non-schema (`#/components/parameters/X`). Remote URL `$ref`s (`https://...`) are NOT resolved in v0.1 — log `Diagnostic` with the ref path and skip. For relative file refs, call the injected `FileReader` callback provided by the CLI layer — this keeps core free of `dart:io`.
  - **Refactored architecture (pointer-sharing):** Component schema `$ref`s (`#/components/schemas/X`) are **not** resolved by `RefResolver`. They are left as-is in the raw map tree and resolved at IR level by `SchemaParser` using a pointer-sharing registry (see Task 11). This avoids the deep-copy memory explosion that caused OOM on large specs (GitHub 8.6MB, Stripe 5.8MB). See: [`refactor-ref-resolver-pointer-sharing.md`](./refactor-ref-resolver-pointer-sharing.md).
  - **Circular reference strategy for non-schema refs:** Detect cycles via a `_resolving` set. When a cycle is detected, return a lightweight marker map (`{_circular_ref: true, _ref_target: ref}`). `SchemaParser` recognizes these markers and creates `ApiSchema` stubs with `isCircularRef: true`.
  - **Error handling:** Missing `$ref` targets emit a `Diagnostic` warning and return null (soft failure), consistent with remote URL handling. Shared marker key constants (`circularRefMarker`, `refTargetMarker`) prevent magic string drift between `RefResolver` and `SchemaParser`.
  - **Precondition:** `rootSchema` must contain mutable `Map<String, dynamic>` / `List<dynamic>` instances because `resolveAll` replaces map values in place. Callers must convert YAML/JSON to mutable maps first.
  - Notes: **Highest complexity task in the entire project.** Handle: refs-to-refs, cross-file refs via `FileReader` callback, relative path resolution against `basePath`. Test extensively against Stripe spec.

- [x] Task 11: Implement schema parser (components/schemas → IR)
  - File: `packages/dart_open_fetch_core/lib/src/parser/schema_parser.dart` (create)
  - Action: Parse `components.schemas` into `ApiSchema` IR nodes using a **pointer-sharing registry**. Each component schema is parsed exactly once into `ApiSchema` and the same instance is returned for every `$ref` that targets it. Handle all schema types: primitives, objects (with `properties` + `required`), arrays (with `items`), **`additionalProperties` (→ `Map<String, T>` where T is the additionalProperties schema, or `Map<String, dynamic>` if `true`/absent)**, enums (preserve raw string values), `allOf` (**flatten all member properties into single schema; deduplicate same-name-same-type; use `dynamic` + warn on type conflict**), `oneOf` (union with optional discriminator mapping), `anyOf` (union), format hints, default values, nullable, `deprecated` flag.
  - **Pointer-sharing registry:** Three internal fields — `_rawSchemas` (raw maps, zero copy), `_schemaCache` (parsed `ApiSchema` instances), `_parsing` (circular detection set). `parseComponents()` populates `_rawSchemas` then parses each through `_parseComponentSchema(name)` which checks cache → checks circular → parses → caches. `parseSchema()` detects `$ref` nodes at the top and resolves via the registry. See: [`refactor-ref-resolver-pointer-sharing.md`](./refactor-ref-resolver-pointer-sharing.md).
  - **Circular reference strategy:** `_parsing` set tracks schemas currently being parsed. When re-encountered during a parse tree walk (A→B→A), returns a shared stub from `_circularStubs` cache with `isCircularRef: true` and `refTarget: name`. The code generator detects these stubs and generates the field type normally — Dart classes can reference each other without issue.
  - **Idempotent:** `parseComponents()` clears all internal state on each call, safe to call multiple times. Parse failures are cached as `dynamic_` fallbacks with diagnostics to prevent infinite retry loops.
  - Notes: `allOf` flattening, NOT inheritance. If `allOf` member A has property `id: string` and member B has property `id: string`, deduplicate. If A has `id: string` and B has `id: integer`, emit `id: dynamic` and log `Diagnostic`. Free-form objects (`type: object` with no properties, no additionalProperties) → `Map<String, dynamic>`. Objects with both `properties` AND `additionalProperties` get named fields plus an `Map<String, dynamic> additionalProperties` field. Unrecognized schema type strings emit a diagnostic warning.

- [x] Task 12: Implement paths/operations parser
  - File: `packages/dart_open_fetch_core/lib/src/parser/path_parser.dart` (create)
  - Action: Parse `paths` into `ApiPath` and `ApiOperation` IR nodes. Extract: HTTP method, operationId, summary, `deprecated` flag, parameters (path/query/header/cookie with `style`/`explode` values), request body (with content types), responses (by status code with content types), security requirements, tags. If `operationId` is missing, generate one from method + path (e.g., `get_/users/{id}` → `getUsersById`).
  - Notes: Parameters can be defined at path level or operation level — merge both, operation-level overrides path-level for same-name params. Parse `style` and `explode` from parameters into IR for serialization handling in code generator. Default `style` for path params is `simple`, for query params is `form` with `explode: true`.

- [x] Task 13: Implement info and server parser
  - File: `packages/dart_open_fetch_core/lib/src/parser/info_parser.dart` (create)
  - Action: Parse `info` into `ApiInfo` (title, version, description). Parse `servers` array to extract base URL(s). For server variables (`{environment}` in URL templates), resolve using the variable's `default` value to produce a static URL string. Store resolved URLs in `ApiInfo.servers` as `List<String>`.
  - Notes: v0.1 resolves server variables statically at parse time using defaults. Runtime variable substitution deferred to v0.2. The generated client takes a `baseUrl` constructor param defaulting to the first resolved server URL. `--base-url` CLI flag overrides this at generation time.

- [x] Task 14: Implement security schemes parser
  - File: `packages/dart_open_fetch_core/lib/src/parser/security_parser.dart` (create)
  - Action: Parse `components.securitySchemes` into `ApiSecurityScheme` IR nodes. Handle apiKey (header/query/cookie), http (bearer/basic), oauth2 (flows), openIdConnect.
  - Notes: v0.1 parses these into IR for the typed client signature. Actual auth middleware implementations are v0.2.

- [x] Task 15: Implement top-level parser orchestrator
  - File: `packages/dart_open_fetch_core/lib/src/parser/openapi_parser.dart` (create)
  - Action: Orchestrate the full parse pipeline: validate → detect version → normalize → resolve refs → parse schemas → parse paths → parse info → parse security → assemble `ApiSpec` IR root. Collect all `Diagnostic`s during parsing into a warnings list returned alongside the `ApiSpec`. Fatal errors (`SchemaParseException`, `RefResolutionException`) propagate immediately.
  - Notes: Constructor: `OpenApiParser({required FileReader fileReader})`. Entry point: `ParseResult parse(Map<String, dynamic> rawSchema, {required String basePath})` where `ParseResult` contains `ApiSpec spec` and `List<Diagnostic> warnings`. The `FileReader` callback is used by the `$ref` resolver for relative file resolution.

- [x] Task 16: Write parser unit tests
  - File: `packages/dart_open_fetch_core/test/parser/schema_parser_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/parser/path_parser_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/parser/ref_resolver_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/parser/version_detector_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/parser/openapi_parser_test.dart` (create)
  - Action: Test each parser component against fixture schemas. Petstore for basic coverage, GitHub for medium complexity, Stripe for stress test. Test `$ref` cycles, `allOf` merging, `oneOf` discriminators, nullable handling for both 3.0 and 3.1 styles.
  - Notes: Red-green-refactor against real schemas. If Stripe parses clean, the parser is solid.

### Milestone 3: Code Generator (IR → Dart)

- [ ] Task 17: Implement model generator (ApiSchema → Dart classes)
  - File: `packages/dart_open_fetch_core/lib/src/generator/model_generator.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/generator/name_resolver.dart` (create)
  - Action: Walk `ApiSchema` IR nodes and emit Dart classes via `code_builder`. Generate: class with final fields, constructor, `fromJson` factory, `toJson` method, `copyWith` (using `_Undefined` sentinel for nullable field disambiguation), `==`/`hashCode`, `toString`. Handle:
    - Nested objects, lists, `Map` types (from `additionalProperties`)
    - Objects with both `properties` AND `additionalProperties` (named fields + extra map field)
    - Free-form objects → `Map<String, dynamic>`
    - Enums: Dart enum with sanitized member names (`in-progress` → `inProgress`, `404` → `value404`, reserved words appended with `$`). `fromJson`/`toJson` use original string values.
    - Nullable fields, default values
    - `@Deprecated()` annotations for `deprecated: true` schemas/properties
    - **Name resolution** (`name_resolver.dart`): detect and resolve class name collisions (append numeric suffix), reserved word collisions (append `$`), file name collisions on case-insensitive systems. Log warnings for all name transformations.
  - Notes: Use `Code()` blocks for `fromJson`/`toJson` body expressions. Class names match schema names unless collision forces suffix. One file per model.

- [ ] Task 18: Implement union type generator (oneOf/anyOf)
  - File: `packages/dart_open_fetch_core/lib/src/generator/union_generator.dart` (create)
  - Action: Generate sealed class hierarchies for `oneOf`/`anyOf` schemas using Dart 3 sealed classes.
    - **With discriminator:** Generate a factory `fromJson` that reads the discriminator field, switches on its value using the discriminator mapping, and constructs the correct subclass. Unknown discriminator values throw `FormatException`.
    - **Without discriminator (ordered try-parse):** Generate a factory `fromJson` that attempts deserialization of each variant in schema-defined order. Each variant's `fromJson` must throw `FormatException` on type mismatch. First successful parse wins. If all variants fail, throw `FormatException` listing all attempted types and their errors.
  - Notes: Dart 3 sealed classes + pattern matching for exhaustive switches. `anyOf` uses same try-parse strategy as `oneOf` without discriminator (semantically similar for code generation). Variant subclass names derived from referenced schema names (e.g., `sealed class PetOrError` with `class PetOrErrorPet extends PetOrError`).

- [ ] Task 19: Implement client generator (ApiOperation → typed methods)
  - File: `packages/dart_open_fetch_core/lib/src/generator/client_generator.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/generator/parameter_serializer.dart` (create)
  - Action: Generate a typed client class with one method per `ApiOperation`. Method signature includes: typed path/query/header parameters, typed request body (JSON only), return type from response schema.
    - **Constructor:** Takes `HttpAdapter adapter` (required) and `List<Middleware> middleware` (optional, defaults to `[]`). Internally constructs a `MiddlewareChain` stored as `_chain` private field.
    - **Method body:** Serialize path params via simple string interpolation (default `style: simple`). Serialize query params via `Uri` query encoding (default `style: form, explode: true`). Non-default param styles use default serialization + log warning during generation. Set `Content-Type: application/json` header for requests with body. Call `_chain.send(request)`. Deserialize response: check for `application/json` in response content types — if present, use that schema's model `fromJson`. If response has no JSON content type, return raw `HttpResponse`.
    - **`@Deprecated()` annotations** on methods for deprecated operations.
    - Group methods by tag into separate client classes if multiple tags exist.
    - **Parameter serializer** (`parameter_serializer.dart`): generates code for path param interpolation and query param encoding. v0.1 supports `style: simple` (path) and `style: form, explode: true` (query) only.
  - Notes: Method names from `operationId` (or derived from method + path). Name collision resolution via `name_resolver.dart`. Non-JSON request bodies are out of scope — operations with only non-JSON request content types get a method that accepts raw `String` body.

- [ ] Task 20: Implement file writer and output coordinator
  - File: `packages/dart_open_fetch_core/lib/src/generator/output_writer.dart` (create)
  - Action: Coordinate generated code output: one file per model (`models/`), one file per client class (`clients/`), one barrel export file. Apply `DartFormatter` to all output. Add generation header comment to each file (source schema, timestamp, tool version).
  - Notes: Output directory structure: `{output}/models/*.dart` (plain models + enums), `{output}/models/*.dart` (union sealed classes — same directory as models, one file per sealed class hierarchy containing base + all variants), `{output}/clients/*.dart`, `{output}/{package_name}.dart` (barrel). Union types live alongside models in `models/` since they are data types consumed the same way.

- [ ] Task 21: Implement top-level generator orchestrator
  - File: `packages/dart_open_fetch_core/lib/src/generator/dart_generator.dart` (create)
  - Action: Orchestrate: take `ApiSpec` IR → generate models → generate unions → generate clients → generate barrel → write files. Single entry point: `Future<GenerateResult> generate(ApiSpec spec, String outputDir, {String? baseUrlOverride})` where `GenerateResult` contains `List<String> filesWritten` and `List<Diagnostic> diagnostics` (warnings from name collisions, unsupported param styles, non-JSON content types, etc.). The optional `baseUrlOverride` replaces the first server URL in the IR for the generated client's default base URL.
  - Notes: Composes model, union, and client generators. Formatting and file writing delegated to `OutputWriter`. Async because file writing is I/O.

- [x] Task 21b: Create core package barrel exports and shared types
  - File: `packages/dart_open_fetch_core/lib/dart_open_fetch_core.dart` (create)
  - File: `packages/dart_open_fetch_core/lib/src/types.dart` (create)
  - Action: Create barrel export for core package exporting: `OpenApiParser`, `DartGenerator`, `ParseResult`, `GenerateResult`, `Diagnostic`, `DiagnosticSeverity`, all error classes, and the `FileReader` typedef. Define `FileReader` typedef, `ParseResult`, and `GenerateResult` in `types.dart`.
  - Notes: CLI imports from this barrel. `FileReader` is `typedef FileReader = Future<Map<String, dynamic>> Function(String relativePath)` where `relativePath` is relative to the `basePath` — the caller (CLI) resolves it against the file system.

- [ ] Task 22: Write golden file tests for code generator
  - File: `packages/dart_open_fetch_core/test/generator/model_generator_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/generator/client_generator_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/generator/union_generator_test.dart` (create)
  - File: `packages/dart_open_fetch_core/test/goldens/petstore/` (create directory)
  - Action: Generate from fixture schemas, compare against golden files. Test model generation (simple object, nested object, enum, nullable fields, array properties), client generation (GET/POST/PUT/DELETE, path params, query params, request body, typed response), union generation (sealed class with discriminator, without discriminator).
  - Notes: Implement `--update-goldens` support via environment variable (`UPDATE_GOLDENS=true dart test`). All generated golden files must pass `dart analyze`.

- [ ] Task 23: Verify generated code compiles
  - File: `packages/dart_open_fetch_core/test/generator/compile_test.dart` (create)
  - Action: Integration test that generates code from Petstore spec into a temp directory, runs `dart analyze` on the output, and asserts zero errors/warnings.
  - Notes: This is the "generated code actually works" gate. Run against all fixture schemas.

### Milestone 4: CLI Shell

- [ ] Task 24: Implement CLI entry point
  - File: `packages/dart_open_fetch/bin/dart_open_fetch.dart` (create)
  - File: `packages/dart_open_fetch/lib/src/cli_runner.dart` (create)
  - Action: Set up `package:args` with `generate` command. Arguments: positional `<schema>` (URL or file path), `-o`/`--output` (output directory, defaults to `lib/api/`), `--base-url` (override server URL — passed as `baseUrlOverride` to `DartGenerator.generate()`). Parse args, invoke core parser then generator.
  - Notes: Entry point in `bin/` for `dart pub global activate dart_open_fetch`. Add `executables` section to `pubspec.yaml`. The `--base-url` flag is passed through to `DartGenerator.generate(spec, outputDir, baseUrlOverride: baseUrl)` which overrides the first server URL in the generated client's default configuration.

- [ ] Task 25: Implement schema fetcher and loader (URL + file → Map)
  - File: `packages/dart_open_fetch/lib/src/schema_fetcher.dart` (create)
  - Action: Detect if schema argument is URL (starts with `http://` or `https://`) or file path. If URL, fetch content string via `package:http`. If file, read content string via `dart:io`. Detect format (JSON if starts with `{`, otherwise YAML). Parse to `Map<String, dynamic>` via `dart:convert` or `package:yaml`. Pass the parsed map + base directory path to `core`'s `OpenApiParser.parse()`. Also provide a `FileReader` callback implementation that reads relative files from disk (for `$ref` resolution).
  - Notes: **No temp file round-trip.** The CLI reads/fetches → parses → passes `Map<String, dynamic>` directly to core. **YAML deep conversion required:** `package:yaml`'s `loadYaml()` returns `YamlMap`/`YamlList`, not plain `Map<String, dynamic>`/`List`. The CLI must deep-convert YAML output to plain Dart maps/lists before passing to core (recursive conversion: `YamlMap` → `Map<String, dynamic>`, `YamlList` → `List<dynamic>`). Without this, `is Map<String, dynamic>` type checks in core will fail on `YamlMap` instances. The CLI also implements the `FileReader` callback for relative `$ref` resolution (must also deep-convert YAML in returned maps). For URL-based schemas, `basePath` is set to CWD (relative file refs from remote schemas are unsupported in v0.1). Handle HTTP errors (404, timeout, non-2xx) with clear messages.

- [ ] Task 26: Implement progress reporter
  - File: `packages/dart_open_fetch/lib/src/progress_reporter.dart` (create)
  - Action: Emit progress messages to stdout: `Fetching schema...`, `Parsing schema...`, `Resolving references...`, `Generating N models...`, `Generating N clients...`, `Writing files to {output}...`, `Done.`
  - Notes: Keep it simple — print statements. No fancy progress bars for v0.1.

- [ ] Task 27: Create GitHub Actions CI pipeline
  - File: `.github/workflows/ci.yaml` (create)
  - Action: Create CI workflow that runs on push/PR: `melos bootstrap`, `melos run analyze` (dart analyze all packages), `melos run test` (dart test all packages), `melos run format-check` (dart format --set-exit-if-changed). Configure melos scripts in `melos.yaml` for these commands.
  - Notes: Fixture schemas are committed to repo, not downloaded in CI. CI runs against the committed golden files. No special matrix needed — single Dart SDK version (latest stable 3.x).

- [ ] Task 28: Write CLI integration tests
  - File: `packages/dart_open_fetch/test/cli_runner_test.dart` (create)
  - File: `packages/dart_open_fetch/test/schema_fetcher_test.dart` (create)
  - Action: Test CLI arg parsing (valid args, missing args, invalid schema path). Test schema fetcher with local file. Test end-to-end: run CLI against Petstore fixture, verify output directory contains expected files, verify generated code compiles.
  - Notes: Use process runner to test actual CLI invocation in integration tests.

### Acceptance Criteria

**Milestone 1 — Scaffolding + IR + Runtime:**

- [ ] AC 1: Given a fresh clone, when `melos bootstrap` is run, then all three packages resolve dependencies without errors
- [ ] AC 2: Given the IR classes, when an `ApiSpec` is constructed manually, then all fields are accessible and the object graph is traversable
- [ ] AC 3: Given a mock `HttpAdapter` and two test `Middleware` instances, when a request is sent through the `MiddlewareChain`, then middleware executes in order (first added = first to handle) and the response flows back through the chain
- [ ] AC 4: Given an empty middleware list, when a request is sent through `MiddlewareChain`, then the request goes directly to the `HttpAdapter`

**Milestone 2 — Parser:**

- [ ] AC 5: Given the Petstore OpenAPI 3.0 YAML spec, when parsed, then the resulting `ApiSpec` contains all paths, operations, schemas, and parameters matching the spec
- [ ] AC 6: Given the GitHub OpenAPI spec, when parsed, then all `$ref` references are resolved correctly including cross-component refs
- [ ] AC 7: Given the Stripe OpenAPI spec (~80k lines), when parsed, then parsing completes without errors and all `allOf` compositions are correctly merged
- [ ] AC 8: Given a schema with `nullable: true` (3.0 style), when parsed, then the IR `ApiSchema` has `nullable = true`
- [ ] AC 9: Given a schema with `type: [string, "null"]` (3.1 style), when parsed, then the IR `ApiSchema` has `nullable = true` and base type `string`
- [ ] AC 10: Given a schema with circular `$ref` (A refs B, B refs A), when parsed, then the parser detects the cycle and breaks it without stack overflow
- [ ] AC 11: Given a multi-file schema with relative `$ref` paths, when parsed, then all cross-file references resolve correctly
- [ ] AC 12: Given a schema with `oneOf` and a discriminator, when parsed, then the IR `ApiSchema` captures the discriminator property name and mapping

**Milestone 3 — Code Generator:**

- [ ] AC 13: Given a Petstore `ApiSpec` IR, when the generator runs, then output contains one `.dart` file per schema model in `models/` directory
- [ ] AC 14: Given a generated model class, when `fromJson` is called with valid JSON matching the schema, then all fields are correctly deserialized including nested objects, lists, and nullable fields
- [ ] AC 15: Given a generated model instance, when `toJson` is called, then the output JSON round-trips correctly (`fromJson(instance.toJson()) == instance`)
- [ ] AC 16: Given a schema with an enum property, when generated, then a Dart enum is created with `fromJson`/`toJson` support and correct values
- [ ] AC 17: Given a `oneOf` schema with discriminator, when generated, then a Dart sealed class hierarchy is produced with a factory `fromJson` that dispatches on the discriminator field
- [ ] AC 18: Given a generated client class, when a method is called with typed parameters, then it constructs the correct `HttpRequest` (URL, method, headers, body) and passes it through the middleware chain
- [ ] AC 19: Given generated code from any fixture schema, when `dart analyze` is run, then zero errors and zero warnings are reported
- [ ] AC 20: Given generated code from any fixture schema, when `dart format --set-exit-if-changed` is run, then no formatting changes are needed
- [ ] AC 21: Given generated files, when inspected, then each file contains a header comment with source schema, generation timestamp, and tool version
- [ ] AC 22: Given golden files for Petstore, when the generator output is compared, then it matches exactly (or `--update-goldens` regenerates them)

**Milestone 3 — Code Generator (additional):**

- [ ] AC 23: Given a schema with `additionalProperties: { type: string }`, when generated, then the model contains a `Map<String, String>` field with correct `fromJson`/`toJson` handling
- [ ] AC 24: Given a free-form object schema (no properties, no additionalProperties), when generated, then the type is `Map<String, dynamic>`
- [ ] AC 25: Given a schema with both named `properties` and `additionalProperties`, when generated, then the model has named fields plus a `Map<String, dynamic> additionalProperties` field
- [ ] AC 26: Given an enum with values `["in-progress", "404", "class", ""]`, when generated, then enum members are valid Dart identifiers (`inProgress`, `value404`, `class$`, `empty`) and `fromJson`/`toJson` use original string values
- [ ] AC 27: Given two schemas with the same name from different `$ref` paths, when generated, then the second gets a numeric suffix and a warning is logged
- [ ] AC 28: Given a schema property with `deprecated: true`, when generated, then the Dart field has an `@Deprecated()` annotation
- [ ] AC 29: Given a model with nullable field `String? name`, when `copyWith(name: null)` is called, then `name` is set to null; when `copyWith()` is called without `name`, then `name` is unchanged
- [ ] AC 30: Given an `allOf` where two members define `id: string` and `id: integer`, when parsed, then the IR uses `dynamic` for `id` and an `Diagnostic` is logged
- [ ] AC 31: Given an operation with `style: pipeDelimited` on a query param, when generated, then default `form` serialization is used and a warning is logged during generation

**Milestone 3 — Error Handling:**

- [ ] AC 32: Given a Swagger 2.0 schema (has `swagger` field instead of `openapi`), when parsed, then a `SchemaParseException` is thrown with message mentioning "Swagger 2.0 is not supported"
- [ ] AC 33: Given a schema with a `$ref` pointing to a non-existent path, when parsed, then a `RefResolutionException` is thrown with the JSON pointer path to the broken ref
- [ ] AC 34: Given a schema with a remote URL `$ref`, when parsed, then an `Diagnostic` is logged and the ref is skipped
- [ ] AC 35: Given a schema with `multipart/form-data` as the only request content type, when generated, then the method accepts a raw `String` body and a warning is logged

**Milestone 3 — Round 2 findings:**

- [ ] AC 42: Given a generated client method for an operation with 200 and 404 responses, when the server returns 200, then `ApiResponse<T>` is returned with deserialized `data`; when the server returns 404, then `ApiException` is thrown with statusCode 404 and raw body
- [ ] AC 43: Given an `HttpRequest` instance, when `headers['injected'] = 'value'` is attempted, then an `UnsupportedError` is thrown (headers are unmodifiable)
- [ ] AC 44: Given an `anyOf` schema with two variants, when generated, then a sealed class hierarchy is produced with try-parse `fromJson` (same as `oneOf` without discriminator)
- [ ] AC 45: Given an OpenAPI 3.1 schema with `type: [string, integer]`, when parsed, then the IR normalizes this to a `oneOf` with string and integer variants
- [ ] AC 46: Given an operation with no tags, when generated, then the method is placed in `DefaultClient`
- [ ] AC 47: Given an operation with tags `["pets", "admin"]`, when generated, then the method appears in `PetsClient` only (first tag wins)
- [ ] AC 48: Given a server URL template `https://{env}.api.com` with default `env: production`, when parsed, then `ApiInfo.servers` contains `https://production.api.com`
- [ ] AC 49: Given base URL `https://api.com/v1/` and path `/users/{id}` with id=`42`, when URL is constructed, then the result is `https://api.com/v1/users/42` (normalized slashes)
- [ ] AC 50: Given two model instances with identical field values, when `==` is called, then it returns true; when `hashCode` is called on both, then values are equal
- [ ] AC 51: Given a YAML schema loaded by the CLI, when passed to core parser, then all nested maps are plain `Map<String, dynamic>` (not `YamlMap`) and type checks work correctly
- [ ] AC 52: Given `--base-url https://custom.api.com` CLI flag, when code is generated, then the generated client's default base URL is `https://custom.api.com` instead of the schema's server URL

**Milestone 4 — CLI:**

- [ ] AC 36: Given a local Petstore YAML file, when `dart_open_fetch generate ./petstore.yaml -o lib/api/` is run, then generated Dart files appear in `lib/api/` and compile cleanly
- [ ] AC 37: Given an invalid file path, when `dart_open_fetch generate ./nonexistent.yaml` is run, then a clear error message is displayed: "Error: File not found: ./nonexistent.yaml"
- [ ] AC 38: Given a schema URL, when `dart_open_fetch generate https://...` is run, then the schema is fetched, parsed, and code is generated to the default output directory
- [ ] AC 39: Given a large schema (Stripe), when the CLI runs, then progress messages are printed to stdout showing each phase (fetching, parsing, resolving, generating, writing)
- [ ] AC 40: Given `dart pub global activate dart_open_fetch`, when `dart_open_fetch generate` is run from any directory, then the CLI executes correctly as a globally installed tool
- [ ] AC 41: Given the CI pipeline on a fresh clone, when triggered, then all packages analyze clean, all tests pass, and formatting check passes

## Additional Context

### Dependencies

**Core package (`dart_open_fetch_core`):**
- `dart:convert` (built-in)
- `package:yaml` — YAML schema parsing
- `package:code_builder` — Structured Dart code generation with `DartEmitter.scoped()` for automatic import management. Note: `code_builder` has transitive dependencies on `package:built_value` and `package:built_collection`. These only affect the core dev-time package, not the runtime or generated code. Pin `code_builder` version in `pubspec.yaml` to avoid transitive conflicts.
- `package:dart_style` — `DartFormatter` for formatting generated output
- `package:collection` — `MapEquality` for IR/runtime value class equality

**CLI package (`dart_open_fetch`):**
- `package:args` — CLI argument parsing
- `package:http` — Schema fetching from URLs
- `dart_open_fetch_core` — Parser + code generator

**Runtime package (`dart_open_fetch_runtime`):**
- `package:collection` — `MapEquality` for `HttpRequest`/`HttpResponse` value equality (sole external dependency — lightweight, maintained by dart-lang)

**Dev dependencies (all packages):**
- `package:test` — Dart test framework
- `package:melos` — Mono-repo workspace management
- `package:lints` — Recommended lint rules

**SDK constraint (all packages):**
- `environment: sdk: '>=3.0.0 <4.0.0'` — Dart 3.0+ required for sealed classes and pattern matching

### Testing Strategy

**Tier 1 — High risk, test heavily:**
- Schema parser correctness: feed real-world OpenAPI specs (Stripe, GitHub, Petstore) and validate the IR. Edge cases in `$ref` resolution, `allOf`/`oneOf`/`anyOf` composition, nullable types.
- Generated code compilation: every generated output MUST `dart analyze` clean with zero warnings.

**Tier 2 — Medium risk:**
- Code generator output: golden file / snapshot tests. Generate from known schemas, compare output against golden files in `test/goldens/`. Catches regressions fast.
- Middleware chain ordering and execution: unit tests with mock adapters.

**Tier 3 — Lower risk but valuable:**
- CLI integration tests: run actual CLI against fixture schemas, verify generated files exist and compile.
- End-to-end: generate client from a live test server, make real HTTP calls, validate responses deserialize correctly.

**Test Corpus:** Download and **commit** into `test/fixtures/` on day one — version-pinned for reproducibility. Write the parser against them from the start (red-green-refactor):
- **Petstore** — Hello-world baseline, simple CRUD (pinned to OAI/OpenAPI-Specification main branch example)
- **GitHub** — Medium complexity, good `$ref` coverage (pinned to specific tagged release from `github/rest-api-description`)
- **Stripe** — ~80k lines, extensive `allOf`, deeply nested `$ref` chains, polymorphic types with discriminators (pinned to specific tagged release from `stripe/openapi`). **If the parser handles Stripe, it handles everything.** Introduce early, not late.
- Include a `test/fixtures/README.md` documenting exact source URLs, commit hashes, and download dates for each fixture
- When updating fixtures, update golden files simultaneously

**Golden File Strategy:**
- Golden files in `test/goldens/{schema_name}/` with expected generated output
- Implement `--update-goldens` flag on test runner from the start to allow mass-updating golden files when the emitter improves intentionally
- Without this, every emitter improvement breaks every golden file and maintenance becomes a nightmare

**Quality Gates:**
1. Parser passes on all fixture schemas
2. Generated code analyzes clean (`dart analyze`)
3. Generated client makes successful typed calls against a mock server
4. Runtime interfaces (adapter/middleware) covered by unit tests

### Notes

- Inspired by [openapi-fetch](https://openapi-ts.dev/openapi-fetch/) (TypeScript) — lightweight, native, type-safe
- Existing Dart alternatives evaluated: openapi_generator (Java-heavy), openapi_retrofit_generator (opinionated deps), swagger_to_dart (freezed/retrofit coupling)
- Tagline: *"OpenAPI clients for Dart — no Java, no dependencies, no opinions."*
- The `HttpAdapter` + `Middleware` pattern makes generated clients trivially testable by consumers — mock the adapter, inject it, get deterministic tests without network calls
- MVP v0.1: parser + models + typed client + runtime interfaces. Middleware implementations (auth, retry, logging) come in v0.2.
- The parser is the highest-risk, highest-effort component (~60-70% of total work). It must be test-driven against real-world schemas from the start.
- IR class hierarchy is the critical path — all other work is gated behind it.
- Runtime follows semver strictly — `HttpAdapter`/`Middleware`/`HttpRequest`/`HttpResponse` interfaces are the stability contract. Breaking changes = major version bump.
- Generated code header includes `// requires: dart_open_fetch_runtime ^0.1.0` for version compatibility tracking.
