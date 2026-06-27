import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string
import oaisp/cli
import oaisp/endpoint
import oaisp/info
import oaisp/internal/emit
import oaisp/internal/exec
import oaisp/internal/fs
import oaisp/param
import oaisp/schema

fn todo_ref() -> schema.Schema {
  schema.type_ref("shop/types", "Todo")
}

fn package_interface_json() -> String {
  let assert Ok(content) = fs.read("test/fixtures/package_interface.json")
  content
}

fn endpoints_json() -> String {
  emit.to_string(
    emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
      endpoint.get("/todos/{id}")
      |> endpoint.with_path_param("id", param.string())
      |> endpoint.with_response(200, todo_ref()),
    ]),
  )
}

pub fn build_document_test() {
  let assert Ok(document) =
    cli.build_document(package_interface_json(), endpoints_json())
  assert json.parse(document, decode.at(["openapi"], decode.string))
    == Ok("3.1.0")
  assert json.parse(
      document,
      decode.at(["components", "schemas", "Todo", "type"], decode.string),
    )
    == Ok("object")
}

pub fn build_document_rejects_bad_package_interface_test() {
  assert result.is_error(cli.build_document("not json", endpoints_json()))
}

pub fn build_document_rejects_bad_endpoints_test() {
  assert result.is_error(cli.build_document(
    package_interface_json(),
    "not json",
  ))
}

pub fn build_document_rejects_unresolved_ref_test() {
  // A `type_ref` to a type the interface knows the module of but not the name
  // (a typo or a missing `pub`) is rejected, not emitted as a dangling `$ref`.
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
        endpoint.get("/todos")
        |> endpoint.with_response(200, schema.type_ref("shop/types", "Ghost")),
      ]),
    )
  assert result.is_error(cli.build_document(package_interface_json(), endpoints))
}

pub fn build_document_rejects_unresolved_query_record_test() {
  // `query_record` is a type reference too; typos should be reported rather
  // than silently producing an operation with missing reflected parameters.
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
        endpoint.get("/todos")
        |> endpoint.with_query_record(schema.type_ref("shop/types", "Ghost")),
      ]),
    )
  assert result.is_error(cli.build_document(package_interface_json(), endpoints))
}

pub fn build_document_rejects_duplicate_routes_test() {
  // Two routes with the same method and path collapse to one operation in the
  // document while the server serves only the first — reject it, naming the
  // offender, rather than letting the document and the server drift apart.
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
        endpoint.get("/todos") |> endpoint.with_response(200, todo_ref()),
        endpoint.get("/todos") |> endpoint.with_response(201, todo_ref()),
      ]),
    )
  let assert Error(message) =
    cli.build_document(package_interface_json(), endpoints)
  assert string.contains(message, "GET /todos")
}

pub fn build_document_allows_same_path_different_methods_test() {
  // A shared path is fine while the methods differ: GET and POST /todos are
  // distinct operations, not a duplicate.
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
        endpoint.get("/todos") |> endpoint.with_response(200, todo_ref()),
        endpoint.post("/todos")
          |> endpoint.with_body(todo_ref())
          |> endpoint.with_response(201, todo_ref()),
      ]),
    )
  assert result.is_ok(cli.build_document(package_interface_json(), endpoints))
}

pub fn build_document_rejects_path_param_without_placeholder_test() {
  // A declared `in: path` parameter with no `{id}` in the path template is
  // invalid OpenAPI 3.1; the error must name the offending endpoint.
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
        endpoint.get("/todos")
        |> endpoint.with_path_param("id", param.string())
        |> endpoint.with_response(200, todo_ref()),
      ]),
    )
  let assert Error(message) =
    cli.build_document(package_interface_json(), endpoints)
  assert string.contains(message, "get /todos")
  assert string.contains(message, "id")
}

pub fn build_document_rejects_placeholder_without_path_param_test() {
  // A `{id}` placeholder with no declared path parameter leaves it
  // undocumented; the error must name the offending endpoint.
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Todo API", "1.0.0"), endpoints: [
        endpoint.get("/todos/{id}")
        |> endpoint.with_response(200, todo_ref()),
      ]),
    )
  let assert Error(message) =
    cli.build_document(package_interface_json(), endpoints)
  assert string.contains(message, "get /todos/{id}")
  assert string.contains(message, "id")
}

pub fn build_document_accepts_matched_path_param_test() {
  // A declared parameter that matches its `{id}` placeholder is valid.
  assert result.is_ok(cli.build_document(
    package_interface_json(),
    endpoints_json(),
  ))
}

pub fn build_document_rejects_malformed_format_directive_test() {
  // A `@format` directive on a reached type that isn't `@format <field>: <format>`
  // (here a line with no colon) is reported before emit — naming the type and the
  // offending line — rather than being silently dropped from the schema.
  let assert Ok(package_interface) =
    fs.read("test/fixtures/format_package_interface.json")
  let endpoints =
    emit.to_string(
      emit.Document(info: info.info("Contacts", "1.0.0"), endpoints: [
        endpoint.get("/contacts")
        |> endpoint.with_response(
          200,
          schema.type_ref("contacts/types", "Contact"),
        ),
      ]),
    )
  let assert Error(message) = cli.build_document(package_interface, endpoints)
  assert string.contains(message, "Contact")
  assert string.contains(message, "@format brokenline")
}

pub fn exec_captures_stdout_and_exit_code_test() {
  let output = exec.run("printf hello")
  assert output.exit_code == 0
  assert output.stdout == "hello"
}
