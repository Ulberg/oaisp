//// Adapter over `gleam_package_interface`: the single seam between oaisp and
//// the compiler's package-interface JSON.
////
//// Everything the rest of oaisp knows about a user's types flows through here,
//// translated out of the raw package-interface wire types into the small
//// [`ResolvedType`](#ResolvedType) shape `oaisp/internal/merge` projects into
//// OpenAPI. If the package-interface format ever shifts, this module is the
//// only one that must move with it.

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface as pi
import gleam/result
import gleam/string

/// A decoded package interface — the public surface of one Gleam package.
pub type Package =
  pi.Package

/// Why resolving against a package interface failed.
pub type Error {
  /// The package-interface JSON could not be decoded.
  CouldNotParse(reason: json.DecodeError)
  /// No module with this path exists in the package interface.
  ModuleNotFound(module: String)
  /// The module exists but exposes no public type with this name. (A private
  /// type never appears in the interface at all.)
  TypeNotFound(module: String, name: String)
}

/// A public type resolved into the shape oaisp needs to build a schema.
///
/// oaisp derives schemas from type structure, so it faithfully projects the
/// shapes whose JSON encoding follows that structure — records (objects) and
/// fieldless-variant unions (string enums) — and soundly under-describes the
/// rest (opaque types, generics, and unions with payloads, whose wire shape is
/// decided by a hand-written encoder oaisp cannot see).
pub type ResolvedType {
  /// A product type: one constructor with labelled fields → a JSON object.
  RecordType(fields: List(Field), documentation: Option(String))
  /// A union whose variants are all fieldless → a string enum of variant names.
  EnumType(variants: List(String), documentation: Option(String))
  /// A type oaisp cannot faithfully describe (opaque, generic, or a union with
  /// payloads). Carries only documentation; merge emits a permissive schema.
  Unmodelled(documentation: Option(String))
}

/// A field of a [`RecordType`](#ResolvedType).
pub type Field {
  Field(name: String, type_: FieldType)
}

/// The type of a record field, as far as oaisp models it for OpenAPI.
pub type FieldType {
  StringType
  IntType
  FloatType
  BoolType
  NilType
  ListType(element: FieldType)
  OptionType(inner: FieldType)
  DictType(value: FieldType)
  TupleType(elements: List(FieldType))
  /// A `String` field carrying an OpenAPI `format`, requested by a
  /// `@format <field>: <format>` directive in the enclosing type's doc comment.
  /// The runtime value is still a `String`, so codecs are unaffected; the format
  /// is pure metadata, the nearest Gleam gets to an F# `[DataType]` attribute.
  /// See [`parse_format_lines`](#parse_format_lines).
  FormattedStringType(format: String)
  /// The standard `gleam/time/timestamp.Timestamp`, rendered as an RFC 3339
  /// `string` with `format: date-time`. Recognised by name in the package
  /// interface, so oaisp takes no dependency on `gleam_time` and never forces an
  /// oaisp-owned type onto consumers.
  TimestampType
  /// A reference to another named type, resolved transitively by merge into a
  /// `$ref`. References merge cannot resolve (dependency types absent from this
  /// package's interface) are soundly treated as [`AnyType`](#FieldType).
  RefType(module: String, name: String)
  /// Anything oaisp does not model precisely (type variables, functions,
  /// unrecognised named types) — projected as the permissive `{}` schema.
  AnyType
}

/// Decode a package interface from its JSON string.
pub fn decode_string(input: String) -> Result(Package, Error) {
  json.parse(input, pi.decoder())
  |> result.map_error(CouldNotParse)
}

/// Look up a public type definition by module path and name.
fn lookup_type(
  package: Package,
  module module: String,
  name name: String,
) -> Result(pi.TypeDefinition, Error) {
  use found_module <- result.try(
    dict.get(package.modules, module)
    |> result.replace_error(ModuleNotFound(module)),
  )
  dict.get(found_module.types, name)
  |> result.replace_error(TypeNotFound(module, name))
}

/// Resolve a public type into the [`ResolvedType`](#ResolvedType) shape oaisp
/// builds schemas from.
pub fn resolve_type(
  package: Package,
  module module: String,
  name name: String,
) -> Result(ResolvedType, Error) {
  use definition <- result.map(lookup_type(package, module:, name:))
  classify(definition)
}

fn classify(definition: pi.TypeDefinition) -> ResolvedType {
  // The doc comment is two things at once: prose (the schema description) and
  // any `@format` directives. Parse it once, then hand each part to the side
  // that needs it.
  let raw = raw_doc_lines(definition.documentation)
  let documentation = clean_doc(raw)
  let formats = format_map(parse_format_lines(raw))
  case definition.constructors {
    // Opaque types are public but expose no constructors.
    [] -> Unmodelled(documentation)
    [single] -> classify_product(single, documentation, formats)
    many -> classify_union(many, documentation)
  }
}

fn classify_product(
  constructor: pi.TypeConstructor,
  documentation: Option(String),
  formats: dict.Dict(String, String),
) -> ResolvedType {
  // A record needs labels to name its object properties; zero fields counts as
  // an empty object. Positional fields cannot be named, so under-describe.
  case list.all(constructor.parameters, fn(p) { option.is_some(p.label) }) {
    True ->
      RecordType(
        list.map(constructor.parameters, fn(parameter) {
          field_from_param(parameter, formats)
        }),
        documentation,
      )
    False -> Unmodelled(documentation)
  }
}

fn classify_union(
  constructors: List(pi.TypeConstructor),
  documentation: Option(String),
) -> ResolvedType {
  case list.all(constructors, fn(c) { c.parameters == [] }) {
    True -> EnumType(list.map(constructors, fn(c) { c.name }), documentation)
    False -> Unmodelled(documentation)
  }
}

fn field_from_param(
  parameter: pi.Parameter,
  formats: dict.Dict(String, String),
) -> Field {
  let assert Some(label) = parameter.label
    as "record fields are checked to be labelled before this point"
  let base = field_type(parameter.type_)
  let type_ = case dict.get(formats, label) {
    Ok(format) -> apply_format(base, format)
    Error(Nil) -> base
  }
  Field(name: label, type_:)
}

/// Attach a `@format` to a field's type. A format describes a `string`, so it
/// only takes on a `String` field (directly or inside an `Option`); on any
/// other field type it is ignored here.
fn apply_format(base: FieldType, format: String) -> FieldType {
  case base {
    StringType -> FormattedStringType(format)
    OptionType(StringType) -> OptionType(FormattedStringType(format))
    other -> other
  }
}

fn field_type(type_: pi.Type) -> FieldType {
  case type_ {
    pi.Named(name:, package:, module:, parameters:) ->
      named_type(name, package, module, parameters)
    pi.Tuple(elements:) -> TupleType(list.map(elements, field_type))
    pi.Variable(..) -> AnyType
    pi.Fn(..) -> AnyType
  }
}

fn named_type(
  name: String,
  package: String,
  module: String,
  parameters: List(pi.Type),
) -> FieldType {
  case package, module, name {
    "", "gleam", "String" -> StringType
    "", "gleam", "Int" -> IntType
    "", "gleam", "Float" -> FloatType
    "", "gleam", "Bool" -> BoolType
    "", "gleam", "Nil" -> NilType
    "", "gleam", "List" -> ListType(nth_type(parameters, 0))
    "gleam_stdlib", "gleam/option", "Option" ->
      OptionType(nth_type(parameters, 0))
    "gleam_stdlib", "gleam/dict", "Dict" -> DictType(nth_type(parameters, 1))
    "gleam_time", "gleam/time/timestamp", "Timestamp" -> TimestampType
    _, _, _ -> RefType(module:, name:)
  }
}

fn nth_type(parameters: List(pi.Type), index: Int) -> FieldType {
  case list.drop(parameters, index) {
    [type_, ..] -> field_type(type_)
    [] -> AnyType
  }
}

/// One outcome of parsing a `@format` directive line from a doc comment.
pub type FormatDirective {
  /// A well-formed `@format <field>: <format>` naming a field and a format.
  FormatDirective(field: String, format: String)
  /// A `@format` line that isn't `@format <field>: <format>` — e.g. a missing
  /// colon or an empty field/format. Carries the offending text; oaisp ignores
  /// it when building the schema.
  MalformedFormat(line: String)
}

/// Gleam stores a `///` doc as " line one\n line two" — one leading space per
/// line. Drop that single leading space, returning the lines.
fn raw_doc_lines(documentation: Option(String)) -> List(String) {
  case documentation {
    None -> []
    Some(text) ->
      text
      |> string.split("\n")
      |> list.map(strip_one_leading_space)
  }
}

/// The prose of a doc comment: every line that isn't a `@format` directive,
/// trimmed into clean Markdown. `None` when nothing but directives remain.
fn clean_doc(lines: List(String)) -> Option(String) {
  let cleaned =
    lines
    |> list.filter(fn(line) { !is_format_line(line) })
    |> string.join("\n")
    |> string.trim
  case cleaned {
    "" -> None
    _ -> Some(cleaned)
  }
}

/// Parse the `@format` directives out of a type's doc-comment lines (already
/// stripped of their one leading space by [`raw_doc_lines`](#raw_doc_lines)).
///
/// A directive is `@format <field>: <format>` — the field is a record label and
/// the format is the OpenAPI `format` to attach to it. Lines that don't match
/// come back as [`MalformedFormat`](#FormatDirective); this function never
/// fails. Whether a named field exists, is a string, or names a known format is
/// decided later, when the directives are applied to the resolved type.
pub fn parse_format_lines(lines: List(String)) -> List(FormatDirective) {
  lines
  |> list.filter(is_format_line)
  |> list.map(parse_format_line)
}

fn is_format_line(line: String) -> Bool {
  // `@format` must be a whole token: `@format email: …` is a directive, but
  // `@formatting` or `@format-version` is ordinary prose, not a typo'd one.
  let rest =
    line
    |> string.trim_start
    |> string.split_once(format_prefix)
  case rest {
    Ok(#("", after)) ->
      after == ""
      || string.starts_with(after, " ")
      || string.starts_with(after, "\t")
    _ -> False
  }
}

const format_prefix = "@format"

fn parse_format_line(line: String) -> FormatDirective {
  let body =
    line
    |> string.trim_start
    |> string.drop_start(string.length(format_prefix))
    |> string.trim
  case string.split_once(body, ":") {
    Ok(#(field, format)) -> {
      let field = string.trim(field)
      let format = string.trim(format)
      case field == "" || format == "" || string.contains(field, " ") {
        True -> MalformedFormat(line: string.trim(line))
        False -> FormatDirective(field:, format:)
      }
    }
    Error(Nil) -> MalformedFormat(line: string.trim(line))
  }
}

/// The well-formed directives as a `field -> format` dict (later wins on
/// duplicates). Malformed lines are dropped; `lint` surfaces them separately.
fn format_map(directives: List(FormatDirective)) -> dict.Dict(String, String) {
  directives
  |> list.filter_map(fn(directive) {
    case directive {
      FormatDirective(field:, format:) -> Ok(#(field, format))
      MalformedFormat(..) -> Error(Nil)
    }
  })
  |> dict.from_list
}

fn strip_one_leading_space(line: String) -> String {
  case string.starts_with(line, " ") {
    True -> string.drop_start(line, 1)
    False -> line
  }
}
