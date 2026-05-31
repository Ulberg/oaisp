# oaisp

A code-first **OpenAPI 3.1** generator for [Wisp](https://gleam.run/wisp/)
applications on the BEAM. You declare your API as a list of **routes** — each
binding a path + method to a handler and carrying its OpenAPI annotations — and
that single list drives both your running server *and* the emitted document. One
CLI command writes a truthful OpenAPI 3.1 document at build time.

The schemas come from the compiler's own resolved type information
(`gleam export package-interface`), so the document can't drift from your types.
No spec-first scaffolding, no runtime reflection of the router, no source
re-parsing.

## Single source of truth

The thing that usually rots — the doc drifting from the routes — can't happen
here, because there is only one list:

```gleam
import oaisp
import oaisp/param
import oaisp/route.{type Route, OpenApi, ResponseBody}

pub fn routes() -> List(Route(Handler)) {
  [
    route.get("/todos/{id}", get_todo)
      |> route.with_openapi(OpenApi(
        ..route.openapi(),
        summary: Some("Get a todo"),
        tags: ["todos"],
        path: [#("id", param.string())],
        responses: [ResponseBody(200, oaisp.type_ref("myapp/types", "Todo"))],
      )),
  ]
}
```

`route.match(routes(), method, segments)` dispatches a request to `get_todo`;
`oaisp.add_openapi(routes(), info)` documents the same list. `Route` is generic
in the handler — oaisp never inspects it — so oaisp has **no dependency on wisp,
mist, or any server library**.

## Requirements

- **Erlang/OTP 27+** — `gleam_json` 3.x uses the OTP 27 `json` module.
- **Gleam 1.11+**.

## How it works

```
your Gleam types ──► gleam export package-interface ─┐
                                                      ├──► oaisp/cli merge ──► openapi.json
your routes()    ──► --emit-endpoints ────────────────┘
```

1. You write `routes()` — each route binds a handler and carries an `OpenApi`
   annotation (request/response **types** by reference, params, summary, tags).
2. You dispatch with `route.match` and wire `oaisp.add_openapi(routes(), info)`
   into your `main` (a one-line, generic pass-through; under `--emit-endpoints`
   it prints the declarations and exits).
3. `gleam run -m oaisp/cli generate` runs the package-interface export, collects
   the declarations, resolves every `type_ref` against the resolved type
   information, and writes `openapi.json`.

**Soundness over completeness:** the document never claims something the server
won't honor. Routes you don't put in `routes()` (streaming, websockets, …) are
served by your fallback and simply left undocumented; a type whose JSON shape
oaisp can't derive is described permissively.

## Quickstart

### 1. Your types are just types

```gleam
// src/myapp/types.gleam
pub type Todo {
  Todo(id: String, title: String, done: Bool)
}
```

Doc-comments on types become schema descriptions.

### 2. Bind routes to handlers, annotate them

```gleam
// src/myapp/api.gleam
import gleam/http
import gleam/string
import oaisp
import oaisp/route.{type Route, OpenApi, ResponseBody}
import wisp

pub type Handler =
  fn(wisp.Request, List(#(String, String))) -> wisp.Response

pub fn routes() -> List(Route(Handler)) {
  [
    route.get("/todos/{id}", get_todo)
      |> route.with_openapi(OpenApi(
        ..route.openapi(),
        path: [#("id", param.string())],
        responses: [ResponseBody(200, oaisp.type_ref("myapp/types", "Todo"))],
      )),
  ]
}

pub fn handle(req: wisp.Request) -> wisp.Response {
  let method = string.lowercase(http.method_to_string(req.method))
  case route.match(routes(), method, wisp.path_segments(req)) {
    Ok(route.Matched(handler, params)) -> handler(req, params)
    Error(Nil) -> wisp.not_found()
  }
}

fn get_todo(_req, params) -> wisp.Response {
  // … build and return a Todo response …
}
```

### 3. One pipeline in `main`

```gleam
wisp_mist.handler(api.handle, secret_key_base)
|> mist.new
|> oaisp.add_openapi(api.routes(), info)
|> mist.port(8080)
|> mist.start
```

`add_openapi` adds nothing at runtime beyond an `argv` peek at startup.

### 4. Generate

```sh
gleam run -m oaisp/cli generate        # → ./openapi.json
```

## CLI

```
gleam run -m oaisp/cli <command> [options]
```

| Command | What it does |
|---|---|
| `generate` | Emit the OpenAPI 3.1 document. |
| `lint` | Check declarations: `type_ref` existence, `{placeholder}` ↔ path params, duplicate operations. Non-zero on error. |
| `diff <old> <new>` | Report breaking changes between two documents (a CI gate). |
| `derive` | Generate decoder + encoder functions for your public types. |

Options: `-o, --out <PATH>` (`-` for stdout), `--package-interface <PATH>`,
`--quiet`. Writes are atomic; status goes to stderr.

## What maps to what

| Gleam | OpenAPI 3.1 schema |
|---|---|
| record (one constructor, labelled fields) | `object` with `properties` + `required` |
| `Option(T)` field | not required, type allows `null` |
| `List(T)` | `array` of `T` |
| `Dict(String, V)` | `object` with `additionalProperties: V` |
| union of fieldless variants | `string` `enum` |
| `String` / `Int` / `Float` / `Bool` | `string` / `integer` / `number` / `boolean` |
| `gleam/time/timestamp.Timestamp` | `string`, `format: date-time` (RFC 3339) |
| reference to another public type | `$ref` (collected transitively) |
| opaque type, generic, or union with payloads | permissively under-described |

`Float` additionally carries `format: double` (it is an IEEE-754 double on the
BEAM). `Int` is intentionally left without an `int32`/`int64` format: a Gleam
`Int` is an arbitrary-precision bignum, so claiming a fixed width would be
unsound.

String `format`s are type-driven: a `gleam/time/timestamp.Timestamp` field
becomes `format: date-time`. oaisp recognises it by name in the package interface
and takes no dependency on `gleam_time`, so the format rides on the standard type
without forcing an oaisp-owned type on you — the same way the F# generator derives
`date-time` from `DateTimeOffset`.

## Query parameters

Declare query parameters either way:

- **Explicitly** — `query: [QueryParam("limit", param.int(), False), …]`.
- **Reflected from a record** — `query_record: Some(type_ref("myapp/types", "TodoQuery"))`.
  Each scalar field of the record becomes a query parameter (an `Option` field
  is optional, the rest required; a `List(scalar)` field becomes an array
  parameter; non-scalar fields are soundly omitted). Write the record, get the
  parameters — mirroring F#'s `addQueryParameters<'T>`.

## Caveats

- **Soundness, not completeness.** Undeclared routes are served by your fallback
  and left out of the doc; that's intentional (streaming, websockets, …).
- **Schemas follow type structure** — oaisp assumes your handler reads/writes a
  type with its field labels as JSON keys. For guaranteed-matching codecs, use
  `oaisp derive`.
- **Public types only.** A `type_ref` to a private type fails to resolve —
  `oaisp lint` flags it.
- **Erlang target only.**

## Example

A complete Wisp/mist Todo API is in [`example/`](example/), exercising every
shape oaisp models. Its end-to-end check ([`example/e2e/`](example/e2e/))
generates the document, validates it as OpenAPI 3.1 with redocly, type-checks an
`openapi-fetch` client against it, and runs that client against the live server —
all in CI ([`.github/workflows/e2e.yml`](.github/workflows/e2e.yml)).

## License

Apache-2.0
