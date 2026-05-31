#!/usr/bin/env bash
# End-to-end check for oaisp:
#   1. generate openapi.json from the example app,
#   2. validate it as OpenAPI 3.1 with redocly,
#   3. generate a typed client with openapi-typescript, and
#   4. type-check an openapi-fetch client against it.
#
# Run from anywhere; requires gleam + Erlang/OTP 27 and Node.js.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
example_dir="$(dirname "$here")"

echo "==> Generating openapi.json from the example app"
(cd "$example_dir" && gleam run -m oaisp/cli generate -o "$here/openapi.json" --quiet)

cd "$here"

echo "==> Installing client tooling"
npm install --no-audit --no-fund --silent

echo "==> Validating the OpenAPI 3.1 document"
npx @redocly/cli lint openapi.json

echo "==> Generating the typed client"
npx openapi-typescript openapi.json -o api.ts

echo "==> Type-checking the openapi-fetch client"
npx tsc --noEmit

echo "✅ E2E passed"
