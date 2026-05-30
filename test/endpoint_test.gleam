import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import oaisp/codec
import oaisp/endpoint
import oaisp/param

fn todo_codec() -> codec.Codec(String) {
  codec.codec(
    decode: decode.string,
    encode: json.string,
    schema: codec.type_ref("myapp/types", "Todo"),
  )
}

pub fn get_sets_method_and_path_test() {
  let e = endpoint.get("/todos")
  assert endpoint.method(e) == endpoint.Get
  assert endpoint.path(e) == "/todos"
  assert endpoint.responses(e) == []
  assert endpoint.body(e) == None
}

pub fn builder_pipeline_test() {
  let e =
    endpoint.post("/todos")
    |> endpoint.with_body(todo_codec())
    |> endpoint.with_response(201, todo_codec())
    |> endpoint.with_summary("Create a todo")
    |> endpoint.with_tag("todos")
    |> endpoint.with_operation_id("createTodo")

  assert endpoint.method(e) == endpoint.Post
  assert endpoint.body(e) == Some(codec.TypeRef("myapp/types", "Todo"))
  assert endpoint.summary(e) == Some("Create a todo")
  assert endpoint.tags(e) == ["todos"]
  assert endpoint.operation_id(e) == Some("createTodo")
  assert endpoint.responses(e)
    == [
      endpoint.Response(201, Some(codec.TypeRef("myapp/types", "Todo")), None),
    ]
}

pub fn responses_keep_declaration_order_test() {
  let e =
    endpoint.get("/todos/{id}")
    |> endpoint.with_path_param("id", param.string())
    |> endpoint.with_response(200, todo_codec())
    |> endpoint.with_empty_response(404, "Not found")

  assert endpoint.path_params(e)
    == [endpoint.Param("id", codec.Scalar(codec.StringKind, None), True)]
  assert list.map(endpoint.responses(e), fn(r) { r.status }) == [200, 404]
}

pub fn method_to_string_test() {
  assert endpoint.method_to_string(endpoint.Get) == "get"
  assert endpoint.method_to_string(endpoint.Delete) == "delete"
}
