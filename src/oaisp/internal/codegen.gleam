//// `oaisp derive` — generate decoder + encoder source from the package
//// interface.
////
//// This closes the v1.0 gap where the schema is derived from the type but the
//// decoder/encoder are hand-written (and could drift): the generated codecs
//// follow the same structure the schema does, so they cannot disagree.
////
//// It emits a Gleam module. Records become a `decode.field` decoder and a
//// `json.object` encoder; fieldless-variant unions become a string
//// decoder/encoder. A type is only generated when every field is derivable —
//// scalars, `List`, `Option`, `Dict`, and references to other derivable types;
//// anything else (opaque types, generics, tuples, unions with payloads) is
//// skipped, so the output always compiles.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import oaisp/internal/package_interface.{
  type FieldType, type ResolvedType, AnyType, BoolType, DictType, EnumType,
  FloatType, FormattedStringType, IntType, ListType, NilType, OptionType,
  RecordType, RefType, StringType, TimestampType, TupleType, Unmodelled,
} as pkg

/// Generate a Gleam module of decoders and encoders for `package`'s public
/// types.
pub fn codecs(package: pkg.Package) -> String {
  let resolved =
    pkg.type_names(package)
    |> list.filter_map(fn(reference) {
      let #(module, name) = reference
      pkg.resolve_type(package, module, name)
      |> result.map(fn(resolved_type) { #(name, #(module, resolved_type)) })
    })
    |> dict.from_list

  let derivable =
    resolved
    |> dict.map_values(fn(_, entry) { entry.1 })
    |> derivable_set

  let names = derivable |> set.to_list |> list.sort(string.compare)
  let definitions =
    list.map(names, fn(name) {
      let #(module, resolved_type) = get(resolved, name)
      generate(name, module_alias(module), resolved_type)
    })
  let modules =
    names
    |> list.map(fn(name) { get(resolved, name).0 })
    |> list.unique
    |> list.sort(string.compare)

  assemble(modules, definitions)
}

// --- derivability ------------------------------------------------------------

fn derivable_set(types: Dict(String, ResolvedType)) -> Set(String) {
  let initial =
    types
    |> dict.to_list
    |> list.filter_map(fn(entry) {
      case entry.1 {
        RecordType(..) | EnumType(..) -> Ok(entry.0)
        Unmodelled(..) -> Error(Nil)
      }
    })
    |> set.from_list
  fixpoint(types, initial)
}

fn fixpoint(
  types: Dict(String, ResolvedType),
  current: Set(String),
) -> Set(String) {
  let next =
    current
    |> set.to_list
    |> list.filter(fn(name) { derivable(name, types, current) })
    |> set.from_list
  case set.size(next) == set.size(current) {
    True -> next
    False -> fixpoint(types, next)
  }
}

fn derivable(
  name: String,
  types: Dict(String, ResolvedType),
  current: Set(String),
) -> Bool {
  case dict.get(types, name) {
    Ok(EnumType(..)) -> True
    Ok(RecordType(fields, _)) ->
      list.all(fields, fn(field) { field_derivable(field.type_, current) })
    _ -> False
  }
}

fn field_derivable(field_type: FieldType, current: Set(String)) -> Bool {
  case field_type {
    // A formatted field is a `String` at runtime, so its codec is the plain
    // string codec — the format is documentation only.
    StringType
    | FormattedStringType(..)
    | IntType
    | FloatType
    | BoolType
    | NilType -> True
    ListType(element) -> field_derivable(element, current)
    OptionType(inner) -> field_derivable(inner, current)
    DictType(value) -> field_derivable(value, current)
    RefType(_module, name) -> set.contains(current, name)
    // Tuples have no general json codec, AnyType is unknown by definition, and a
    // Timestamp's codec lives in `gleam_time` — oaisp won't synthesise one.
    TupleType(..) | AnyType | TimestampType -> False
  }
}

// --- generation --------------------------------------------------------------

fn generate(
  name: String,
  alias: String,
  resolved_type: ResolvedType,
) -> String {
  case resolved_type {
    RecordType(fields, _) -> generate_record(name, alias, fields)
    EnumType(variants, _) -> generate_enum(name, alias, variants)
    Unmodelled(_) -> ""
  }
}

fn generate_record(
  name: String,
  alias: String,
  fields: List(pkg.Field),
) -> String {
  let type_ref = alias <> "." <> name
  let base = snake_case(name)

  let decoder_lines =
    fields
    |> list.map(fn(field) {
      "  use "
      <> field.name
      <> " <- decode.field(\""
      <> field.name
      <> "\", "
      <> decoder_expr(field.type_)
      <> ")"
    })
    |> string.join("\n")
  let constructor =
    fields
    |> list.map(fn(field) { field.name <> ":" })
    |> string.join(", ")
  let decoder =
    "pub fn "
    <> base
    <> "_decoder() -> decode.Decoder("
    <> type_ref
    <> ") {\n"
    <> decoder_lines
    <> "\n  decode.success("
    <> type_ref
    <> "("
    <> constructor
    <> "))\n}"

  let encoder_lines =
    fields
    |> list.map(fn(field) {
      "    #(\""
      <> field.name
      <> "\", "
      <> encode_field(field.type_, "value." <> field.name)
      <> "),"
    })
    |> string.join("\n")
  let encoder =
    "pub fn "
    <> base
    <> "_encoder(value: "
    <> type_ref
    <> ") -> json.Json {\n  json.object([\n"
    <> encoder_lines
    <> "\n  ])\n}"

  decoder <> "\n\n" <> encoder
}

fn generate_enum(
  name: String,
  alias: String,
  variants: List(String),
) -> String {
  let type_ref = alias <> "." <> name
  let base = snake_case(name)
  let first = case variants {
    [variant, ..] -> variant
    [] -> name
  }

  let decode_cases =
    variants
    |> list.map(fn(variant) {
      "    \""
      <> variant
      <> "\" -> decode.success("
      <> alias
      <> "."
      <> variant
      <> ")"
    })
    |> string.join("\n")
  let decoder =
    "pub fn "
    <> base
    <> "_decoder() -> decode.Decoder("
    <> type_ref
    <> ") {\n  use variant <- decode.then(decode.string)\n  case variant {\n"
    <> decode_cases
    <> "\n    _ -> decode.failure("
    <> alias
    <> "."
    <> first
    <> ", \""
    <> name
    <> "\")\n  }\n}"

  let encode_cases =
    variants
    |> list.map(fn(variant) {
      "    "
      <> alias
      <> "."
      <> variant
      <> " -> json.string(\""
      <> variant
      <> "\")"
    })
    |> string.join("\n")
  let encoder =
    "pub fn "
    <> base
    <> "_encoder(value: "
    <> type_ref
    <> ") -> json.Json {\n  case value {\n"
    <> encode_cases
    <> "\n  }\n}"

  decoder <> "\n\n" <> encoder
}

fn decoder_expr(field_type: FieldType) -> String {
  case field_type {
    StringType | FormattedStringType(..) -> "decode.string"
    IntType -> "decode.int"
    FloatType -> "decode.float"
    BoolType -> "decode.bool"
    NilType -> "decode.success(Nil)"
    ListType(element) -> "decode.list(" <> decoder_expr(element) <> ")"
    OptionType(inner) -> "decode.optional(" <> decoder_expr(inner) <> ")"
    DictType(value) ->
      "decode.dict(decode.string, " <> decoder_expr(value) <> ")"
    RefType(_module, name) -> snake_case(name) <> "_decoder()"
    TupleType(..) | AnyType | TimestampType ->
      panic as "non-derivable field type reached generation"
  }
}

fn encode_field(field_type: FieldType, value: String) -> String {
  case field_type {
    ListType(element) ->
      "json.array(" <> value <> ", " <> encoder_fn(element) <> ")"
    OptionType(inner) ->
      "json.nullable(" <> value <> ", " <> encoder_fn(inner) <> ")"
    DictType(inner) ->
      "json.dict(" <> value <> ", fn(key) { key }, " <> encoder_fn(inner) <> ")"
    NilType -> "json.null()"
    _ -> encoder_fn(field_type) <> "(" <> value <> ")"
  }
}

fn encoder_fn(field_type: FieldType) -> String {
  case field_type {
    StringType | FormattedStringType(..) -> "json.string"
    IntType -> "json.int"
    FloatType -> "json.float"
    BoolType -> "json.bool"
    NilType -> "fn(_) { json.null() }"
    ListType(element) ->
      "fn(items) { json.array(items, " <> encoder_fn(element) <> ") }"
    OptionType(inner) ->
      "fn(option) { json.nullable(option, " <> encoder_fn(inner) <> ") }"
    DictType(inner) ->
      "fn(entries) { json.dict(entries, fn(key) { key }, "
      <> encoder_fn(inner)
      <> ") }"
    RefType(_module, name) -> snake_case(name) <> "_encoder"
    TupleType(..) | AnyType | TimestampType ->
      panic as "non-derivable field type reached generation"
  }
}

fn assemble(modules: List(String), definitions: List(String)) -> String {
  let imports =
    modules
    |> list.map(fn(module) {
      "import " <> module <> " as " <> module_alias(module)
    })
    |> string.join("\n")
  "//// Generated by `oaisp derive`. Do not edit by hand; regenerate instead.\n\n"
  <> "import gleam/dynamic/decode\n"
  <> "import gleam/json\n"
  <> imports
  <> "\n\n"
  <> string.join(definitions, "\n\n")
  <> "\n"
}

fn module_alias(module: String) -> String {
  string.replace(module, "/", "_")
}

fn snake_case(name: String) -> String {
  name
  |> string.to_graphemes
  |> list.index_map(fn(grapheme, index) {
    case is_upper(grapheme), index {
      True, 0 -> string.lowercase(grapheme)
      True, _ -> "_" <> string.lowercase(grapheme)
      False, _ -> grapheme
    }
  })
  |> string.join("")
}

fn is_upper(grapheme: String) -> Bool {
  grapheme != string.lowercase(grapheme)
}

fn get(types: Dict(String, a), key: String) -> a {
  let assert Ok(value) = dict.get(types, key)
    as "key came from this dict's own key set"
  value
}
