import gleam/dynamic/decode
import gleam/json
import oaisp/codec
import oaisp/endpoint
import oaisp/info
import oaisp/internal/fs
import oaisp/internal/merge
import oaisp/internal/package_interface as pkg
import oaisp/param

fn package() -> pkg.Package {
  let assert Ok(content) = fs.read("test/fixtures/package_interface.json")
  let assert Ok(decoded) = pkg.decode_string(content)
  decoded
}

fn todo_codec() -> codec.Codec(Nil) {
  codec.codec(
    decode.success(Nil),
    fn(_) { json.null() },
    codec.type_ref("shop/types", "Todo"),
  )
}

fn endpoints() -> List(endpoint.Endpoint) {
  [
    endpoint.get("/todos")
      |> endpoint.with_query_param("limit", param.int(), False)
      |> endpoint.with_response(200, todo_codec())
      |> endpoint.with_summary("List todos")
      |> endpoint.with_tag("todos"),
    endpoint.post("/todos")
      |> endpoint.with_body(todo_codec())
      |> endpoint.with_response(201, todo_codec()),
    endpoint.get("/todos/{id}")
      |> endpoint.with_path_param("id", param.string())
      |> endpoint.with_response(200, todo_codec())
      |> endpoint.with_empty_response(404, "Not found"),
  ]
}

fn document() -> String {
  merge.to_string(endpoints(), info.info("Todo API", "1.0.0"), package())
}

fn at(
  path: List(String),
  inner: decode.Decoder(t),
) -> Result(t, json.DecodeError) {
  json.parse(document(), decode.at(path, inner))
}

pub fn openapi_version_test() {
  assert at(["openapi"], decode.string) == Ok("3.1.0")
}

pub fn info_test() {
  assert at(["info", "title"], decode.string) == Ok("Todo API")
  assert at(["info", "version"], decode.string) == Ok("1.0.0")
}

pub fn transitive_components_test() {
  // Referencing Todo must pull in the User record and Status enum it mentions.
  assert at(["components", "schemas", "User", "type"], decode.string)
    == Ok("object")
  assert at(
      ["components", "schemas", "Status", "enum"],
      decode.list(decode.string),
    )
    == Ok(["Active", "Done", "Archived"])
}

pub fn record_schema_test() {
  assert at(["components", "schemas", "Todo", "type"], decode.string)
    == Ok("object")
  // Every field except the Option is required, in declaration order.
  assert at(
      ["components", "schemas", "Todo", "required"],
      decode.list(decode.string),
    )
    == Ok([
      "id",
      "title",
      "done",
      "rank",
      "score",
      "tags",
      "owner",
      "status",
      "labels",
    ])
  assert at(
      ["components", "schemas", "Todo", "properties", "owner", "$ref"],
      decode.string,
    )
    == Ok("#/components/schemas/User")
  assert at(
      ["components", "schemas", "Todo", "properties", "tags", "type"],
      decode.string,
    )
    == Ok("array")
  assert at(
      ["components", "schemas", "Todo", "properties", "tags", "items", "type"],
      decode.string,
    )
    == Ok("string")
  assert at(
      [
        "components", "schemas", "Todo", "properties", "labels",
        "additionalProperties", "type",
      ],
      decode.string,
    )
    == Ok("integer")
}

pub fn nullable_option_field_test() {
  // An Option(String) field is not required and its type allows null.
  assert at(
      ["components", "schemas", "Todo", "properties", "note", "type"],
      decode.list(decode.string),
    )
    == Ok(["string", "null"])
}

pub fn paths_and_refs_test() {
  assert at(
      [
        "paths", "/todos", "get", "responses", "200", "content",
        "application/json", "schema", "$ref",
      ],
      decode.string,
    )
    == Ok("#/components/schemas/Todo")
  assert at(["paths", "/todos", "get", "summary"], decode.string)
    == Ok("List todos")
  assert at(
      [
        "paths", "/todos", "post", "requestBody", "content", "application/json",
        "schema", "$ref",
      ],
      decode.string,
    )
    == Ok("#/components/schemas/Todo")
}

pub fn responses_test() {
  assert at(
      ["paths", "/todos/{id}", "get", "responses", "404", "description"],
      decode.string,
    )
    == Ok("Not found")
  // A response declared without a description falls back to the status reason.
  assert at(
      ["paths", "/todos/{id}", "get", "responses", "200", "description"],
      decode.string,
    )
    == Ok("OK")
}

pub fn parameters_test() {
  let param_decoder = {
    use name <- decode.field("name", decode.string)
    use location <- decode.field("in", decode.string)
    use required <- decode.field("required", decode.bool)
    decode.success(#(name, location, required))
  }
  assert at(
      ["paths", "/todos/{id}", "get", "parameters"],
      decode.list(param_decoder),
    )
    == Ok([#("id", "path", True)])
  assert at(
      ["paths", "/todos", "get", "parameters"],
      decode.list(param_decoder),
    )
    == Ok([#("limit", "query", False)])
}
