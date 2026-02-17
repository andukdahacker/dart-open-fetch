# CLAUDE.md

## Project Overview

Dart monorepo: OpenAPI 3.0/3.1 code generator producing typed HTTP clients.
Managed with **Melos 7.x** (config lives in root `pubspec.yaml`, not a separate `melos.yaml`).
Dart SDK >=3.5.0.

## Monorepo Structure

- `packages/dart_open_fetch` — CLI tool
- `packages/dart_open_fetch_core` — Parser + code generator
- `packages/dart_open_fetch_runtime` — Runtime library (users depend on this)
- `examples/dart_console/` and `examples/flutter_app/`

## Build & Test Commands

- `melos bootstrap` — install deps
- Run tests per-package: `cd packages/<pkg> && dart test`
- Analyzer per-package: `cd packages/<pkg> && dart analyze --fatal-infos`
- Format check: `cd packages/<pkg> && dart format --set-exit-if-changed .`
- Note: melos scripts may require a TTY; in non-interactive environments run commands per-package directly

## Architecture Summary

- **Parser:** YAML/JSON → RefResolver → SchemaParser/PathParser → ApiSpec (IR)
- **Generator:** ApiSpec → ModelGenerator/ClientGenerator/UnionGenerator → code_builder → dart_style → files
- **Runtime:** HttpAdapter → MiddlewareChain → Middleware → HttpRequest/HttpResponse
- Generated clients accept `adapter`, `middleware`, `baseUrl`; methods return `Future<ApiResponse<T>>`; throw `ApiException` on non-2xx

## Coding Conventions

- Linting: `package:lints/recommended.yaml`
- Must pass `dart analyze --fatal-infos` and `dart format`
- Tests use `package:test`; fixture paths are relative to the package directory (not repo root)
- Reserved runtime type names in NameResolver

## Key Entry Points

- CLI: `packages/dart_open_fetch/lib/src/cli_runner.dart`
- Parser: `packages/dart_open_fetch_core/lib/src/parser/openapi_parser.dart`
- Generator: `packages/dart_open_fetch_core/lib/src/generator/dart_generator.dart`
- Runtime exports: `packages/dart_open_fetch_runtime/lib/dart_open_fetch_runtime.dart`
