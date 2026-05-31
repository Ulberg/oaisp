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
  parse_with(arguments, default_options())
}

/// Parse starting from a caller-supplied default — e.g. `derive` defaults its
/// output to stdout rather than `./openapi.json`. Also the recursion step:
/// `options` carries the flags parsed so far.
pub fn parse_with(
  arguments: List(String),
  options: Options,
) -> Result(Options, Error) {
  case arguments {
    [] -> Ok(options)
    ["-o", value, ..rest] | ["--out", value, ..rest] ->
      parse_with(rest, Options(..options, out: parse_out(value)))
    ["-o"] | ["--out"] -> Error(MissingValue("--out"))
    ["--package-interface", value, ..rest] ->
      parse_with(rest, Options(..options, package_interface: Some(value)))
    ["--package-interface"] -> Error(MissingValue("--package-interface"))
    ["--quiet", ..rest] -> parse_with(rest, Options(..options, quiet: True))
    [flag, ..] -> Error(UnknownFlag(flag))
  }
}

fn parse_out(value: String) -> Output {
  case value {
    "-" -> ToStdout
    path -> ToFile(path)
  }
}
