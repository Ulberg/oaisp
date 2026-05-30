//// Endpoint declarations: typed values capturing an operation's method, path,
//// parameters, request body, and responses.
////
//// Each declaration fuses a route with the codecs its handler uses, so the
//// emitted document and the runtime contract are read from one place. An
//// `Endpoint` is built with a method constructor ([`get`](#get),
//// [`post`](#post), …) and refined with the `with_*` combinators; it is opaque
//// so it can never exist without a method and a path.

import gleam/list
import gleam/option.{type Option, None, Some}
import oaisp/codec.{type Codec, type Schema, schema}

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
pub fn with_body(endpoint: Endpoint, codec: Codec(t)) -> Endpoint {
  Endpoint(..endpoint, body: Some(schema(codec)))
}

/// Document a response with a body schema for `status`.
pub fn with_response(
  endpoint: Endpoint,
  status: Int,
  codec: Codec(t),
) -> Endpoint {
  let response = Response(status:, body: Some(schema(codec)), description: None)
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
