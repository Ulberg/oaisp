//// oaisp — a code-first OpenAPI 3.1 generator for Wisp applications on the BEAM.
////
//// You write request/response types and endpoint declarations as ordinary
//// Gleam code; one CLI command (`gleam run -m oaisp/cli generate`) emits a
//// truthful OpenAPI 3.1 document at build time. The Gleam code is the single
//// source of truth; the spec is a sound projection of it.
////
//// This module is the public surface: it re-exports the builders so callers
//// can stay in a single `oaisp.*` namespace, and provides [`add_openapi`](#add_openapi),
//// the one-line build-time hook. Scalar param helpers live in
//// [`oaisp/param`](./oaisp/param.html); the CLI in
//// [`oaisp/cli`](./oaisp/cli.html).

import argv
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import oaisp/codec as codec_module
import oaisp/endpoint as endpoint_module
import oaisp/info as info_module
import oaisp/internal/emit

/// The version of the oaisp library.
pub const version: String = "0.1.0"

/// A codec bundling a decoder, encoder, and schema for a type. See
/// [`oaisp/codec`](./oaisp/codec.html).
pub type Codec(t) =
  codec_module.Codec(t)

/// How a value's schema is described in the document.
pub type Schema =
  codec_module.Schema

/// The primitive kinds an inline scalar schema can take.
pub type ScalarKind =
  codec_module.ScalarKind

/// A single endpoint declaration. See [`oaisp/endpoint`](./oaisp/endpoint.html).
pub type Endpoint =
  endpoint_module.Endpoint

/// An HTTP method oaisp can document.
pub type Method =
  endpoint_module.Method

/// The top-level metadata for the emitted document.
pub type Info =
  info_module.Info

/// Bundle a decoder, an encoder, and a schema into a [`Codec`](#Codec).
pub fn codec(
  decode decode: decode.Decoder(t),
  encode encode: fn(t) -> json.Json,
  schema schema: Schema,
) -> Codec(t) {
  codec_module.codec(decode:, encode:, schema:)
}

/// A schema referring to a public Gleam type, resolved at merge time.
pub fn type_ref(module module: String, name name: String) -> Schema {
  codec_module.type_ref(module:, name:)
}

/// A `GET` endpoint at `path`.
pub fn get(path: String) -> Endpoint {
  endpoint_module.get(path)
}

/// A `POST` endpoint at `path`.
pub fn post(path: String) -> Endpoint {
  endpoint_module.post(path)
}

/// A `PUT` endpoint at `path`.
pub fn put(path: String) -> Endpoint {
  endpoint_module.put(path)
}

/// A `PATCH` endpoint at `path`.
pub fn patch(path: String) -> Endpoint {
  endpoint_module.patch(path)
}

/// A `DELETE` endpoint at `path`.
pub fn delete(path: String) -> Endpoint {
  endpoint_module.delete(path)
}

/// Attach a request-body schema, taken from `codec`.
pub fn with_body(endpoint: Endpoint, codec: Codec(t)) -> Endpoint {
  endpoint_module.with_body(endpoint, codec)
}

/// Document a response with a body schema for `status`.
pub fn with_response(
  endpoint: Endpoint,
  status: Int,
  codec: Codec(t),
) -> Endpoint {
  endpoint_module.with_response(endpoint, status, codec)
}

/// Document an empty (bodyless) response for `status`, with a description.
pub fn with_empty_response(
  endpoint: Endpoint,
  status: Int,
  description: String,
) -> Endpoint {
  endpoint_module.with_empty_response(endpoint, status, description)
}

/// Document a path parameter.
pub fn with_path_param(
  endpoint: Endpoint,
  name: String,
  schema: Schema,
) -> Endpoint {
  endpoint_module.with_path_param(endpoint, name, schema)
}

/// Document a query parameter, marking whether it is required.
pub fn with_query_param(
  endpoint: Endpoint,
  name: String,
  schema: Schema,
  required: Bool,
) -> Endpoint {
  endpoint_module.with_query_param(endpoint, name, schema, required)
}

/// Set the operation summary.
pub fn with_summary(endpoint: Endpoint, summary: String) -> Endpoint {
  endpoint_module.with_summary(endpoint, summary)
}

/// Set the operation description.
pub fn with_description(endpoint: Endpoint, description: String) -> Endpoint {
  endpoint_module.with_description(endpoint, description)
}

/// Add a grouping tag.
pub fn with_tag(endpoint: Endpoint, tag: String) -> Endpoint {
  endpoint_module.with_tag(endpoint, tag)
}

/// Set the `operationId`.
pub fn with_operation_id(endpoint: Endpoint, id: String) -> Endpoint {
  endpoint_module.with_operation_id(endpoint, id)
}

/// Document metadata with no description and no servers; spread to override.
pub fn info(title title: String, version version: String) -> Info {
  info_module.info(title:, version:)
}

/// The build-time hook. Drop it into your server builder pipeline:
///
/// ```gleam
/// wisp_mist.handler(router.handle_request, secret_key_base)
/// |> mist.new
/// |> oaisp.add_openapi(endpoints.all(), info)
/// |> mist.port(8080)
/// |> mist.start
/// ```
///
/// When the program is run with `--emit-endpoints` (which the CLI does
/// internally), it prints the endpoint declarations and document info as JSON
/// and exits. Otherwise it returns `builder` untouched — so it adds nothing to
/// your server at runtime beyond a single `argv` peek at startup.
///
/// It is generic in the builder type and never inspects it, so oaisp needs no
/// dependency on `mist` (or any server library): the value simply passes
/// through.
pub fn add_openapi(builder: a, endpoints: List(Endpoint), info: Info) -> a {
  case list.contains(argv.load().arguments, "--emit-endpoints") {
    True -> {
      io.println(emit.to_string(emit.Document(info:, endpoints:)))
      halt(0)
    }
    False -> builder
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> a
