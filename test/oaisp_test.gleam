import gleeunit
import oaisp
import oaisp/endpoint

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_test() {
  assert oaisp.version == "0.1.0"
}

pub fn add_openapi_passes_builder_through_test() {
  // With no --emit-endpoints flag the hook returns the builder untouched — and
  // it is generic, so any value stands in for the server builder.
  let builder = "server-builder"
  assert oaisp.add_openapi(builder, [], oaisp.info("API", "1.0.0")) == builder
}

pub fn reexported_builders_delegate_test() {
  let item = oaisp.type_ref("myapp/types", "Todo")
  let via_oaisp =
    oaisp.get("/x")
    |> oaisp.with_response(200, item)
    |> oaisp.with_summary("s")
  let direct =
    endpoint.get("/x")
    |> endpoint.with_response(200, item)
    |> endpoint.with_summary("s")
  assert via_oaisp == direct
}
