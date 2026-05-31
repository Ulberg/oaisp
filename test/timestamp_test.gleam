//// Type-driven `date-time` formats from `gleam/time/timestamp.Timestamp`.
////
//// oaisp recognises the standard `Timestamp` by its `(package, module, name)`
//// in the package interface — so it takes no dependency on `gleam_time` and
//// never forces an oaisp-owned type onto consumers. Because `gleam_time` cannot
//// be fetched in this offline sandbox, the fixture below is a minimal package
//// interface in the exact shape `gleam export package-interface` emits (its
//// `Named`-type encoding is verified against `package_interface.json`); it pins
//// that recognition without pulling the dependency in.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import oaisp/endpoint
import oaisp/info
import oaisp/internal/fs
import oaisp/internal/merge
import oaisp/internal/package_interface as pkg
import oaisp/schema

fn package() -> pkg.Package {
  let assert Ok(content) =
    fs.read("test/fixtures/timestamp_package_interface.json")
  let assert Ok(decoded) = pkg.decode_string(content)
  decoded
}

fn entry_ref() -> schema.Schema {
  schema.type_ref("journal/types", "Entry")
}

fn document(endpoints: List(endpoint.Endpoint)) -> String {
  merge.to_string(endpoints, info.info("Journal", "1.0.0"), package())
}

fn at(
  endpoints: List(endpoint.Endpoint),
  path: List(String),
  inner: decode.Decoder(t),
) -> Result(t, json.DecodeError) {
  json.parse(document(endpoints), decode.at(path, inner))
}

/// The `(package, module, name)` triple resolves to the dedicated semantic type.
pub fn timestamp_is_recognised_test() {
  let assert Ok(resolved) =
    pkg.resolve_type(package(), "journal/types", "Entry")
  assert resolved
    == pkg.RecordType(
      [
        pkg.Field("id", pkg.StringType),
        pkg.Field("created_at", pkg.TimestampType),
        pkg.Field("updated_at", pkg.OptionType(pkg.TimestampType)),
      ],
      None,
    )
}

/// A `Timestamp` field renders as an RFC 3339 `string` with `format: date-time`,
/// mirroring the F# `DateTimeOffset -> {type: string, format: date-time}` case.
pub fn timestamp_field_has_date_time_format_test() {
  let eps = [
    endpoint.get("/entries") |> endpoint.with_response(200, entry_ref()),
  ]
  assert at(
      eps,
      ["components", "schemas", "Entry", "properties", "created_at", "type"],
      decode.string,
    )
    == Ok("string")
  assert at(
      eps,
      ["components", "schemas", "Entry", "properties", "created_at", "format"],
      decode.string,
    )
    == Ok("date-time")
}

/// An `Option(Timestamp)` field is nullable, not required, and keeps the format.
pub fn optional_timestamp_field_test() {
  let eps = [
    endpoint.get("/entries") |> endpoint.with_response(200, entry_ref()),
  ]
  assert at(
      eps,
      ["components", "schemas", "Entry", "properties", "updated_at", "type"],
      decode.list(decode.string),
    )
    == Ok(["string", "null"])
  assert at(
      eps,
      ["components", "schemas", "Entry", "properties", "updated_at", "format"],
      decode.string,
    )
    == Ok("date-time")
  // The Option is the only non-required field.
  assert at(
      eps,
      ["components", "schemas", "Entry", "required"],
      decode.list(decode.string),
    )
    == Ok(["id", "created_at"])
}

/// Reflected into query parameters, a `Timestamp` field is a valid `date-time`
/// string scalar (as `DateTimeOffset` is in the F# `createQueryParam`).
pub fn timestamp_query_parameter_test() {
  let eps = [
    endpoint.get("/entries") |> endpoint.with_query_record(entry_ref()),
  ]
  let param = {
    use name <- decode.field("name", decode.string)
    use required <- decode.field("required", decode.bool)
    use kind <- decode.subfield(["schema", "type"], decode.string)
    // `id` is a plain string with no format; the Timestamp fields carry one.
    use format <- decode.then(decode.optionally_at(
      ["schema", "format"],
      "",
      decode.string,
    ))
    decode.success(#(name, required, kind, format))
  }
  assert at(eps, ["paths", "/entries", "get", "parameters"], decode.list(param))
    == Ok([
      #("id", True, "string", ""),
      #("created_at", True, "string", "date-time"),
      #("updated_at", False, "string", "date-time"),
    ])
}
