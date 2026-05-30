import gleam/list
import gleam/string
import oaisp/endpoint
import oaisp/internal/fs
import oaisp/internal/lint
import oaisp/internal/package_interface as pkg
import oaisp/param
import oaisp/schema

fn package() -> pkg.Package {
  let assert Ok(content) = fs.read("test/fixtures/package_interface.json")
  let assert Ok(decoded) = pkg.decode_string(content)
  decoded
}

fn type_for(name: String) -> schema.Schema {
  schema.type_ref("shop/types", name)
}

fn has(
  findings: List(lint.Finding),
  severity: lint.Severity,
  fragment: String,
) -> Bool {
  list.any(findings, fn(finding) {
    finding.severity == severity && string.contains(finding.message, fragment)
  })
}

pub fn clean_endpoint_has_no_findings_test() {
  let endpoints = [
    endpoint.get("/todos/{id}")
    |> endpoint.with_path_param("id", param.string())
    |> endpoint.with_response(200, type_for("Todo")),
  ]
  assert lint.lint(endpoints, package()) == []
}

pub fn missing_path_param_declaration_is_an_error_test() {
  let endpoints = [
    endpoint.get("/todos/{id}")
    |> endpoint.with_response(200, type_for("Todo")),
  ]
  let findings = lint.lint(endpoints, package())
  assert lint.has_errors(findings)
  assert has(findings, lint.Violation, "{id}")
}

pub fn declared_param_absent_from_path_is_an_error_test() {
  let endpoints = [
    endpoint.get("/todos")
    |> endpoint.with_path_param("id", param.string())
    |> endpoint.with_response(200, type_for("Todo")),
  ]
  assert has(
    lint.lint(endpoints, package()),
    lint.Violation,
    "absent from the path",
  )
}

pub fn duplicate_operation_is_an_error_test() {
  let make = fn() {
    endpoint.get("/todos") |> endpoint.with_response(200, type_for("Todo"))
  }
  assert has(
    lint.lint([make(), make()], package()),
    lint.Violation,
    "declared 2 times",
  )
}

pub fn unresolvable_type_ref_is_an_error_test() {
  let endpoints = [
    endpoint.get("/x") |> endpoint.with_response(200, type_for("Ghost")),
  ]
  assert has(lint.lint(endpoints, package()), lint.Violation, "Ghost")
}

pub fn under_described_type_is_a_warning_test() {
  // Token is a single positional-field newtype, so it resolves to Unmodelled.
  let endpoints = [
    endpoint.get("/x") |> endpoint.with_response(200, type_for("Token")),
  ]
  let findings = lint.lint(endpoints, package())
  assert has(findings, lint.Warning, "under-described")
  assert lint.has_errors(findings) == False
}
