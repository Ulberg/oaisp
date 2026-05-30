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
import oaisp/internal/fs

/// A decoded package interface — the public surface of one Gleam package.
pub type Package =
  pi.Package

/// Why loading or resolving against a package interface failed.
pub type Error {
  /// The package-interface file could not be read.
  CouldNotRead(path: String, reason: String)
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

/// Read and decode a package interface from a file path.
pub fn load(path: String) -> Result(Package, Error) {
  use content <- result.try(
    fs.read(path) |> result.map_error(CouldNotRead(path, _)),
  )
  decode_string(content)
}

/// Look up a public type definition by module path and name.
pub fn lookup_type(
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
  let documentation = clean_doc(definition.documentation)
  case definition.constructors {
    // Opaque types are public but expose no constructors.
    [] -> Unmodelled(documentation)
    [single] -> classify_product(single, documentation)
    many -> classify_union(many, documentation)
  }
}

fn classify_product(
  constructor: pi.TypeConstructor,
  documentation: Option(String),
) -> ResolvedType {
  // A record needs labels to name its object properties; zero fields counts as
  // an empty object. Positional fields cannot be named, so under-describe.
  case list.all(constructor.parameters, fn(p) { option.is_some(p.label) }) {
    True ->
      RecordType(
        list.map(constructor.parameters, field_from_param),
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

fn field_from_param(parameter: pi.Parameter) -> Field {
  let assert Some(label) = parameter.label
    as "record fields are checked to be labelled before this point"
  Field(name: label, type_: field_type(parameter.type_))
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
    _, _, _ -> RefType(module:, name:)
  }
}

fn nth_type(parameters: List(pi.Type), index: Int) -> FieldType {
  case list.drop(parameters, index) {
    [type_, ..] -> field_type(type_)
    [] -> AnyType
  }
}

/// Gleam stores a `///` doc as " line one\n line two" — one leading space per
/// line. Drop that space and trim the result into clean Markdown.
fn clean_doc(documentation: Option(String)) -> Option(String) {
  case documentation {
    None -> None
    Some(text) -> {
      let cleaned =
        text
        |> string.split("\n")
        |> list.map(strip_one_leading_space)
        |> string.join("\n")
        |> string.trim
      case cleaned {
        "" -> None
        _ -> Some(cleaned)
      }
    }
  }
}

fn strip_one_leading_space(line: String) -> String {
  case string.starts_with(line, " ") {
    True -> string.drop_start(line, 1)
    False -> line
  }
}
