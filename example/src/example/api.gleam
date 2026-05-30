//// The endpoint declarations for the example API. `oaisp generate` resolves
//// each `type_ref` against the package interface and projects these into the
//// OpenAPI document — covering path params, query params, request bodies, and
//// several response shapes across every HTTP method.

import oaisp
import oaisp/param

fn ref(name: String) -> oaisp.Schema {
  oaisp.type_ref("example/types", name)
}

pub fn endpoints() -> List(oaisp.Endpoint) {
  [
    oaisp.get("/todos")
      |> oaisp.with_query_param("limit", param.int(), False)
      |> oaisp.with_query_param("tag", param.string(), False)
      |> oaisp.with_response(200, ref("TodoPage"))
      |> oaisp.with_summary("List todos")
      |> oaisp.with_operation_id("listTodos")
      |> oaisp.with_tag("todos"),
    oaisp.post("/todos")
      |> oaisp.with_body(ref("NewTodo"))
      |> oaisp.with_response(201, ref("Todo"))
      |> oaisp.with_response(400, ref("ApiError"))
      |> oaisp.with_summary("Create a todo")
      |> oaisp.with_operation_id("createTodo")
      |> oaisp.with_tag("todos"),
    oaisp.get("/todos/{id}")
      |> oaisp.with_path_param("id", param.string())
      |> oaisp.with_response(200, ref("Todo"))
      |> oaisp.with_response(404, ref("ApiError"))
      |> oaisp.with_summary("Get a todo by id")
      |> oaisp.with_operation_id("getTodo")
      |> oaisp.with_tag("todos"),
    oaisp.put("/todos/{id}")
      |> oaisp.with_path_param("id", param.string())
      |> oaisp.with_body(ref("Todo"))
      |> oaisp.with_response(200, ref("Todo"))
      |> oaisp.with_response(404, ref("ApiError"))
      |> oaisp.with_summary("Replace a todo")
      |> oaisp.with_operation_id("replaceTodo")
      |> oaisp.with_tag("todos"),
    oaisp.delete("/todos/{id}")
      |> oaisp.with_path_param("id", param.string())
      |> oaisp.with_empty_response(204, "Deleted")
      |> oaisp.with_response(404, ref("ApiError"))
      |> oaisp.with_summary("Delete a todo")
      |> oaisp.with_operation_id("deleteTodo")
      |> oaisp.with_tag("todos"),
    oaisp.get("/users/{id}")
      |> oaisp.with_path_param("id", param.string())
      |> oaisp.with_response(200, ref("User"))
      |> oaisp.with_response(404, ref("ApiError"))
      |> oaisp.with_summary("Get a user by id")
      |> oaisp.with_operation_id("getUser")
      |> oaisp.with_tag("users"),
  ]
}
