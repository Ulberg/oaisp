# Example

A small Wisp/mist Todo API that uses oaisp.

- [`src/example/types.gleam`](src/example/types.gleam) — the data model, covering
  every shape oaisp projects (scalars, `List`, `Option`, `Dict`, a nested record,
  an enum, pagination, an error envelope).
- [`src/example/api.gleam`](src/example/api.gleam) — the endpoint declarations.
- [`src/example/router.gleam`](src/example/router.gleam) — the Wisp request handler.
- [`src/example.gleam`](src/example.gleam) — the server `main`, with the one-line
  `oaisp.add_openapi` hook.

```sh
gleam run                                   # serve on http://localhost:8080
gleam run -m oaisp/cli generate -o openapi.json   # emit the OpenAPI document
```

For the end-to-end check that validates the document and runs an `openapi-fetch`
client against the live server, see [`e2e/`](e2e/).
