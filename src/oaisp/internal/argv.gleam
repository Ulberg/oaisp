//// A tiny parser for the `generate` command's flags. Kept pure (a list of
//// arguments in, options or an error out) so it is trivial to test.

import gleam/option.{type Option, None, Some}

/// Where the generated document should go.
pub type Output {
  ToFile(path: String)
  ToStdout
}

/// Options for `oaisp generate`.
pub type Options {
  Options(out: Output, package_interface: Option(String), quiet: Bool)
}

/// Why argument parsing failed.
pub type Error {
  UnknownFlag(flag: String)
  MissingValue(flag: String)
}

/// The default options: write `./openapi.json`, auto-discover the package
/// interface, status output on.
pub fn default_options() -> Options {
  Options(out: ToFile("./openapi.json"), package_interface: None, quiet: False)
}

/// Parse the flags accepted by `generate` (everything after the subcommand).
pub fn parse(arguments: List(String)) -> Result(Options, Error) {
  do_parse(arguments, default_options())
}

fn do_parse(
  arguments: List(String),
  options: Options,
) -> Result(Options, Error) {
  case arguments {
    [] -> Ok(options)
    ["-o", value, ..rest] | ["--out", value, ..rest] ->
      do_parse(rest, Options(..options, out: parse_out(value)))
    ["-o"] | ["--out"] -> Error(MissingValue("--out"))
    ["--package-interface", value, ..rest] ->
      do_parse(rest, Options(..options, package_interface: Some(value)))
    ["--package-interface"] -> Error(MissingValue("--package-interface"))
    ["--quiet", ..rest] -> do_parse(rest, Options(..options, quiet: True))
    [flag, ..] -> Error(UnknownFlag(flag))
  }
}

fn parse_out(value: String) -> Output {
  case value {
    "-" -> ToStdout
    path -> ToFile(path)
  }
}
