//// The API as one list of routes. The same `routes()` drives the running
//// server (via [`handle`](#handle), which dispatches with `route.match`) and
//// the generated OpenAPI document (via `oaisp.add_openapi`) — so the wire
//// behaviour and the spec can't drift. Each route binds a path + method to a
//// handler and carries its OpenAPI annotations — set either with the `OpenApi`
//// record (the `/todos` routes) or with pipeable modifiers (the `/{id}`
//// routes); the two styles are interchangeable.

import gleam/http
import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import gleam/string
import oaisp
import oaisp/param
import oaisp/route.{type Route, OpenApi, ResponseBody}
import wisp

/// A handler receives the request and the path parameters the route captured.
pub type Handler =
  fn(wisp.Request, List(#(String, String))) -> wisp.Response

fn ref(name: String) -> oaisp.Schema {
  oaisp.type_ref("example/types", name)
}

pub fn routes() -> List(Route(Handler)) {
  [
    // The `/todos` collection routes use the advanced path: the `OpenApi` record
    // sets every annotation at once — handy when there are several.
    route.get("/todos", list_todos)
      |> route.with_openapi(
        OpenApi(
          ..route.openapi(),
          summary: Some("List todos"),
          operation_id: Some("listTodos"),
          tags: ["todos"],
          // Reflected from the `TodoQuery` record: `limit` and `tag` become
          // individual (optional) query parameters. Mirrors F#
          // `addQueryParameters<'T>`.
          query_record: Some(ref("TodoQuery")),
          responses: [ResponseBody(200, ref("TodoPage"))],
        ),
      ),
    route.post("/todos", create_todo)
      |> route.with_openapi(
        OpenApi(
          ..route.openapi(),
          summary: Some("Create a todo"),
          operation_id: Some("createTodo"),
          tags: ["todos"],
          request_body: Some(ref("NewTodo")),
          responses: [
            ResponseBody(201, ref("Todo")),
            ResponseBody(400, ref("ApiError")),
          ],
        ),
      ),
    // The `/{id}` routes use the simple path: pipeable modifiers instead of the
    // `OpenApi` record. Same result, less ceremony — no record, no `Some`.
    route.get("/todos/{id}", get_todo)
      |> route.summary("Get a todo by id")
      |> route.operation_id("getTodo")
      |> route.tags(["todos"])
      |> route.path_param("id", param.string())
      |> route.returns(200, ref("Todo"))
      |> route.returns(404, ref("ApiError")),
    route.put("/todos/{id}", replace_todo)
      |> route.summary("Replace a todo")
      |> route.operation_id("replaceTodo")
      |> route.tags(["todos"])
      |> route.path_param("id", param.string())
      |> route.accepts(ref("Todo"))
      |> route.returns(200, ref("Todo"))
      |> route.returns(404, ref("ApiError")),
    route.delete("/todos/{id}", delete_todo)
      |> route.summary("Delete a todo")
      |> route.operation_id("deleteTodo")
      |> route.tags(["todos"])
      |> route.path_param("id", param.string())
      |> route.returns_empty(204, "Deleted")
      |> route.returns(404, ref("ApiError")),
    route.get("/users/{id}", get_user)
      |> route.summary("Get a user by id")
      |> route.operation_id("getUser")
      |> route.tags(["users"])
      |> route.path_param("id", param.string())
      |> route.returns(200, ref("User"))
      |> route.returns(404, ref("ApiError")),
  ]
}

/// Dispatch a request to the matching route's handler. Uses the same `routes()`
/// that generates the document.
pub fn handle(request: wisp.Request) -> wisp.Response {
  let method = string.lowercase(http.method_to_string(request.method))
  case route.match(routes(), method, wisp.path_segments(request)) {
    Ok(route.Matched(handler, path_params)) -> handler(request, path_params)
    Error(Nil) -> wisp.not_found()
  }
}

// --- handlers (canned responses that match the schemas) ----------------------

fn list_todos(_request: wisp.Request, _params) -> wisp.Response {
  ok(todo_page())
}

fn create_todo(_request: wisp.Request, _params) -> wisp.Response {
  wisp.json_response(json.to_string(todo_json("created-id")), 201)
}

fn get_todo(_request: wisp.Request, params) -> wisp.Response {
  case path_param(params, "id") {
    "missing" -> error(404, "todo not found")
    id -> ok(todo_json(id))
  }
}

fn replace_todo(_request: wisp.Request, params) -> wisp.Response {
  ok(todo_json(path_param(params, "id")))
}

fn delete_todo(_request: wisp.Request, _params) -> wisp.Response {
  wisp.no_content()
}

fn get_user(_request: wisp.Request, params) -> wisp.Response {
  case path_param(params, "id") {
    "missing" -> error(404, "user not found")
    id -> ok(user(id))
  }
}

fn path_param(params: List(#(String, String)), name: String) -> String {
  case list.key_find(params, name) {
    Ok(value) -> value
    Error(Nil) -> ""
  }
}

// --- json bodies -------------------------------------------------------------

fn ok(value: Json) -> wisp.Response {
  wisp.json_response(json.to_string(value), 200)
}

fn error(status: Int, message: String) -> wisp.Response {
  wisp.json_response(
    json.to_string(
      json.object([
        #("message", json.string(message)),
        #("code", json.int(status)),
      ]),
    ),
    status,
  )
}

fn user(id: String) -> Json {
  json.object([
    #("id", json.string(id)),
    #("name", json.string("Ada")),
    #("email", json.string("ada@example.com")),
  ])
}

fn todo_json(id: String) -> Json {
  json.object([
    #("id", json.string(id)),
    #("title", json.string("Write the docs")),
    #("done", json.bool(False)),
    #("rank", json.int(1)),
    #("score", json.float(0.5)),
    #("tags", json.array(["home", "work"], json.string)),
    #("note", json.null()),
    #("owner", user("u1")),
    #("priority", json.string("High")),
    #("labels", json.object([#("urgent", json.int(2))])),
  ])
}

fn todo_page() -> Json {
  json.object([
    #("items", json.preprocessed_array([todo_json("t1"), todo_json("t2")])),
    #("total", json.int(2)),
    #("next", json.null()),
  ])
}
