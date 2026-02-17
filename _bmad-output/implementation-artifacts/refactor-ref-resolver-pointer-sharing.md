# Refactor RefResolver: Pointer-Sharing Schema Registry (OOM Fix)

## Context

The OpenAPI parser test crashes with OOM on large specs (GitHub 8.6MB/907 schemas, Stripe 5.8MB/1321 schemas). Root cause: `RefResolver._resolveRef()` calls `_deepConvert(target)` for each of the ~9,377 `$ref`s in GitHub, creating massive memory duplication. This is the **#1 documented cause of OOM** across the OpenAPI tooling ecosystem (swagger-parser, Redoc, Spectral all have the same issue).

The fix follows **ogen's pointer-sharing approach**: parse each component schema exactly once into an `ApiSchema` registry, and share the same instance everywhere it's referenced. Memory drops from `O(refs * schema_size)` to `O(unique_schemas)`.

## Research: How Other Tools Solve This

| Tool | Language | Strategy | Memory |
|---|---|---|---|
| **swagger-parser** | Java | Full inline (`resolveFully`) | Poor -- deep copies at every usage site; OOM common |
| **openapi-generator** | Java | Flatten via `InlineModelResolver` | Moderate -- deduplicates via `matchGenerated()` |
| **openapi-typescript v7** | TypeScript | Bundle (Redocly) then walk | Good -- bundling without full expansion |
| **json-schema-ref-parser** | JavaScript | Object identity sharing (`dereference`) | Good -- pointer sharing, no deep copies |
| **ogen** | Go | Pointer-sharing via `refcache` | Very Good -- each schema parsed once, shared via pointer |
| **OpenAPI.NET v2 / Kiota** | C# | Lazy proxy objects | Excellent -- 35% less memory, proxies are lightweight |
| **Speakeasy** | Go | Lazy intermediate representation | Excellent -- 1.5-2.8x less than competitors |

Our current approach matches swagger-parser's `resolveFully` -- the worst performing strategy. The fix adopts ogen's `refcache` approach -- the best balance of simplicity and performance.

## Architecture Change

**Before:** `RefResolver` deep-copies every `$ref` target into the raw map tree -> `SchemaParser` parses the inlined maps into `ApiSchema`

**After:** `RefResolver` skips component schema `$ref`s (leaves them as-is) -> `SchemaParser` resolves them at the IR level via a registry cache

```
BEFORE:                                 AFTER:

Raw YAML Map                            Raw YAML Map
     |                                       |
     v                                       v
RefResolver                             RefResolver (simplified)
  - deep-copy ALL $ref targets            - resolve only non-schema $refs
  - resolve circular refs                 - leave schema $refs as-is
  - cache resolved copies                      |
     |                                       v
     v                                  SchemaParser (enhanced)
SchemaParser                              - detect $ref in parseSchema()
  - parse inlined maps                    - resolve via _schemaCache registry
  - handle _circular_ref markers          - circular detection via _parsing set
     |                                    - each schema parsed ONCE
     v                                       |
ApiSchema IR (lots of copies)                v
                                        ApiSchema IR (shared instances)
```

## Implementation Steps

### Step 1: Add registry + `$ref` handling to `SchemaParser`

**File:** `lib/src/parser/schema_parser.dart`

Add three fields to the class:

```dart
/// Raw component schema maps (pointers into rootSchema, zero copy).
final Map<String, Map<String, dynamic>> _rawSchemas = {};

/// Parsed schema registry. Each component schema is parsed at most once.
final Map<String, ApiSchema> _schemaCache = {};

/// Schema names currently being parsed (for circular detection).
final Set<String> _parsing = {};
```

Rewrite `parseComponents()`:

```dart
List<ApiSchema> parseComponents(Map<String, dynamic> schema) {
  final components = schema['components'] as Map<String, dynamic>?;
  if (components == null) return [];

  final schemas = components['schemas'] as Map<String, dynamic>?;
  if (schemas == null) return [];

  // Store raw schemas for on-demand parsing via the registry.
  for (final entry in schemas.entries) {
    _rawSchemas[entry.key] = entry.value as Map<String, dynamic>;
  }

  // Parse each component schema through the cache.
  return schemas.keys.map((name) => _parseComponentSchema(name)).toList();
}
```

Add `_parseComponentSchema()` -- the core registry method:

```dart
/// Parse a component schema by name, using cache for deduplication.
ApiSchema _parseComponentSchema(String name) {
  // Return cached result if already parsed.
  if (_schemaCache.containsKey(name)) {
    return _schemaCache[name]!;
  }

  // Circular detection: if we're already parsing this schema,
  // return a stub that code generation resolves by name.
  if (_parsing.contains(name)) {
    return ApiSchema(
      name: name,
      type: SchemaType.object,
      isCircularRef: true,
      refTarget: name,
      schemaPath: '#/components/schemas/$name',
    );
  }

  final raw = _rawSchemas[name];
  if (raw == null) {
    diagnostics.add(Diagnostic(
      message: 'Referenced component schema "$name" not found',
      schemaPath: '#/components/schemas/$name',
      severity: DiagnosticSeverity.warning,
    ));
    return ApiSchema(
      name: name,
      type: SchemaType.dynamic_,
      schemaPath: '#/components/schemas/$name',
    );
  }

  _parsing.add(name);
  try {
    final result = parseSchema(
      raw,
      name: name,
      path: '#/components/schemas/$name',
    );
    _schemaCache[name] = result;
    return result;
  } finally {
    _parsing.remove(name);
  }
}
```

Add `$ref` detection at the top of `parseSchema()`:

```dart
ApiSchema parseSchema(
  Map<String, dynamic> node, {
  String? name,
  String? path,
}) {
  // Handle unresolved component schema $ref (left by RefResolver).
  if (node.containsKey(r'$ref')) {
    final ref = node[r'$ref'] as String;
    if (ref.startsWith('#/components/schemas/')) {
      final targetName = ref.substring('#/components/schemas/'.length);
      return _parseComponentSchema(targetName);
    }
    // Non-schema $ref should have been resolved by RefResolver.
    diagnostics.add(Diagnostic(
      message: 'Unresolved \$ref: $ref',
      schemaPath: path,
      severity: DiagnosticSeverity.warning,
    ));
    return ApiSchema(name: name, type: SchemaType.dynamic_, schemaPath: path);
  }

  // Handle circular ref markers from RefResolver (non-schema refs only)
  if (node['_circular_ref'] == true) {
    // ... existing code ...
  }

  // ... rest of existing parseSchema code unchanged ...
}
```

**Why allOf still works:** When `_parseAllOf` encounters a `$ref` member, `parseSchema` resolves it to the full cached `ApiSchema` with all properties. The merge reads `memberSchema.properties` from the cached instance. No deep copy needed.

**Why circular refs work:**

```
Schema A -> B -> A:

1. _parseComponentSchema('A')
   _parsing = {A}

2. Parsing A finds $ref to B
   _parseComponentSchema('B')
   _parsing = {A, B}

3. Parsing B finds $ref to A
   _parsing.contains('A') == true
   -> return ApiSchema(isCircularRef: true, refTarget: 'A')

4. B finishes parsing (with circular stub for A), cached
   _parsing = {A}

5. A finishes parsing (with full B), cached
   _parsing = {}
```

### Step 2: Simplify `RefResolver` -- skip component schema `$ref`s

**File:** `lib/src/parser/ref_resolver.dart`

In `_resolveRef()`, add early return after the remote URL check:

```dart
Future<Map<String, dynamic>?> _resolveRef(String ref, String path) async {
  // Remote URL refs
  if (ref.startsWith('http://') || ref.startsWith('https://')) {
    // ... existing diagnostic ...
    return null;
  }

  // Component schema refs are resolved at IR level by SchemaParser.
  // Leave them as-is in the map tree to avoid expensive deep-copy.
  if (ref.startsWith('#/components/schemas/')) {
    return null;
  }

  // ... rest of existing resolution for non-schema refs ...
}
```

Returning `null` causes `_resolveNode` to leave the `{"$ref": "..."}` map in place (lines 99-101 already check `if (resolved != null)`).

In `resolveAll()`, remove the component schema resolution loop:

```dart
Future<Map<String, dynamic>> resolveAll() async {
  // Main tree walk -- resolves non-schema $refs in paths, parameters, etc.
  await _resolveNode(rootSchema, '#', skipComponentSchemas: true);
  // Component schemas stay as raw maps; SchemaParser resolves them at IR level.
  return rootSchema;
}
```

Remove the constructor's `_deepConvert` call:

```dart
RefResolver({
  required this.rootSchema,  // Was: rootSchema = _deepConvert(rootSchema)
  required this.basePath,
  required this.fileReader,
});
```

Keep `_deepConvert` static method -- still used for per-target copies of non-schema refs (parameters, responses -- these are small).

Remove unused `_markCircularRefs` / `_markCircularRefsInList` methods.

### Step 3: Files that need NO changes

- **`api_schema.dart`** -- `isCircularRef` + `refTarget` stay as-is (now only for actual circular refs)
- **`model_generator.dart`** -- already handles circular stubs via `refTarget` (line 457) and named schemas via `schema.name` (line 464). Non-circular refs return the cached `ApiSchema` which has `name` set, so the existing name-based branch handles it correctly.
- **`openapi_parser.dart`** -- pipeline order unchanged. `SchemaParser` instance is shared between `parseComponents()` and `PathParser.parsePaths()`, so the registry built during parseComponents is available when PathParser calls `schemaParser.parseSchema()`.
- **`path_parser.dart`** -- calls `schemaParser.parseSchema()` which now handles `$ref` nodes internally. No changes needed.

### Step 4: Update `ref_resolver_test.dart`

**File:** `test/parser/ref_resolver_test.dart`

Update 3 tests to match new behavior (component schema `$ref`s left as-is):

1. **`resolves local $ref`** -> rename to **`leaves component schema $ref for SchemaParser`** -- assert the `$ref` is preserved in the response schema map
2. **`handles circular $ref without stack overflow`** -> rename to **`leaves component schema definitions untouched`** -- assert the raw `$ref` is still in the child property map
3. **`resolves refs-to-refs`** -> rename to **`leaves ref-to-ref component schemas for SchemaParser`** -- assert PetAlias still has `$ref` key

Add 1 new test: **`resolves non-schema $ref (parameters)`** -- verify parameter `$ref`s are still resolved normally by RefResolver.

Keep **`logs diagnostic for remote URL $ref`** unchanged.

### Step 5: Add new tests to `schema_parser_test.dart`

**File:** `test/parser/schema_parser_test.dart`

Add tests in a new `$ref resolution` group:

1. **`resolves $ref to component schema`** -- call parseComponents, then parseSchema with a `$ref` node, verify it returns the correct schema with properties
2. **`$ref returns same ApiSchema instance (pointer sharing)`** -- call parseSchema twice with same `$ref`, verify `identical(a, b) == true`
3. **`handles circular $ref in component schemas`** -- Node schema with self-referencing child property, verify child's schema has `isCircularRef: true` and `refTarget: 'Node'`
4. **`allOf with $ref resolves properties from target`** -- Cat allOf [Animal ref, {color}], verify Cat has both Animal's and its own properties merged
5. **`resolves $ref-to-$ref chain`** -- PetAlias -> Pet, verify the alias resolves to Pet's properties
6. **`emits diagnostic for missing schema ref`** -- ref to non-existent schema, verify diagnostic emitted and dynamic stub returned

### Step 6: Update test fixture helper

**File:** `test/parser/openapi_parser_test.dart`

Extract YAML loading into `loadYamlFixture()` function so the raw YAML string and YamlMap tree are GC-eligible before parsing begins. (This was done in a previous edit.)

## Implementation Order

Execute in this order to keep tests passing at each step:

1. **SchemaParser** -- add registry + `$ref` handling (dormant until RefResolver changes)
2. **schema_parser_test.dart** -- add new `$ref` resolution tests (these call parseComponents + parseSchema directly)
3. **RefResolver** -- skip component schema `$ref`s, remove resolution loop, remove constructor deep-convert
4. **ref_resolver_test.dart** -- update assertions
5. **openapi_parser_test.dart** -- verify integration (fixture helper already updated)
6. **Run full test suite** -- GitHub and Stripe should no longer OOM

## Edge Cases Handled

| Case | How It's Handled |
|---|---|
| `$ref` inside `oneOf`/`anyOf` | `parseSchema` detects `$ref`, returns cached schema with `name` set |
| `$ref` in array `items` | `parseSchema` recurses into items, detects `$ref`, returns cached schema |
| `$ref` in object `properties` | Same as above -- `parseSchema` detects `$ref` in property value |
| Mutual circular (A -> B -> A) | `_parsing` set detects cycle, returns stub for the back-reference |
| Deep chains (A -> B -> C -> A) | Same -- `_parsing` catches the cycle at any depth |
| `$ref`-to-`$ref` alias | `parseSchema` resolves first `$ref`, which is itself a `$ref` map, resolves again via registry |
| Missing schema target | `_rawSchemas[name]` returns null, diagnostic emitted, `dynamic_` stub returned |
| Non-schema `$ref`s (parameters) | Still resolved by RefResolver as before (they're small) |
| External file `$ref` | Still resolved by RefResolver as before |
| Remote URL `$ref` | Still skipped by RefResolver with diagnostic |

## Memory Impact

| | Before | After |
|---|---|---|
| rootSchema map | ~50MB (GitHub) | ~50MB (same, temporary) |
| Deep-converted copy | ~50MB | **0** (removed) |
| Resolved cache (deep copies) | ~100-150MB (907 copies) | **0** (eliminated) |
| ApiSchema IR cache | ~5MB | ~5MB (shared instances) |
| **Peak total** | **~200-250MB** | **~55MB** |

## Verification

```bash
# 1. New $ref resolution tests
dart test packages/dart_open_fetch_core/test/parser/schema_parser_test.dart

# 2. Updated RefResolver tests
dart test packages/dart_open_fetch_core/test/parser/ref_resolver_test.dart

# 3. Integration tests -- GitHub/Stripe should NOT OOM
dart test packages/dart_open_fetch_core/test/parser/openapi_parser_test.dart

# 4. Full test suite
dart test packages/dart_open_fetch_core/
```

## Status: Completed

## Review Notes
- Adversarial review completed (12 findings)
- Findings: 12 total, 7 fixed, 3 skipped (noise/undecided), 2 acknowledged (correct behavior)
- Resolution approach: auto-fix

### Fixes Applied
- **F1** (Critical): Documented mutable-map precondition on RefResolver constructor
- **F2** (High): Added try-catch with error caching in `_parseComponentSchema` to prevent infinite retry
- **F3** (High): Changed `RefResolutionException` throw to diagnostic + return null for consistent soft-failure
- **F4** (High): Fixed `$ref-to-$ref` chain test to verify alias resolves to same instance via `identical()`
- **F6** (Medium): Added `circularRefMarker` / `refTargetMarker` shared constants, removed magic strings
- **F10** (Low): Added diagnostic for unrecognized schema types in `_parseType`
- **F11** (Low): Added test for `parseSchema` with `$ref` before `parseComponents`

### Skipped
- **F5** (Medium, Real): Circular stubs intentionally not cached -- they are temporary markers, full schema cached after parse completes
- **F7** (Medium, Undecided): `resolvedCircularRef` late field -- pre-existing, not introduced by this diff
- **F8** (Medium, Undecided): `parseComponents` idempotency -- currently safe (fresh SchemaParser per parse call)
- **F9** (Medium, Real): Name loss on `$ref` -- correct `$ref` semantics (target's name is the schema name)
- **F12** (Low, Noise): `ApiSchema.==` operator -- pre-existing, cache uses String keys not ApiSchema equality
