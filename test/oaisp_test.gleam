import gleeunit
import gleeunit/should
import oaisp

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_test() {
  oaisp.version
  |> should.equal("0.1.0")
}
