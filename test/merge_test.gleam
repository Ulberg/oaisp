import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import gleam/string
import oaisp/endpoint
import oaisp/info
import oaisp/internal/fs
import oaisp/internal/merge
import oaisp/internal/package_interface as pkg
import oaisp/param
import oaisp/schema

fn package() -> pkg.Package {
  let assert Ok(content) = fs.read("test/fixtures/package_interface.json")
  let assert Ok(decoded) = pkg.decode_string(content)
  decoded
}

fn todo_ref() -> schema.Schema {
  schema.type_ref("shop/types", "Todo")
}

fn package_with_duplicate_todo() -> pkg.Package {
  let assert Ok(content) = fs.read("test/fixtures/package_interface.json")
  let other_module =
    "\"shop/other\":{"
    <> "\"documentation\":[],"
    <> "\"type-aliases\":{},"
    <> "\"types\":{"
    <> "\"Todo\":{"
    <> "\"documentation\":\" Other todo.\\n\","
    <> "\"deprecation\":null,"
    <> "\"parameters\":0,"
    <> "\"constructors\":[{"
    <> "\"documentation\":null,"
    <> "\"name\":\"Todo\","
    <> "\"parameters\":[{"
    <> "\"label\":\"slug\","
    <> "\"type\":{"
    <> "\"kind\":\"named\","
    <> "\"name\":\"String\","
    <> "\"package\":\"\","
    <> "\"module\":\"gleam\","
    <> "\"parameters\":[]"
    <> "}}]}]}},"
    <> "\"constants\":{},"
    <> "\"functions\":{}"
    <> "}"
  let assert Ok(#(before, after)) =
    string.split_once(content, "\"modules\":{\"shop/types\":")
  let with_duplicate =
    before <> "\"modules\":{" <> other_module <> ",\"shop/types\":" <> after
  let assert Ok(decoded) = pkg.decode_string(with_duplicate)
  decoded
}

fn endpoints() -> List(endpoint.Endpoint) {
  [
    endpoint.get("/todos")
      |> endpoint.with_query_param(
        "limit",
        schema.Scalar(schema.IntKind, None),
        False,
      )
      |> endpoint.with_response(200, todo_ref())
      |> endpoint.with_summary("List todos")
      |> endpoint.with_tag("todos"),
    endpoint.post("/todos")
      |> endpoint.with_body(todo_ref())
      |> endpoint.with_response(201, todo_ref()),
    endpoint.get("/todos/{id}")
      |> endpoint.with_path_param("id", param.string())
      |> endpoint.with_response(200, todo_ref())
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

pub fn float_format_test() {
  // Gleam Float is an IEEE-754 double on the BEAM, so it carries format double.
  assert at(
      ["components", "schemas", "Todo", "properties", "score", "type"],
      decode.string,
    )
    == Ok("number")
  assert at(
      ["components", "schemas", "Todo", "properties", "score", "format"],
      decode.string,
    )
    == Ok("double")
  // Int is arbitrary precision, so it carries no (int32/int64) format.
  let assert Error(_) =
    at(
      ["components", "schemas", "Todo", "properties", "rank", "format"],
      decode.string,
    )
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

pub fn reflected_query_record_test() {
  // `with_query_record` reflects the record's scalar fields into query params:
  // scalars required, the Option optional, the List(String) an array param, and
  // non-scalar fields (the User ref, Status enum, Dict) soundly omitted.
  let eps = [endpoint.get("/search") |> endpoint.with_query_record(todo_ref())]
  let doc = merge.to_string(eps, info.info("Search", "1.0.0"), package())
  let param = {
    use name <- decode.field("name", decode.string)
    use location <- decode.field("in", decode.string)
    use required <- decode.field("required", decode.bool)
    use kind <- decode.subfield(["schema", "type"], decode.string)
    decode.success(#(name, location, required, kind))
  }
  assert json.parse(
      doc,
      decode.at(["paths", "/search", "get", "parameters"], decode.list(param)),
    )
    == Ok([
      #("id", "query", True, "string"),
      #("title", "query", True, "string"),
      #("done", "query", True, "boolean"),
      #("rank", "query", True, "integer"),
      #("score", "query", True, "number"),
      #("tags", "query", True, "array"),
      #("note", "query", False, "string"),
    ])
}

pub fn external_ref_with_same_name_as_component_is_not_mislinked_test() {
  let eps = [
    endpoint.get("/local") |> endpoint.with_response(200, todo_ref()),
    endpoint.get("/external")
      |> endpoint.with_response(
        200,
        schema.type_ref("dependency/types", "Todo"),
      ),
  ]
  let doc = merge.to_string(eps, info.info("Todos", "1.0.0"), package())

  assert json.parse(
      doc,
      decode.at(
        [
          "paths", "/local", "get", "responses", "200", "content",
          "application/json", "schema", "$ref",
        ],
        decode.string,
      ),
    )
    == Ok("#/components/schemas/Todo")

  let assert Error(_) =
    json.parse(
      doc,
      decode.at(
        [
          "paths", "/external", "get", "responses", "200", "content",
          "application/json", "schema", "$ref",
        ],
        decode.string,
      ),
    )
}

pub fn duplicate_type_names_get_namespaced_components_test() {
  let eps = [
    endpoint.get("/todos") |> endpoint.with_response(200, todo_ref()),
    endpoint.get("/other-todos")
      |> endpoint.with_response(200, schema.type_ref("shop/other", "Todo")),
  ]
  let doc =
    merge.to_string(
      eps,
      info.info("Todos", "1.0.0"),
      package_with_duplicate_todo(),
    )

  assert json.parse(
      doc,
      decode.at(
        [
          "paths", "/todos", "get", "responses", "200", "content",
          "application/json", "schema", "$ref",
        ],
        decode.string,
      ),
    )
    == Ok("#/components/schemas/shop.types.Todo")
  assert json.parse(
      doc,
      decode.at(
        [
          "paths", "/other-todos", "get", "responses", "200", "content",
          "application/json", "schema", "$ref",
        ],
        decode.string,
      ),
    )
    == Ok("#/components/schemas/shop.other.Todo")
  assert json.parse(
      doc,
      decode.at(
        ["components", "schemas", "shop.other.Todo", "type"],
        decode.string,
      ),
    )
    == Ok("object")
  assert json.parse(
      doc,
      decode.at(
        ["components", "schemas", "shop.types.Todo", "type"],
        decode.string,
      ),
    )
    == Ok("object")
}
