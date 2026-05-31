import gleam/list
import gleam/option.{None, Some}
import oaisp/endpoint
import oaisp/param
import oaisp/route.{EmptyResponse, OpenApi, ResponseBody}
import oaisp/schema

pub fn match_static_paths_test() {
  let routes = [route.get("/plants", "list"), route.post("/plants", "create")]
  assert route.match(routes, "get", ["plants"]) == Ok(route.Matched("list", []))
  assert route.match(routes, "post", ["plants"])
    == Ok(route.Matched("create", []))
  assert route.match(routes, "delete", ["plants"]) == Error(Nil)
  assert route.match(routes, "get", ["nope"]) == Error(Nil)
}

pub fn match_captures_path_params_test() {
  let routes = [route.get("/todos/{id}/items/{item}", "h")]
  assert route.match(routes, "get", ["todos", "42", "items", "9"])
    == Ok(route.Matched("h", [#("id", "42"), #("item", "9")]))
  // wrong length doesn't match
  assert route.match(routes, "get", ["todos", "42"]) == Error(Nil)
}

pub fn first_match_wins_test() {
  let routes = [route.get("/a", "first"), route.get("/a", "second")]
  assert route.match(routes, "get", ["a"]) == Ok(route.Matched("first", []))
}

pub fn with_openapi_carries_the_doc_test() {
  let routes = [
    route.get("/todos/{id}", "h")
    |> route.with_openapi(
      OpenApi(
        ..route.openapi(),
        summary: Some("Get a todo"),
        tags: ["todos"],
        path: [#("id", param.string())],
        responses: [
          ResponseBody(200, schema.type_ref("myapp/types", "Todo")),
          EmptyResponse(404, "Not found"),
        ],
      ),
    ),
  ]
  let assert [e] = route.to_endpoints(routes)
  assert endpoint.method(e) == endpoint.Get
  assert endpoint.path(e) == "/todos/{id}"
  assert endpoint.summary(e) == Some("Get a todo")
  assert endpoint.tags(e) == ["todos"]
  assert endpoint.path_params(e)
    == [endpoint.Param("id", schema.Scalar(schema.StringKind, None), True)]
  assert list.map(endpoint.responses(e), fn(r) { r.status }) == [200, 404]
}

pub fn with_openapi_carries_query_record_test() {
  let routes = [
    route.get("/todos", "h")
    |> route.with_openapi(
      OpenApi(
        ..route.openapi(),
        query_record: Some(schema.type_ref("myapp/types", "TodoQuery")),
      ),
    ),
  ]
  let assert [e] = route.to_endpoints(routes)
  assert endpoint.query_record(e)
    == Some(schema.type_ref("myapp/types", "TodoQuery"))
}
