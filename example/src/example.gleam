//// A real Wisp/mist server, with the one-line oaisp hook.
////
//// Run normally, it serves the API on port 8080. Run with `--emit-endpoints`
//// (as `oaisp generate` does internally), `add_openapi` prints the endpoint
//// declarations and exits before the server starts — that is the whole
//// integration.

import example/api
import example/router
import gleam/erlang/process
import gleam/option.{Some}
import mist
import oaisp
import oaisp/info
import wisp
import wisp/wisp_mist

pub fn main() {
  // (A real app would also call `wisp.configure_logger()`; we skip it so that
  // under `--emit-endpoints` the only thing on stdout is the emitted JSON.)
  let secret_key_base = wisp.random_string(64)

  // `info` is a plain record: build the common case and spread to add a
  // description and the servers the API is reachable at.
  let document_info =
    info.Info(
      ..oaisp.info("Example Todo API", "1.0.0"),
      description: Some("A small API exercising every shape oaisp models."),
      servers: ["http://localhost:8080"],
    )

  let assert Ok(_) =
    wisp_mist.handler(router.handle, secret_key_base)
    |> mist.new
    |> oaisp.add_openapi(api.endpoints(), document_info)
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
