# Example E2E

Two checks that prove the document oaisp emits is both **valid** and **usable**,
end to end. Run in CI by [`.github/workflows/e2e.yml`](../../.github/workflows/e2e.yml).

## `run.sh` — generate, validate, type-check

1. **Generate** `openapi.json` from the example app (`oaisp generate`).
2. **Validate** it as OpenAPI 3.1 with [`@redocly/cli`](https://github.com/Redocly/redocly-cli).
3. **Generate** typed client definitions with [`openapi-typescript`](https://openapi-ts.dev/).
4. **Type-check** an [`openapi-fetch`](https://openapi-ts.dev/openapi-fetch/)
   client ([`client.ts`](client.ts)) against them.

## `live.sh` — live round-trip

5. **Start** the example Wisp/mist server.
6. **Call** it with an `openapi-fetch` client ([`live.mjs`](live.mjs)) and assert
   the responses match what the document describes.

```sh
bash run.sh && bash live.sh
```

Requires `gleam` + Erlang/OTP 27, Node.js, and `curl`.
