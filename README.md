# oaisp

A code-first **OpenAPI 3.1** generator for [Wisp](https://gleam.run/wisp/)
applications on the BEAM. You write your request/response types and endpoint
declarations as ordinary Gleam code; one CLI command emits a truthful OpenAPI
document at build time.

The Gleam code is the single source of truth — the spec is a *sound projection*
of it, derived from the compiler's own resolved type information
(`gleam export package-interface`). No spec-first scaffolding, no runtime
reflection, no source re-parsing.

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

1. You bundle each type's decoder, encoder, and a **schema reference** into a
   `Codec`. Your handlers use the decoder/encoder; oaisp uses the schema.
2. You declare endpoints (method, path, params, body, responses) as values.
3. `oaisp.add_openapi` is a one-line hook in your `main`. At runtime it does
   nothing but peek `argv`; under `--emit-endpoints` it dumps the declarations
   and exits.
4. `gleam run -m oaisp/cli generate` runs the package-interface export, collects
   the declarations, resolves every `TypeRef` against the resolved type
   information, and writes `openapi.json`.

The router stays hand-written — oaisp never owns it. **Soundness over
completeness:** the document never claims something the server won't honor, but
it may under-describe (an undeclared route, or a type whose JSON shape oaisp
can't derive, is simply left out or described permissively).

## Quickstart

### 1. Define types and codecs

```gleam
// src/myapp/types.gleam
import gleam/dynamic/decode
import gleam/json
import oaisp

pub type Todo {
  Todo(id: String, title: String, done: Bool)
}

pub fn todo_codec() -> oaisp.Codec(Todo) {
  oaisp.codec(
    decode: {
      use id <- decode.field("id", decode.string)
      use title <- decode.field("title", decode.string)
      use done <- decode.field("done", decode.bool)
      decode.success(Todo(id:, title:, done:))
    },
    encode: fn(todo) {
      json.object([
        #("id", json.string(todo.id)),
        #("title", json.string(todo.title)),
        #("done", json.bool(todo.done)),
      ])
    },
    // Refers to the public type; resolved from the package interface at merge time.
    schema: oaisp.type_ref("myapp/types", "Todo"),
  )
}
```

### 2. Declare endpoints

```gleam
// src/myapp/endpoints.gleam
import myapp/types
import oaisp
import oaisp/param

pub fn all() -> List(oaisp.Endpoint) {
  [
    oaisp.get("/todos")
      |> oaisp.with_response(200, types.todo_codec())
      |> oaisp.with_summary("List all todos"),
    oaisp.post("/todos")
      |> oaisp.with_body(types.todo_codec())
      |> oaisp.with_response(201, types.todo_codec()),
    oaisp.get("/todos/{id}")
      |> oaisp.with_path_param("id", param.string())
      |> oaisp.with_response(200, types.todo_codec())
      |> oaisp.with_empty_response(404, "Not found"),
  ]
}
```

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

Doc-comments on your types become schema `description`s automatically.

## CLI

```
gleam run -m oaisp/cli generate [OPTIONS]
```

| Option | Default | Meaning |
|---|---|---|
| `-o, --out <PATH>` | `./openapi.json` | Output path. `-` writes to stdout (status stays on stderr, so it's pipeable: `… generate -o - \| jq`). |
| `--package-interface <PATH>` | auto | Use an existing `package-interface.json` instead of running the export. |
| `--quiet` | off | Suppress status output on stderr. |

Writes are atomic (temp file + rename). Status goes to stderr; the exit code is
non-zero on failure.

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
- **Schemas follow type structure.** v1 derives schemas from your types and
  assumes your hand-written encoder matches them (field label → JSON key). Full
  codec *generation* that guarantees this is on the roadmap (`oaisp derive`).
- **Public types only.** The package interface contains only `pub` types; a
  `type_ref` to a private type fails to resolve with a clear error.
- **Erlang target only.**

## License

Apache-2.0
