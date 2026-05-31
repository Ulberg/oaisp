//// oaisp — a code-first OpenAPI 3.1 generator for Wisp applications on the BEAM.
////
//// You declare your API as a list of [`Route`](./oaisp/route.html)s — each
//// binding a path + method to a handler and carrying its OpenAPI annotations.
//// That single list drives both your running server (`route.match`) and the
//// emitted document, so the two can't drift. One CLI command
//// (`gleam run -m oaisp/cli generate`) writes a truthful OpenAPI 3.1 document
//// at build time.
////
//// This module is the public surface. The route builders live in
//// [`oaisp/route`](./oaisp/route.html), scalar param helpers in
//// [`oaisp/param`](./oaisp/param.html), and the CLI in
//// [`oaisp/cli`](./oaisp/cli.html).

import argv
import gleam/io
import gleam/list
import oaisp/info as info_module
import oaisp/internal/emit
import oaisp/route
import oaisp/schema as schema_module

/// The version of the oaisp library.
pub const version: String = "0.1.0"

/// A schema reference for a body, response, or parameter. See
/// [`oaisp/schema`](./oaisp/schema.html).
pub type Schema =
  schema_module.Schema

/// The primitive kinds an inline scalar schema can take.
pub type ScalarKind =
  schema_module.ScalarKind

/// The top-level metadata for the emitted document.
pub type Info =
  info_module.Info

/// A route: a path + method bound to a handler, plus its OpenAPI annotations.
/// See [`oaisp/route`](./oaisp/route.html).
pub type Route(handler) =
  route.Route(handler)

/// A schema referring to a public Gleam type, resolved at merge time from the
/// package interface.
pub fn type_ref(module module: String, name name: String) -> Schema {
  schema_module.type_ref(module:, name:)
}

/// Document metadata with no description and no servers; spread to override.
pub fn info(title title: String, version version: String) -> Info {
  info_module.info(title:, version:)
}

/// The build-time hook. Drop it into your server builder pipeline alongside the
/// same `routes` you dispatch with `route.match`:
///
/// ```gleam
/// wisp_mist.handler(handle(routes), secret_key_base)
/// |> mist.new
/// |> oaisp.add_openapi(routes, info)
/// |> mist.port(8080)
/// |> mist.start
/// ```
///
/// Run with `--emit-endpoints` (as the CLI does internally) it prints the
/// declarations and exits; otherwise it returns `builder` untouched. It is
/// generic in the builder and never inspects it, so oaisp needs no dependency
/// on `mist` or any server library.
pub fn add_openapi(builder: a, routes: List(Route(handler)), info: Info) -> a {
  case list.contains(argv.load().arguments, "--emit-endpoints") {
    True -> {
      io.println(
        emit.to_string(emit.Document(
          info:,
          endpoints: route.to_endpoints(routes),
        )),
      )
      halt(0)
    }
    False -> builder
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> a
