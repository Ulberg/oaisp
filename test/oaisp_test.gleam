import gleeunit
import oaisp
import oaisp/route
import oaisp/schema

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_test() {
  assert oaisp.version == "0.1.0"
}

pub fn type_ref_reexport_test() {
  assert oaisp.type_ref("myapp/types", "Todo")
    == schema.type_ref("myapp/types", "Todo")
}

pub fn add_openapi_passes_builder_through_test() {
  // With no --emit-endpoints flag the hook returns the builder untouched. It is
  // generic in both the builder and the route handler, so plain strings stand
  // in for both here.
  let routes = [route.get("/x", "handler")]
  assert oaisp.add_openapi("server-builder", routes, oaisp.info("API", "1.0.0"))
    == "server-builder"
}
