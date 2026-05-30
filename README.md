# oaisp

A code-first **OpenAPI 3.1** generator for [Wisp](https://gleam.run/wisp/)
applications on the BEAM. You write your request/response types and endpoint
declarations as ordinary Gleam code; one CLI command emits a truthful OpenAPI
document at build time.

The Gleam code is the single source of truth — the spec is a *sound projection*
of it, derived from the compiler's own resolved type information
(`gleam export package-interface`). No spec-first scaffolding, no runtime
reflection, no source re-parsing.

**Non-intrusive by design.** An endpoint points at its body/response types *by
name*; oaisp resolves their schemas from the package interface. It never sees
your decoders or encoders — your handlers stay entirely yours.

## Requirements

- **Erlang/OTP 27+** — oaisp depends on `gleam_json` 3.x, which uses the `json`
  module introduced in OTP 27.
- **Gleam 1.11+**.

## How it works

```
your Gleam types ──► gleam export package-interface ─┐
                                                      ├──► oaisp/cli merge ──► openapi.json
your endpoint declarations ──► --emit-endpoints ──────┘
```

1. You declare endpoints (method, path, params, body, responses) as values. The
   body and each response refer to a type by name with `type_ref`.
2. `oaisp.add_openapi` is a one-line hook in your `main`. At runtime it does
   nothing but peek `argv`; under `--emit-endpoints` it dumps the declarations
   and exits.
3. `gleam run -m oaisp/cli generate` runs the package-interface export, collects
   the declarations, resolves every `type_ref` against the resolved type
   information, and writes `openapi.json`.

The router stays hand-written — oaisp never owns it. **Soundness over
completeness:** the document never claims something the server won't honor, but
it may under-describe (an undeclared route, or a type whose JSON shape oaisp
can't derive, is simply left out or described permissively).

## Quickstart

### 1. Your types are just types

```gleam
// src/myapp/types.gleam

/// A todo item.
pub type Todo {
  Todo(id: String, title: String, done: Bool)
}

/// Fields for creating a todo.
pub type NewTodo {
  NewTodo(title: String)
}
```

No oaisp wrappers, no required codec. Doc-comments become schema descriptions.

### 2. Declare endpoints

```gleam
// src/myapp/endpoints.gleam
import myapp/types
import oaisp
import oaisp/param

// A tiny helper keeps the type references tidy.
fn todo() -> oaisp.Schema {
  oaisp.type_ref("myapp/types", "Todo")
}

pub fn all() -> List(oaisp.Endpoint) {
  [
    oaisp.get("/todos")
      |> oaisp.with_response(200, todo())
      |> oaisp.with_summary("List all todos"),
    oaisp.post("/todos")
      |> oaisp.with_body(oaisp.type_ref("myapp/types", "NewTodo"))
      |> oaisp.with_response(201, todo()),
    oaisp.get("/todos/{id}")
      |> oaisp.with_path_param("id", param.string())
      |> oaisp.with_response(200, todo())
      |> oaisp.with_empty_response(404, "Not found"),
  ]
}
```

`type_ref(module, name)` names a public type; oaisp resolves its schema from the
package interface. A mistyped reference is caught by `oaisp lint`.

### 3. One line in `main`

```gleam
import myapp/endpoints
import oaisp

pub fn main() {
  let info = oaisp.info("Todo API", "1.0.0")
  let assert Ok(_) =
    wisp_mist.handler(router.handle_request, secret_key_base)
    |> mist.new
    |> oaisp.add_openapi(endpoints.all(), info)
    // ^ the addition
    |> mist.port(8080)
    |> mist.start
  process.sleep_forever()
}
```

`add_openapi` is generic in the builder and only passes it through, so it works
with mist (or anything) and adds **no dependency on a server library** — and no
runtime cost beyond a single `argv` peek.

### 4. Generate

```sh
gleam run -m oaisp/cli generate        # → ./openapi.json
```

For the `Todo` above you get:

```jsonc
{
  "openapi": "3.1.0",
  "info": { "title": "Todo API", "version": "1.0.0" },
  "paths": {
    "/todos/{id}": {
      "get": {
        "parameters": [
          { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
        ],
        "responses": {
          "200": { "description": "OK", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Todo" } } } },
          "404": { "description": "Not found" }
        }
      }
    }
    // …
  },
  "components": {
    "schemas": {
      "Todo": {
        "description": "A todo item.",
        "type": "object",
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "done": { "type": "boolean" }
        },
        "required": ["id", "title", "done"]
      }
    }
  }
}
```

## CLI

```
gleam run -m oaisp/cli <command> [options]
```

| Command | What it does |
|---|---|
| `generate` | Emit the OpenAPI 3.1 document. |
| `lint` | Check the declarations: every `type_ref` resolves, every `{placeholder}` has a `with_path_param` (and vice versa), no duplicate operations. Exits non-zero on an error. |
| `diff <old> <new>` | Report breaking changes between two OpenAPI documents (removed operations/responses/schemas/properties, newly-required params/properties). Exits non-zero on a breaking change — a CI gate. |
| `derive` | Generate decoder + encoder functions for your public types (see below). |

Options for `generate` / `lint` / `derive`:

| Option | Default | Meaning |
|---|---|---|
| `-o, --out <PATH>` | `generate`: `./openapi.json`; `derive`: stdout | Output path. `-` is stdout (status stays on stderr, so it's pipeable). |
| `--package-interface <PATH>` | auto | Use an existing `package-interface.json` instead of running the export. |
| `--quiet` | off | Suppress status output on stderr. |

Writes are atomic (temp file + rename). Status goes to stderr; the exit code is
non-zero on failure.

### `derive` — optional codec generation

Hand-writing decoders and encoders is boilerplate, and a hand-written one can
drift from the type. `oaisp derive` generates them *from the same type
structure the schema comes from*, so they can't disagree:

```sh
gleam run -m oaisp/cli derive -o src/myapp/codecs.gleam
```

This emits a module of `*_decoder()` / `*_encoder()` functions for your records
and enums (referencing each other and your types). It's entirely optional — use
them in your handlers if you like; oaisp's document generation never requires
them.

## What maps to what

| Gleam | OpenAPI 3.1 schema |
|---|---|
| record (one constructor, labelled fields) | `object` with `properties` + `required` |
| `Option(T)` field | not required, type allows `null` |
| `List(T)` | `array` of `T` |
| `Dict(String, V)` | `object` with `additionalProperties: V` |
| union of fieldless variants | `string` `enum` |
| `String` / `Int` / `Float` / `Bool` | `string` / `integer` / `number` / `boolean` |
| reference to another public type | `$ref` (collected transitively) |
| opaque type, generic, or union with payloads | permissively under-described |

## Caveats

- **Soundness, not completeness.** Routes the router serves but you didn't
  declare are intentional escape hatches; they're simply absent from the doc.
- **Schemas follow type structure.** oaisp derives schemas from your types and
  assumes your handler reads/writes them with the field labels as JSON keys. If
  you want generated codecs that are guaranteed to match, use `oaisp derive`.
- **Public types only.** The package interface contains only `pub` types; a
  `type_ref` to a private type fails to resolve — `oaisp lint` flags it.
- **Erlang target only.**

## Example

A complete example lives in [`example/`](example/) — a Todo API exercising every
shape oaisp models (scalars, `List`, `Option`, `Dict`, nested records, enums,
path/query params, request bodies, several response codes across all methods).
Its end-to-end check ([`example/e2e/`](example/e2e/)) **generates** the document,
**validates** it as OpenAPI 3.1 with [redocly](https://github.com/Redocly/redocly-cli),
and **type-checks** an [`openapi-fetch`](https://openapi-ts.dev/openapi-fetch/)
client generated from it — so the document is proven both valid and faithfully
consumable. It runs in CI ([`.github/workflows/e2e.yml`](.github/workflows/e2e.yml)).

## License

Apache-2.0
