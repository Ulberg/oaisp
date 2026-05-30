import gleam/dynamic/decode
import gleam/json
import gleam/result
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

pub fn exec_captures_stdout_and_exit_code_test() {
  let output = exec.run("printf hello")
  assert output.exit_code == 0
  assert output.stdout == "hello"
}
