//// A route binds a path and method to a handler *and* carries the OpenAPI
//// annotations for that endpoint. One list of routes is the single source of
//// truth: it drives your running server (via [`match`](#match)) and the
//// generated document (via [`to_endpoints`](#to_endpoints)), so the two can't
//// drift.
////
//// Annotations are a single [`OpenApi`](#OpenApi) record — build the default
//// and spread what you need, mirroring the F# `addOpenApi(OpenApiConfig(…))`:
////
//// ```gleam
//// route.get("/plants", handle_list_plants)
//// |> route.with_openapi(OpenApi(
////   ..route.openapi(),
////   summary: Some("ListPlants"),
////   tags: ["Portfolio"],
////   responses: [ResponseBody(200, type_ref("myapp/types", "PlantList"))],
//// ))
//// ```
////
//// oaisp never inspects the handler — `Route` is generic in it — so oaisp gains
//// no dependency on wisp, mist, or any server library. `match` returns the
//// matched handler and the captured path parameters for *you* to invoke.

import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import oaisp/endpoint.{type Endpoint}
import oaisp/schema.{type Schema}

/// A documented endpoint plus the handler that serves it. `handler` is whatever
/// your framework uses — e.g. `fn(wisp.Request, List(#(String, String))) ->
/// wisp.Response`.
pub opaque type Route(handler) {
  Route(endpoint: Endpoint, handler: handler)
}

/// The OpenAPI annotations for a route. Build [`openapi`](#openapi) and spread
/// to set what you need.
pub type OpenApi {
  OpenApi(
    summary: Option(String),
    description: Option(String),
    operation_id: Option(String),
    tags: List(String),
    path: List(#(String, Schema)),
    query: List(QueryParam),
    query_record: Option(Schema),
    request_body: Option(Schema),
    responses: List(ResponseSpec),
  )
}

/// A documented query parameter.
pub type QueryParam {
  QueryParam(name: String, schema: Schema, required: Bool)
}

/// A documented response: a body of a given type, or an empty response.
pub type ResponseSpec {
  ResponseBody(status: Int, schema: Schema)
  EmptyResponse(status: Int, description: String)
}

/// The result of a successful [`match`](#match): the handler to invoke and the
/// path parameters captured from the request path.
pub type Matched(handler) {
  Matched(handler: handler, path_params: List(#(String, String)))
}

/// An empty [`OpenApi`](#OpenApi) annotation — spread it to set fields.
pub fn openapi() -> OpenApi {
  OpenApi(
    summary: None,
    description: None,
    operation_id: None,
    tags: [],
    path: [],
    query: [],
    query_record: None,
    request_body: None,
    responses: [],
  )
}

/// A `GET` route at `path`, served by `handler`.
pub fn get(path: String, handler: handler) -> Route(handler) {
  Route(endpoint.get(path), handler)
}

/// A `POST` route at `path`, served by `handler`.
pub fn post(path: String, handler: handler) -> Route(handler) {
  Route(endpoint.post(path), handler)
}

/// A `PUT` route at `path`, served by `handler`.
pub fn put(path: String, handler: handler) -> Route(handler) {
  Route(endpoint.put(path), handler)
}

/// A `PATCH` route at `path`, served by `handler`.
pub fn patch(path: String, handler: handler) -> Route(handler) {
  Route(endpoint.patch(path), handler)
}

/// A `DELETE` route at `path`, served by `handler`.
pub fn delete(path: String, handler: handler) -> Route(handler) {
  Route(endpoint.delete(path), handler)
}

/// Apply OpenAPI annotations to a route.
pub fn with_openapi(route: Route(handler), config: OpenApi) -> Route(handler) {
  let annotated =
    route.endpoint
    |> set_optional(config.summary, endpoint.with_summary)
    |> set_optional(config.description, endpoint.with_description)
    |> set_optional(config.operation_id, endpoint.with_operation_id)
    |> list.fold(config.tags, _, endpoint.with_tag)
    |> list.fold(config.path, _, fn(acc, param) {
      endpoint.with_path_param(acc, param.0, param.1)
    })
    |> list.fold(config.query, _, fn(acc, param) {
      endpoint.with_query_param(acc, param.name, param.schema, param.required)
    })
    |> set_optional(config.query_record, endpoint.with_query_record)
    |> set_optional(config.request_body, endpoint.with_body)
    |> list.fold(config.responses, _, apply_response)
  Route(..route, endpoint: annotated)
}

fn set_optional(
  endpoint: Endpoint,
  value: Option(a),
  with: fn(Endpoint, a) -> Endpoint,
) -> Endpoint {
  case value {
    Some(value) -> with(endpoint, value)
    None -> endpoint
  }
}

fn apply_response(endpoint: Endpoint, response: ResponseSpec) -> Endpoint {
  case response {
    ResponseBody(status, schema) ->
      endpoint.with_response(endpoint, status, schema)
    EmptyResponse(status, description) ->
      endpoint.with_empty_response(endpoint, status, description)
  }
}

// --- simple path: pipeable modifiers -----------------------------------------
//
// The [`OpenApi`](#OpenApi) record above is the advanced path: set every
// annotation at once. For simpler endpoints, pipe these one-concern modifiers
// onto the route instead — no record, no `Some` wrapping, no extra imports, and
// it reads as a flat pipe. Both styles drive the same underlying endpoint, so
// they are interchangeable and can be mixed on the same route.

/// Set the one-line summary.
pub fn summary(route: Route(handler), summary: String) -> Route(handler) {
  modify(route, endpoint.with_summary(_, summary))
}

/// Set the longer description.
pub fn description(
  route: Route(handler),
  description: String,
) -> Route(handler) {
  modify(route, endpoint.with_description(_, description))
}

/// Set the operation id.
pub fn operation_id(
  route: Route(handler),
  operation_id: String,
) -> Route(handler) {
  modify(route, endpoint.with_operation_id(_, operation_id))
}

/// Tag the operation, for grouping in the document.
pub fn tags(route: Route(handler), tags: List(String)) -> Route(handler) {
  modify(route, fn(ep) { list.fold(tags, ep, endpoint.with_tag) })
}

/// Document a `{name}` path parameter with `schema` — always required.
pub fn path_param(
  route: Route(handler),
  name: String,
  schema: Schema,
) -> Route(handler) {
  modify(route, endpoint.with_path_param(_, name, schema))
}

/// Document a query parameter.
pub fn query_param(
  route: Route(handler),
  name: String,
  schema: Schema,
  required: Bool,
) -> Route(handler) {
  modify(route, endpoint.with_query_param(_, name, schema, required))
}

/// Reflect each scalar field of `schema` (a record type) into a query
/// parameter — the equivalent of F#'s `addQueryParameters<'T>`.
pub fn query_record(route: Route(handler), schema: Schema) -> Route(handler) {
  modify(route, endpoint.with_query_record(_, schema))
}

/// Document the request body type.
pub fn accepts(route: Route(handler), schema: Schema) -> Route(handler) {
  modify(route, endpoint.with_body(_, schema))
}

/// Document a response body for `status`.
pub fn returns(
  route: Route(handler),
  status: Int,
  schema: Schema,
) -> Route(handler) {
  modify(route, endpoint.with_response(_, status, schema))
}

/// Document an empty response for `status`, with a description.
pub fn returns_empty(
  route: Route(handler),
  status: Int,
  description: String,
) -> Route(handler) {
  modify(route, endpoint.with_empty_response(_, status, description))
}

fn modify(
  route: Route(handler),
  with: fn(Endpoint) -> Endpoint,
) -> Route(handler) {
  Route(..route, endpoint: with(route.endpoint))
}

/// The documented endpoints behind these routes — the input to the document
/// generator. Drops the handlers.
pub fn to_endpoints(routes: List(Route(handler))) -> List(Endpoint) {
  list.map(routes, fn(route) { route.endpoint })
}

/// Find the first route whose method and path match the request, returning its
/// handler and the captured path parameters. `method` is the lower-cased HTTP
/// method (`"get"`, `"post"`, …); `path_segments` is the request path split on
/// `/` (e.g. `["todos", "42"]`).
pub fn match(
  routes: List(Route(handler)),
  method: String,
  path_segments: List(String),
) -> Result(Matched(handler), Nil) {
  list.find_map(routes, fn(route) {
    use <- bool.guard(
      when: endpoint.method_to_string(endpoint.method(route.endpoint)) != method,
      return: Error(Nil),
    )
    match_path(endpoint.path(route.endpoint), path_segments)
    |> result.map(fn(params) { Matched(route.handler, params) })
  })
}

fn match_path(
  pattern: String,
  segments: List(String),
) -> Result(List(#(String, String)), Nil) {
  do_match_path(path_segments(pattern), segments, [])
}

fn do_match_path(
  pattern: List(String),
  segments: List(String),
  captured: List(#(String, String)),
) -> Result(List(#(String, String)), Nil) {
  case pattern, segments {
    [], [] -> Ok(list.reverse(captured))
    [pattern_segment, ..pattern_rest], [segment, ..segments_rest] ->
      case endpoint.placeholder_name(pattern_segment) {
        Some(name) ->
          do_match_path(pattern_rest, segments_rest, [
            #(name, segment),
            ..captured
          ])
        None ->
          case pattern_segment == segment {
            True -> do_match_path(pattern_rest, segments_rest, captured)
            False -> Error(Nil)
          }
      }
    _, _ -> Error(Nil)
  }
}

fn path_segments(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter(fn(segment) { segment != "" })
}
