//// Minimal filesystem access over the Erlang/OTP `file` module.
////
//// oaisp targets Erlang only, so it talks to `file` directly through FFI
//// rather than depending on a cross-target shim. The error is the OTP reason
//// (e.g. `"enoent"`, `"eacces"`) as a string.

import gleam/bit_array
import gleam/result

@external(erlang, "oaisp_ffi", "read_file")
fn erl_read_file(path: String) -> Result(BitArray, String)

@external(erlang, "oaisp_ffi", "write_file")
fn erl_write_file(path: String, data: String) -> Result(Nil, String)

@external(erlang, "oaisp_ffi", "rename")
fn erl_rename(source: String, destination: String) -> Result(Nil, String)

@external(erlang, "oaisp_ffi", "delete")
fn erl_delete(path: String) -> Result(Nil, String)

/// Read a file as a UTF-8 string.
pub fn read(path: String) -> Result(String, String) {
  use bytes <- result.try(erl_read_file(path))
  bit_array.to_string(bytes)
  |> result.replace_error("file is not valid UTF-8")
}

/// Write a string to a file, replacing any existing contents.
pub fn write(path: String, contents: String) -> Result(Nil, String) {
  erl_write_file(path, contents)
}

/// Rename (move) a file. Atomic when source and destination share a filesystem.
pub fn rename(source: String, destination: String) -> Result(Nil, String) {
  erl_rename(source, destination)
}

/// Delete a file.
pub fn delete(path: String) -> Result(Nil, String) {
  erl_delete(path)
}
