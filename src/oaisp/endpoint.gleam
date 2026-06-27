//// Endpoint declarations: typed values capturing an operation's method, path,
//// parameters, request body, and responses.
////
//// Each declaration fuses a route with the codecs its handler uses, so the
//// emitted document and the runtime contract are read from one place. An
//// `Endpoint` is built with a method constructor ([`get`](#get),
//// [`post`](#post), …) and refined with the `with_*` combinators; it is opaque
//// so it can never exist without a method and a path.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import oaisp/schema.{type Schema, schema_decoder, schema_to_json}

/// An HTTP method oaisp can document.
pub type Method {
  Get
  Post
  Put
  Patch
  Delete
}

/// A documented path or query parameter.
pub type Param {
  Param(name: String, schema: Schema, required: Bool)
}

/// A documented response for a status code. `body` is `None` for a response
/// with no body (e.g. a `404`).
pub type Response {
  Response(status: Int, body: Option(Schema), description: Option(String))
}

/// A single endpoint declaration.
///
/// Opaque: build one with a method constructor and refine it with the `with_*`
/// combinators. Read its parts back with the accessors ([`method`](#method),
/// [`path`](#path), …).
pub opaque type Endpoint {
  Endpoint(
    method: Method,
    path: String,
    summary: Option(String),
    description: Option(String),
    operation_id: Option(String),
    tags: List(String),
    path_params: List(Param),
    query_params: List(Param),
    query_record: Option(Schema),
    body: Option(Schema),
    responses: List(Response),
  )
}

fn new(method: Method, path: String) -> Endpoint {
  Endpoint(
    method:,
    path:,
    summary: None,
    description: None,
    operation_id: None,
    tags: [],
    path_params: [],
    query_params: [],
    query_record: None,
    body: None,
    responses: [],
  )
}

/// A `GET` endpoint at `path`.
pub fn get(path: String) -> Endpoint {
  new(Get, path)
}

/// A `POST` endpoint at `path`.
pub fn post(path: String) -> Endpoint {
  new(Post, path)
}

/// A `PUT` endpoint at `path`.
pub fn put(path: String) -> Endpoint {
  new(Put, path)
}

/// A `PATCH` endpoint at `path`.
pub fn patch(path: String) -> Endpoint {
  new(Patch, path)
}

/// A `DELETE` endpoint at `path`.
pub fn delete(path: String) -> Endpoint {
  new(Delete, path)
}

/// Attach a request-body schema, taken from `codec`.
pub fn with_body(endpoint: Endpoint, schema: Schema) -> Endpoint {
  Endpoint(..endpoint, body: Some(schema))
}

/// Document a response with a body schema for `status`.
pub fn with_response(
  endpoint: Endpoint,
  status: Int,
  schema: Schema,
) -> Endpoint {
  let response = Response(status:, body: Some(schema), description: None)
  Endpoint(..endpoint, responses: list.append(endpoint.responses, [response]))
}

/// Document an empty (bodyless) response for `status`, with a description.
pub fn with_empty_response(
  endpoint: Endpoint,
  status: Int,
  description: String,
) -> Endpoint {
  let response = Response(status:, body: None, description: Some(description))
  Endpoint(..endpoint, responses: list.append(endpoint.responses, [response]))
}

/// Document a path parameter. Path parameters are always required.
pub fn with_path_param(
  endpoint: Endpoint,
  name: String,
  schema: Schema,
) -> Endpoint {
  let param = Param(name:, schema:, required: True)
  Endpoint(..endpoint, path_params: list.append(endpoint.path_params, [param]))
}

/// Document a query parameter, marking whether it is required.
pub fn with_query_param(
  endpoint: Endpoint,
  name: String,
  schema: Schema,
  required: Bool,
) -> Endpoint {
  let param = Param(name:, schema:, required:)
  Endpoint(
    ..endpoint,
    query_params: list.append(endpoint.query_params, [param]),
  )
}

/// Document query parameters by reference to a record type: each of the
/// record's scalar fields becomes a query parameter (an `Option` field is
/// optional, the rest required). The type is resolved at merge time from the
/// package interface; fields oaisp can't express as a scalar query parameter
/// are soundly omitted. Mirrors F#'s `addQueryParameters<'T>`.
pub fn with_query_record(endpoint: Endpoint, schema: Schema) -> Endpoint {
  Endpoint(..endpoint, query_record: Some(schema))
}

/// Set the operation summary (a short one-line label).
pub fn with_summary(endpoint: Endpoint, summary: String) -> Endpoint {
  Endpoint(..endpoint, summary: Some(summary))
}

/// Set the operation description (longer prose).
pub fn with_description(endpoint: Endpoint, description: String) -> Endpoint {
  Endpoint(..endpoint, description: Some(description))
}

/// Add a tag, used to group operations in the document.
pub fn with_tag(endpoint: Endpoint, tag: String) -> Endpoint {
  Endpoint(..endpoint, tags: list.append(endpoint.tags, [tag]))
}

/// Set the `operationId`, a unique identifier for the operation.
pub fn with_operation_id(endpoint: Endpoint, id: String) -> Endpoint {
  Endpoint(..endpoint, operation_id: Some(id))
}

/// The endpoint's HTTP method.
pub fn method(endpoint: Endpoint) -> Method {
  endpoint.method
}

/// The endpoint's path, including any `{param}` placeholders.
pub fn path(endpoint: Endpoint) -> String {
  endpoint.path
}

/// The endpoint's summary, if set.
pub fn summary(endpoint: Endpoint) -> Option(String) {
  endpoint.summary
}

/// The endpoint's description, if set.
pub fn description(endpoint: Endpoint) -> Option(String) {
  endpoint.description
}

/// The endpoint's `operationId`, if set.
pub fn operation_id(endpoint: Endpoint) -> Option(String) {
  endpoint.operation_id
}

/// The endpoint's tags, in declaration order.
pub fn tags(endpoint: Endpoint) -> List(String) {
  endpoint.tags
}

/// The endpoint's path parameters, in declaration order.
pub fn path_params(endpoint: Endpoint) -> List(Param) {
  endpoint.path_params
}

/// The endpoint's query parameters, in declaration order.
pub fn query_params(endpoint: Endpoint) -> List(Param) {
  endpoint.query_params
}

/// The record type whose scalar fields are reflected into query parameters, if
/// one was set with [`with_query_record`](#with_query_record).
pub fn query_record(endpoint: Endpoint) -> Option(Schema) {
  endpoint.query_record
}

/// The endpoint's request-body schema, if any.
pub fn body(endpoint: Endpoint) -> Option(Schema) {
  endpoint.body
}

/// The endpoint's documented responses, in declaration order.
pub fn responses(endpoint: Endpoint) -> List(Response) {
  endpoint.responses
}

/// The string used for `method` in an OpenAPI path item (lower-cased).
pub fn method_to_string(method: Method) -> String {
  case method {
    Get -> "get"
    Post -> "post"
    Put -> "put"
    Patch -> "patch"
    Delete -> "delete"
  }
}

/// Every `(module, name)` type reference the endpoint mentions — across its body,
/// response bodies, and path/query parameters — deduplicated. The single source
/// for "which public types does this endpoint touch", used by the merge both to
/// seed the component closure and to check that every reference resolves.
@internal
pub fn type_refs(endpoint: Endpoint) -> List(#(String, String)) {
  let bodies = [endpoint.body, ..list.map(endpoint.responses, fn(r) { r.body })]
  let params = list.append(endpoint.path_params, endpoint.query_params)
  list.append(option.values(bodies), list.map(params, fn(p) { p.schema }))
  |> list.filter_map(schema.type_ref_parts)
  |> list.unique
}

/// The placeholder name in a `{name}` path segment, or `None` for a literal
/// segment. The one definition of oaisp's path-placeholder syntax, used by route
/// matching.
@internal
pub fn placeholder_name(segment: String) -> Option(String) {
  case string.starts_with(segment, "{") && string.ends_with(segment, "}") {
    True -> Some(segment |> string.drop_start(1) |> string.drop_end(1))
    False -> None
  }
}

// --- internal wire format (for `--emit-endpoints`) ---------------------------

fn method_from_string(name: String) -> Result(Method, Nil) {
  case name {
    "get" -> Ok(Get)
    "post" -> Ok(Post)
    "put" -> Ok(Put)
    "patch" -> Ok(Patch)
    "delete" -> Ok(Delete)
    _ -> Error(Nil)
  }
}

fn method_decoder() -> decode.Decoder(Method) {
  use raw <- decode.then(decode.string)
  case method_from_string(raw) {
    Ok(method) -> decode.success(method)
    Error(Nil) -> decode.failure(Get, "Method")
  }
}

fn param_to_json(param: Param) -> json.Json {
  json.object([
    #("name", json.string(param.name)),
    #("required", json.bool(param.required)),
    #("schema", schema_to_json(param.schema)),
  ])
}

fn param_decoder() -> decode.Decoder(Param) {
  use name <- decode.field("name", decode.string)
  use required <- decode.field("required", decode.bool)
  use param_schema <- decode.field("schema", schema_decoder())
  decode.success(Param(name:, schema: param_schema, required:))
}

fn response_to_json(response: Response) -> json.Json {
  json.object([
    #("status", json.int(response.status)),
    #("body", json.nullable(response.body, schema_to_json)),
    #("description", json.nullable(response.description, json.string)),
  ])
}

fn response_decoder() -> decode.Decoder(Response) {
  use status <- decode.field("status", decode.int)
  use body <- decode.field("body", decode.optional(schema_decoder()))
  use description <- decode.field("description", decode.optional(decode.string))
  decode.success(Response(status:, body:, description:))
}

/// Encode an [`Endpoint`](#Endpoint) to the internal wire JSON.
@internal
pub fn to_json(endpoint: Endpoint) -> json.Json {
  json.object([
    #("method", json.string(method_to_string(endpoint.method))),
    #("path", json.string(endpoint.path)),
    #("summary", json.nullable(endpoint.summary, json.string)),
    #("description", json.nullable(endpoint.description, json.string)),
    #("operation_id", json.nullable(endpoint.operation_id, json.string)),
    #("tags", json.array(endpoint.tags, json.string)),
    #("path_params", json.array(endpoint.path_params, param_to_json)),
    #("query_params", json.array(endpoint.query_params, param_to_json)),
    #("query_record", json.nullable(endpoint.query_record, schema_to_json)),
    #("body", json.nullable(endpoint.body, schema_to_json)),
    #("responses", json.array(endpoint.responses, response_to_json)),
  ])
}

/// Decode an [`Endpoint`](#Endpoint) from the internal wire JSON. Reconstructs
/// the opaque value through its private constructor.
@internal
pub fn decoder() -> decode.Decoder(Endpoint) {
  use method <- decode.field("method", method_decoder())
  use path <- decode.field("path", decode.string)
  use summary <- decode.field("summary", decode.optional(decode.string))
  use description <- decode.field("description", decode.optional(decode.string))
  use operation_id <- decode.field(
    "operation_id",
    decode.optional(decode.string),
  )
  use tags <- decode.field("tags", decode.list(decode.string))
  use path_params <- decode.field("path_params", decode.list(param_decoder()))
  use query_params <- decode.field("query_params", decode.list(param_decoder()))
  use query_record <- decode.field(
    "query_record",
    decode.optional(schema_decoder()),
  )
  use body <- decode.field("body", decode.optional(schema_decoder()))
  use responses <- decode.field("responses", decode.list(response_decoder()))
  decode.success(Endpoint(
    method:,
    path:,
    summary:,
    description:,
    operation_id:,
    tags:,
    path_params:,
    query_params:,
    query_record:,
    body:,
    responses:,
  ))
}
