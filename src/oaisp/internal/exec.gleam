//// Run a child process and capture its stdout. Used by the CLI to drive
//// `gleam export package-interface` and `gleam run -- --emit-endpoints`.

import gleam/bit_array

/// The result of running a command.
pub type Output {
  Output(exit_code: Int, stdout: String)
}

@external(erlang, "oaisp_ffi", "run")
fn ffi_run(command: String) -> #(Int, BitArray)

/// Run `command` through the shell, capturing its stdout and exit code. stderr
/// is left attached to the parent process, so a child's progress output (e.g.
/// gleam's "Compiling…" lines) never pollutes the captured stdout.
pub fn run(command: String) -> Output {
  let #(exit_code, bytes) = ffi_run(command)
  let stdout = case bit_array.to_string(bytes) {
    Ok(text) -> text
    Error(Nil) -> ""
  }
  Output(exit_code:, stdout:)
}
