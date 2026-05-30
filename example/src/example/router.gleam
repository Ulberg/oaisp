//// The Wisp request handler. It serves responses that match the schemas the
//// endpoints declare, so a client generated from the OpenAPI document can call
//// it for real (see `e2e/live.mjs`). The bodies are canned — this is an
//// example, not a database.

import gleam/http
import gleam/json.{type Json}
import wisp

pub fn handle(request: wisp.Request) -> wisp.Response {
  case wisp.path_segments(request), request.method {
    ["todos"], http.Get -> json_ok(todo_page())
    ["todos"], http.Post ->
      wisp.json_response(json.to_string(todo_json("created-id")), 201)
    ["todos", "missing"], http.Get -> api_error(404, "todo not found")
    ["todos", id], http.Get -> json_ok(todo_json(id))
    ["todos", id], http.Put -> json_ok(todo_json(id))
    ["todos", _id], http.Delete -> wisp.no_content()
    ["users", "missing"], http.Get -> api_error(404, "user not found")
    ["users", id], http.Get -> json_ok(user(id))
    _, _ -> wisp.not_found()
  }
}

fn json_ok(value: Json) -> wisp.Response {
  wisp.json_response(json.to_string(value), 200)
}

fn api_error(status: Int, message: String) -> wisp.Response {
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
