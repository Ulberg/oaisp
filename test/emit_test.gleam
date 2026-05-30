import gleam/option.{Some}
import oaisp/endpoint
import oaisp/info
import oaisp/internal/emit
import oaisp/param
import oaisp/schema

fn todo_ref() -> schema.Schema {
  schema.type_ref("myapp/types", "Todo")
}

/// The wire format must round-trip exactly: a declaration encoded by the app
/// and parsed by the CLI is the same declaration.
pub fn round_trip_test() {
  let document =
    emit.Document(
      info: info.Info("Todo API", "1.0.0", Some("Manage todos"), [
        "https://api.example.com",
      ]),
      endpoints: [
        endpoint.get("/todos")
          |> endpoint.with_response(200, todo_ref())
          |> endpoint.with_summary("List all todos")
          |> endpoint.with_tag("todos"),
        endpoint.post("/todos")
          |> endpoint.with_body(todo_ref())
          |> endpoint.with_response(201, todo_ref()),
        endpoint.get("/todos/{id}")
          |> endpoint.with_path_param("id", param.string())
          |> endpoint.with_query_param("verbose", param.bool(), False)
          |> endpoint.with_response(200, todo_ref())
          |> endpoint.with_empty_response(404, "Not found"),
      ],
    )

  let assert Ok(decoded) = emit.parse(emit.to_string(document))
  assert decoded == document
}

pub fn empty_document_round_trips_test() {
  let document = emit.Document(info: info.info("API", "0.0.1"), endpoints: [])
  let assert Ok(decoded) = emit.parse(emit.to_string(document))
  assert decoded == document
}
