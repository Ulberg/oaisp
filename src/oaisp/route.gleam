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

// --- simple path -------------------------------------------------------------

/// Document an endpoint in one call — the common case of a summary, some tags,
/// path parameters, and responses, without building an [`OpenApi`](#OpenApi)
/// record or wrapping fields in `Some`:
///
/// ```gleam
/// route.get("/todos/{id}", get_todo)
/// |> route.documented(
///   summary: "Get a todo by id",
///   tags: ["todos"],
///   path: [#("id", param.string())],
///   responses: [
///     ResponseBody(200, type_ref("myapp/types", "Todo")),
///     ResponseBody(404, type_ref("myapp/types", "Error")),
///   ],
/// )
/// ```
///
/// It is exactly [`with_openapi`](#with_openapi) over those four fields, so the
/// two produce the same endpoint. Reach for the full record when you also need a
/// description, an `operationId`, query parameters, a reflected query record, or
/// a request body.
pub fn documented(
  route: Route(handler),
  summary summary: String,
  tags tags: List(String),
  path path: List(#(String, Schema)),
  responses responses: List(ResponseSpec),
) -> Route(handler) {
  with_openapi(
    route,
    OpenApi(..openapi(), summary: Some(summary), tags:, path:, responses:),
  )
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
