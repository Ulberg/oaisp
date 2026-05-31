//// Doc-comment `@format` directives — pure metadata that attaches an OpenAPI
//// `format` to a `String` field without changing its type.
////
//// A type's doc comment may carry `@format <field>: <format>` lines; oaisp
//// applies each to the named string field (the runtime value stays a `String`)
//// and strips the directive lines from the schema description. This mirrors the
//// F# `[DataType(DataType.EmailAddress)]` attribute — the nearest a language
//// without metaprogramming can get. The fixture below is real `gleam export
//// package-interface` output for a `Contact` type whose doc comment exercises a
//// well-formed directive, a directive on an `Option(String)`, and four mistakes
//// (`@format` on an `Int`, on a missing field, with an unknown format, and a
//// line with no colon) that the liberal projection silently ignores.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{Some}
import oaisp/endpoint
import oaisp/info
import oaisp/internal/fs
import oaisp/internal/merge
import oaisp/internal/package_interface as pkg
import oaisp/schema

fn package() -> pkg.Package {
  let assert Ok(content) =
    fs.read("test/fixtures/format_package_interface.json")
  let assert Ok(decoded) = pkg.decode_string(content)
  decoded
}

fn contact_ref() -> schema.Schema {
  schema.type_ref("contacts/types", "Contact")
}

fn document(endpoints: List(endpoint.Endpoint)) -> String {
  merge.to_string(endpoints, info.info("Contacts", "1.0.0"), package())
}

fn at(
  endpoints: List(endpoint.Endpoint),
  path: List(String),
  inner: decode.Decoder(t),
) -> Result(t, json.DecodeError) {
  json.parse(document(endpoints), decode.at(path, inner))
}

fn response_endpoints() -> List(endpoint.Endpoint) {
  [endpoint.get("/contacts") |> endpoint.with_response(200, contact_ref())]
}

// --- directive parsing -------------------------------------------------------

/// The parser reads `@format <field>: <format>` lines and reports the rest as
/// malformed, leaving non-directive prose alone — including lookalikes like
/// `@formatting`, which must not be mistaken for a typo'd directive.
pub fn parse_format_lines_test() {
  let lines = [
    "A heading.",
    "@format email: email",
    "  @format  spaced :  uri  ",
    "@formatting is not a directive",
    "@format-version: 2",
    "@format brokenline",
    "@format : nofield",
    "@format field:",
  ]
  assert pkg.parse_format_lines(lines)
    == [
      pkg.FormatDirective("email", "email"),
      pkg.FormatDirective("spaced", "uri"),
      pkg.MalformedFormat("@format brokenline"),
      pkg.MalformedFormat("@format : nofield"),
      pkg.MalformedFormat("@format field:"),
    ]
}

// --- resolution --------------------------------------------------------------

/// A `@format` directive turns its `String` field into a `FormattedStringType`,
/// an `Option(String)` field into an `Option(FormattedStringType)`, and leaves
/// every other field — including the bad directives' targets — a plain type.
pub fn directive_applies_to_string_fields_test() {
  let assert Ok(resolved) =
    pkg.resolve_type(package(), "contacts/types", "Contact")
  assert resolved
    == pkg.RecordType(
      [
        pkg.Field("id", pkg.StringType),
        pkg.Field("email", pkg.FormattedStringType("email")),
        pkg.Field("homepage", pkg.OptionType(pkg.FormattedStringType("uri"))),
        pkg.Field("nickname", pkg.FormattedStringType("handle")),
        // `@format age: int64` is ignored here (age is an Int), not applied.
        pkg.Field("age", pkg.IntType),
      ],
      // The prose survives; every `@format` line is stripped from it.
      Some("A contact card."),
    )
}

// --- schema rendering --------------------------------------------------------

/// A formatted string field renders as `{type: string, format: <format>}`,
/// exactly like the built-in `Timestamp -> date-time` case.
pub fn formatted_field_has_format_test() {
  let eps = response_endpoints()
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "email", "type"],
      decode.string,
    )
    == Ok("string")
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "email", "format"],
      decode.string,
    )
    == Ok("email")
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "nickname", "format"],
      decode.string,
    )
    == Ok("handle")
}

/// An `Option(String)` field with a `@format` is nullable, not required, and
/// keeps the format — the same shape as an optional `Timestamp`.
pub fn optional_formatted_field_test() {
  let eps = response_endpoints()
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "homepage", "type"],
      decode.list(decode.string),
    )
    == Ok(["string", "null"])
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "homepage", "format"],
      decode.string,
    )
    == Ok("uri")
  // homepage is the only Option, so the only non-required field.
  assert at(
      eps,
      ["components", "schemas", "Contact", "required"],
      decode.list(decode.string),
    )
    == Ok(["id", "email", "nickname", "age"])
}

/// A field without a directive (`id`) stays a plain string with no format, and
/// a mis-targeted directive (`age`) leaves the field's own type untouched.
pub fn unformatted_fields_are_untouched_test() {
  let eps = response_endpoints()
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "id", "type"],
      decode.string,
    )
    == Ok("string")
  let assert Error(_) =
    at(
      eps,
      ["components", "schemas", "Contact", "properties", "id", "format"],
      decode.string,
    )
  assert at(
      eps,
      ["components", "schemas", "Contact", "properties", "age", "type"],
      decode.string,
    )
    == Ok("integer")
}

/// The `@format` lines never leak into the schema `description`.
pub fn directives_are_stripped_from_description_test() {
  let eps = response_endpoints()
  assert at(
      eps,
      ["components", "schemas", "Contact", "description"],
      decode.string,
    )
    == Ok("A contact card.")
}

// --- query parameters --------------------------------------------------------

/// Reflected into query parameters, a formatted string field carries its format
/// (as a `Timestamp` field carries `date-time`).
pub fn formatted_query_parameter_test() {
  let eps = [
    endpoint.get("/contacts") |> endpoint.with_query_record(contact_ref()),
  ]
  let param = {
    use name <- decode.field("name", decode.string)
    use kind <- decode.subfield(["schema", "type"], decode.string)
    use format <- decode.then(decode.optionally_at(
      ["schema", "format"],
      "",
      decode.string,
    ))
    decode.success(#(name, kind, format))
  }
  assert at(
      eps,
      ["paths", "/contacts", "get", "parameters"],
      decode.list(param),
    )
    == Ok([
      #("id", "string", ""),
      #("email", "string", "email"),
      #("homepage", "string", "uri"),
      #("nickname", "string", "handle"),
      #("age", "integer", ""),
    ])
}
