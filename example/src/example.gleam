//// Entry point. `oaisp generate` runs this with `--emit-endpoints`, at which
//// point `add_openapi` prints the declarations and exits.
////
//// In a real Wisp app this is your server pipeline:
////
//// ```gleam
//// wisp_mist.handler(router.handle_request, secret_key_base)
//// |> mist.new
//// |> oaisp.add_openapi(api.endpoints(), info)
//// |> mist.port(8080)
//// |> mist.start
//// ```
////
//// `add_openapi` is a generic pass-through, so the placeholder builder below
//// stands in for the mist builder without pulling in a server dependency.

import example/api
import gleam/option.{Some}
import oaisp
import oaisp/info

pub fn main() {
  // `info` is a plain record: build the common case and spread to add a
  // description and the servers the API is reachable at.
  let document_info =
    info.Info(
      ..oaisp.info("Example Todo API", "1.0.0"),
      description: Some("A small API exercising every shape oaisp models."),
      servers: ["http://localhost:8080"],
    )
  let _placeholder_builder = oaisp.add_openapi(Nil, api.endpoints(), document_info)
  Nil
}
