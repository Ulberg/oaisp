//// `gleam run -m oaisp/cli` — the build-time CLI.
////
//// `generate` orchestrates the pipeline: it runs `gleam export
//// package-interface` for the resolved type information, runs `gleam run --
//// --emit-endpoints` to collect the endpoint declarations the app wires into
//// `add_openapi`, merges the two, and writes the document atomically. `lint`
//// runs the same collection, then reports the lint findings.
////
//// Status messages always go to stderr; with `generate -o -` the document is
//// the only thing on stdout, so it can be piped to other tools.

import argv
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import oaisp/internal/argv as cli_args
import oaisp/internal/atomic_write
import oaisp/internal/codegen
import oaisp/internal/diff
import oaisp/internal/emit
import oaisp/internal/exec
import oaisp/internal/fs
import oaisp/internal/lint
import oaisp/internal/merge
import oaisp/internal/package_interface as pkg

const package_interface_temp = "build/oaisp_package_interface.json"

/// CLI entrypoint.
pub fn main() -> Nil {
  case argv.load().arguments {
    ["generate", ..rest] -> generate(rest)
    ["lint", ..rest] -> lint_command(rest)
    ["diff", old, new, ..] -> diff_command(old, new)
    ["diff", ..] -> {
      log_error("diff needs two paths: oaisp diff <old.json> <new.json>")
      halt(2)
    }
    ["derive", ..rest] -> derive_command(rest)
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
  Ok(merge.to_string(document.endpoints, document.info, package))
}

// --- lint --------------------------------------------------------------------

fn lint_command(arguments: List(String)) -> Nil {
  case cli_args.parse(arguments) {
    Error(error) -> {
      log_error(arg_error_message(error))
      halt(2)
    }
    Ok(options) ->
      case run_lint(options) {
        Error(message) -> {
          log_error(message)
          halt(1)
        }
        Ok(findings) -> report(findings, options.quiet)
      }
  }
}

fn run_lint(options: cli_args.Options) -> Result(List(lint.Finding), String) {
  let log = logger(options)
  use #(package_interface_json, endpoints_json) <- result.try(gather(
    options,
    log,
  ))
  use #(package, document) <- result.try(decode_inputs(
    package_interface_json,
    endpoints_json,
  ))
  Ok(lint.lint(document.endpoints, package))
}

fn report(findings: List(lint.Finding), quiet: Bool) -> Nil {
  case findings {
    [] ->
      case quiet {
        True -> Nil
        False -> log_status("no issues found")
      }
    _ -> {
      list.each(findings, fn(finding) {
        io.println_error(format_finding(finding))
      })
      case lint.has_errors(findings) {
        True -> halt(1)
        False -> Nil
      }
    }
  }
}

fn format_finding(finding: lint.Finding) -> String {
  let severity = case finding.severity {
    lint.Violation -> "error"
    lint.Warning -> "warning"
  }
  finding.location <> ": " <> severity <> ": " <> finding.message
}

// --- diff --------------------------------------------------------------------

fn diff_command(old_path: String, new_path: String) -> Nil {
  case run_diff(old_path, new_path) {
    Error(message) -> {
      log_error(message)
      halt(1)
    }
    Ok(changes) -> report_changes(changes)
  }
}

fn run_diff(
  old_path: String,
  new_path: String,
) -> Result(List(diff.Change), String) {
  use old_document <- result.try(read_file(old_path))
  use new_document <- result.try(read_file(new_path))
  use old_spec <- result.try(
    diff.decode_spec(old_document)
    |> result.map_error(fn(message) { old_path <> ": " <> message }),
  )
  use new_spec <- result.try(
    diff.decode_spec(new_document)
    |> result.map_error(fn(message) { new_path <> ": " <> message }),
  )
  Ok(diff.diff(old_spec, new_spec))
}

fn report_changes(changes: List(diff.Change)) -> Nil {
  case changes {
    [] -> log_status("no changes")
    _ -> {
      list.each(changes, fn(change) { io.println_error(format_change(change)) })
      case diff.has_breaking(changes) {
        True -> halt(1)
        False -> Nil
      }
    }
  }
}

fn format_change(change: diff.Change) -> String {
  let tag = case change.breaking {
    True -> "BREAKING"
    False -> "non-breaking"
  }
  tag <> ": " <> change.description
}

// --- derive ------------------------------------------------------------------

fn derive_command(arguments: List(String)) -> Nil {
  // `derive` writes the generated module to stdout by default, not a file.
  let stdout_default = cli_args.Options(cli_args.ToStdout, None, False)
  case cli_args.parse_with(arguments, stdout_default) {
    Error(error) -> {
      log_error(arg_error_message(error))
      halt(2)
    }
    Ok(options) ->
      case run_derive(options) {
        Ok(Nil) -> Nil
        Error(message) -> {
          log_error(message)
          halt(1)
        }
      }
  }
}

fn run_derive(options: cli_args.Options) -> Result(Nil, String) {
  let log = logger(options)
  use package_interface_json <- result.try(package_interface_source(
    options,
    log,
  ))
  use package <- result.try(
    pkg.decode_string(package_interface_json)
    |> result.map_error(fn(_) { "could not decode the package interface" }),
  )
  let source = codegen.codecs(package)
  case options.out {
    cli_args.ToStdout -> {
      io.println(source)
      Ok(Nil)
    }
    cli_args.ToFile(path) -> {
      use _ <- result.try(
        atomic_write.write(path, source)
        |> result.map_error(fn(reason) {
          "could not write " <> path <> ": " <> reason
        }),
      )
      log("wrote " <> path)
      Ok(Nil)
    }
  }
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
  lint                 Check declarations: type-refs, path params, duplicates
  diff <old> <new>     Report breaking changes between two OpenAPI documents
  derive               Generate decoders + encoders for your public types
                       (to stdout by default; -o to write a module file)

OPTIONS:
  -o, --out <PATH>              Output path (default ./openapi.json; - for stdout)
      --package-interface <PATH>  Use this package-interface.json instead of
                                  running `gleam export package-interface`
      --quiet                   Suppress status output on stderr
  -h, --help                    Print this help"
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> a
