# Example E2E

Proves the document oaisp emits for [`../`](..) is correct and consumable by a
real client generator, end to end:

```sh
bash run.sh
```

It will:

1. **Generate** `openapi.json` from the example app (`gleam run -m oaisp/cli generate`).
2. **Validate** it as OpenAPI 3.1 with [`@redocly/cli`](https://github.com/Redocly/redocly-cli).
3. **Generate** typed client definitions with [`openapi-typescript`](https://openapi-ts.dev/).
4. **Type-check** an [`openapi-fetch`](https://openapi-ts.dev/openapi-fetch/) client
   ([`client.ts`](client.ts)) against them — if it compiles, the document
   faithfully describes every shape the example declares.

Requires `gleam` + Erlang/OTP 27 and Node.js. Run in CI by
[`.github/workflows/e2e.yml`](../../.github/workflows/e2e.yml).
