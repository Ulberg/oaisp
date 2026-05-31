//// A real Wisp/mist server. The same `api.routes()` list drives both the
//// dispatch (`api.handle`, via `route.match`) and the generated document
//// (`oaisp.add_openapi`) — one source of truth.
////
//// Run normally it serves on port 8080. Run with `--emit-endpoints` (as
//// `oaisp generate` does internally), `add_openapi` prints the declarations
//// and exits before the server starts.

import example/api
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

  let document_info =
    info.Info(
      ..oaisp.info("Example Todo API", "1.0.0"),
      description: Some("A small API exercising every shape oaisp models."),
      servers: ["http://localhost:8080"],
    )

  let assert Ok(_) =
    wisp_mist.handler(api.handle, secret_key_base)
    |> mist.new
    |> oaisp.add_openapi(api.routes(), document_info)
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
