import gleam/option.{None, Some}
import oaisp/internal/argv

pub fn defaults_test() {
  assert argv.parse([])
    == Ok(argv.Options(argv.ToFile("./openapi.json"), None, False))
}

pub fn out_file_test() {
  let assert Ok(options) = argv.parse(["-o", "spec/openapi.json"])
  assert options.out == argv.ToFile("spec/openapi.json")
}

pub fn out_stdout_test() {
  let assert Ok(options) = argv.parse(["--out", "-"])
  assert options.out == argv.ToStdout
}

pub fn package_interface_and_quiet_test() {
  let assert Ok(options) =
    argv.parse(["--package-interface", "pi.json", "--quiet"])
  assert options.package_interface == Some("pi.json")
  assert options.quiet == True
}

pub fn missing_value_is_an_error_test() {
  assert argv.parse(["-o"]) == Error(argv.MissingValue("--out"))
}

pub fn unknown_flag_is_an_error_test() {
  assert argv.parse(["--bogus"]) == Error(argv.UnknownFlag("--bogus"))
}
