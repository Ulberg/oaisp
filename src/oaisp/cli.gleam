//// `gleam run -m oaisp/cli` — the build-time CLI.
////
//// `generate` orchestrates the pipeline: it runs `gleam export
//// package-interface` for the resolved type information, runs `gleam run --
//// --emit-endpoints` to collect the endpoint declarations the app wires into
//// `add_openapi`, merges the two, and writes the document atomically.
////
//// Status messages always go to stderr; with `generate -o -` the document is
//// the only thing on stdout, so it can be piped to other tools.

import argv
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import oaisp/internal/argv as cli_args
import oaisp/internal/atomic_write
import oaisp/internal/emit
import oaisp/internal/exec
import oaisp/internal/fs
import oaisp/internal/merge
import oaisp/internal/package_interface as pkg

const package_interface_temp = "build/oaisp_package_interface.json"

/// CLI entrypoint.
pub fn main() -> Nil {
  case argv.load().arguments {
    ["generate", ..rest] -> generate(rest)
    [] | ["help"] | ["--help"] | ["-h"] -> io.println(help_text())
    [command, ..] -> {
      log_error("unknown command `" <> command <> "`")
      io.println_error(help_text())
      halt(2)
    }
  }
}

// --- generate ----------------------------------------------------------------

fn generate(arguments: List(String)) -> Nil {
  case cli_args.parse(arguments) {
    Error(error) -> {
      log_error(arg_error_message(error))
      halt(2)
    }
    Ok(options) ->
      case run_generate(options) {
        Ok(Nil) -> Nil
        Error(message) -> {
          log_error(message)
          halt(1)
        }
      }
  }
}

fn run_generate(options: cli_args.Options) -> Result(Nil, String) {
  let log = logger(options)
  use #(package_interface_json, endpoints_json) <- result.try(gather(
    options,
    log,
  ))
  use document <- result.try(build_document(
    package_interface_json,
    endpoints_json,
  ))

  case options.out {
    cli_args.ToStdout -> {
      io.println(document)
      Ok(Nil)
    }
    cli_args.ToFile(path) -> {
      use _ <- result.try(
        atomic_write.write(path, document)
        |> result.map_error(fn(reason) {
          "could not write " <> path <> ": " <> reason
        }),
      )
      log("wrote " <> path)
      Ok(Nil)
    }
  }
}

/// Build the OpenAPI document from the two JSON inputs the pipeline gathers.
/// Pure, so the heart of `generate` is testable without shelling out.
pub fn build_document(
  package_interface_json: String,
  endpoints_json: String,
) -> Result(String, String) {
  use #(package, document) <- result.try(decode_inputs(
    package_interface_json,
    endpoints_json,
  ))
  case merge.duplicate_routes(document.endpoints) {
    [] ->
      case merge.path_param_mismatches(document.endpoints) {
        [] ->
          case merge.unresolved_refs(document.endpoints, package) {
            [] ->
              case merge.malformed_formats(document.endpoints, package) {
                [] ->
                  Ok(merge.to_string(document.endpoints, document.info, package))
                formats -> Error(malformed_formats_message(formats))
              }
            refs -> Error(unresolved_refs_message(refs))
          }
        mismatches -> Error(path_param_mismatches_message(mismatches))
      }
    routes -> Error(duplicate_routes_message(routes))
  }
}

/// Two routes with the same method and path would describe one operation in the
/// document while the server runs only the first — the document and the server
/// would disagree. List the offenders so the stray route is easy to find.
fn duplicate_routes_message(routes: List(#(String, String))) -> String {
  let bullets =
    routes
    |> list.map(fn(route) {
      "  - " <> string.uppercase(route.0) <> " " <> route.1
    })
    |> string.join("\n")
  "these routes share a method and path — each (method, path) must be unique, or "
  <> "the generated document and your running server will drift:\n"
  <> bullets
}

/// A `type_ref` that doesn't resolve would leave a dangling `$ref` in the
/// document. List the offenders so the typo — or the missing `pub` — is obvious.
fn unresolved_refs_message(refs: List(#(String, String))) -> String {
  let bullets =
    refs
    |> list.map(fn(ref) { "  - " <> ref.0 <> "." <> ref.1 })
    |> string.join("\n")
  "these type references don't resolve against the package interface — check the "
  <> "module path and name, and that the type is public:\n"
  <> bullets
}

/// A path parameter that doesn't match the path template leaves an invalid
/// OpenAPI 3.1 document. List the offenders — the endpoint and whether a
/// parameter has no placeholder, or a placeholder has no parameter — so the
/// missing declaration or the typo is obvious.
fn path_param_mismatches_message(
  mismatches: List(merge.PathParamMismatch),
) -> String {
  let bullets =
    mismatches
    |> list.map(fn(mismatch) {
      case mismatch {
        merge.ParamWithoutPlaceholder(method:, path:, name:) ->
          "  - "
          <> method
          <> " "
          <> path
          <> ": path parameter `"
          <> name
          <> "` has no matching `{"
          <> name
          <> "}` in the path"
        merge.PlaceholderWithoutParam(method:, path:, name:) ->
          "  - "
          <> method
          <> " "
          <> path
          <> ": `{"
          <> name
          <> "}` in the path has no declared path parameter"
      }
    })
    |> string.join("\n")
  "these path parameters don't match the path template — every `in: path` "
  <> "parameter must name a `{placeholder}`, and every placeholder must be "
  <> "declared:\n"
  <> bullets
}

/// A malformed `@format` directive is dropped at emit time, so the format it
/// asked for never reaches the schema. List the offenders — the type and the
/// line — so the typo (a missing colon, an empty field or format) is obvious.
fn malformed_formats_message(
  formats: List(#(String, String, String)),
) -> String {
  let bullets =
    formats
    |> list.map(fn(format) {
      let #(module, name, line) = format
      "  - " <> module <> "." <> name <> ": " <> line
    })
    |> string.join("\n")
  "these `@format` directives are malformed — each must read `@format <field>: "
  <> "<format>`:\n"
  <> bullets
}

// --- shared pipeline ---------------------------------------------------------

fn gather(
  options: cli_args.Options,
  log: fn(String) -> Nil,
) -> Result(#(String, String), String) {
  use package_interface_json <- result.try(package_interface_source(
    options,
    log,
  ))
  log("collecting endpoint declarations")
  use endpoints_json <- result.try(emit_endpoints())
  Ok(#(package_interface_json, endpoints_json))
}

fn package_interface_source(
  options: cli_args.Options,
  log: fn(String) -> Nil,
) -> Result(String, String) {
  case options.package_interface {
    Some(path) -> {
      log("reading package interface from " <> path)
      read_file(path)
    }
    None -> {
      log("running `gleam export package-interface`")
      export_package_interface()
    }
  }
}

fn decode_inputs(
  package_interface_json: String,
  endpoints_json: String,
) -> Result(#(pkg.Package, emit.Document), String) {
  use package <- result.try(
    pkg.decode_string(package_interface_json)
    |> result.map_error(fn(_) { "could not decode the package interface" }),
  )
  use document <- result.try(
    emit.parse(endpoints_json)
    |> result.map_error(fn(_) { "could not parse the emitted endpoints" }),
  )
  Ok(#(package, document))
}

fn export_package_interface() -> Result(String, String) {
  let output =
    exec.run("gleam export package-interface --out " <> package_interface_temp)
  case output.exit_code {
    0 -> read_file(package_interface_temp)
    code ->
      Error(
        "`gleam export package-interface` exited with " <> int.to_string(code),
      )
  }
}

fn emit_endpoints() -> Result(String, String) {
  let output = exec.run("gleam run -- --emit-endpoints")
  case output.exit_code {
    0 -> Ok(output.stdout)
    code ->
      Error(
        "`gleam run -- --emit-endpoints` exited with " <> int.to_string(code),
      )
  }
}

fn read_file(path: String) -> Result(String, String) {
  fs.read(path)
  |> result.map_error(fn(reason) { "could not read " <> path <> ": " <> reason })
}

fn logger(options: cli_args.Options) -> fn(String) -> Nil {
  fn(message) {
    case options.quiet {
      True -> Nil
      False -> log_status(message)
    }
  }
}

fn arg_error_message(error: cli_args.Error) -> String {
  case error {
    cli_args.UnknownFlag(flag) -> "unknown flag `" <> flag <> "`"
    cli_args.MissingValue(flag) -> "`" <> flag <> "` needs a value"
  }
}

fn log_status(message: String) -> Nil {
  io.println_error("oaisp: " <> message)
}

fn log_error(message: String) -> Nil {
  io.println_error("oaisp: error: " <> message)
}

fn help_text() -> String {
  "oaisp — generate an OpenAPI 3.1 document from your Gleam code

USAGE:
  gleam run -m oaisp/cli <COMMAND> [OPTIONS]

COMMANDS:
  generate             Emit the OpenAPI 3.1 document

OPTIONS:
  -o, --out <PATH>              Output path (default ./openapi.json; - for stdout)
      --package-interface <PATH>  Use this package-interface.json instead of
                                  running `gleam export package-interface`
      --quiet                   Suppress status output on stderr
  -h, --help                    Print this help"
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> a
