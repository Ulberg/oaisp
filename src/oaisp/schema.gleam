//// A schema reference for an endpoint's body, response, or parameter.
////
//// oaisp is non-intrusive: it never sees your decoders or encoders. You point
//// an endpoint at a type by name with [`type_ref`](#type_ref) — resolved from
//// the package interface at build time — or at an inline scalar via
//// `oaisp/param`. How your handlers read and write that type is entirely yours.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

/// How an endpoint element's schema is described in the document.
pub type Schema {
  /// A reference to a public Gleam type, resolved at merge time from the
  /// package interface. `module` is the full module path (e.g. `"myapp/types"`)
  /// and `name` the type's name (`"Todo"`).
  TypeRef(module: String, name: String)
  /// An inline scalar, used for path and query parameters where a full type
  /// reference would be overkill.
  Scalar(kind: ScalarKind, description: Option(String))
}

/// The primitive kinds an inline [`Scalar`](#Schema) schema can take.
pub type ScalarKind {
  StringKind
  IntKind
  BoolKind
  FloatKind
}

/// A [`Schema`](#Schema) referring to a public Gleam type, resolved at merge
/// time from the package interface.
pub fn type_ref(module module: String, name name: String) -> Schema {
  TypeRef(module:, name:)
}

/// Encode a [`Schema`](#Schema) into the internal wire JSON that
/// `--emit-endpoints` uses to carry declarations from the app to the CLI.
@internal
pub fn schema_to_json(schema: Schema) -> json.Json {
  case schema {
    TypeRef(module:, name:) ->
      json.object([
        #("kind", json.string("type_ref")),
        #("module", json.string(module)),
        #("name", json.string(name)),
      ])
    Scalar(kind:, description:) ->
      json.object([
        #("kind", json.string("scalar")),
        #("scalar", json.string(scalar_kind_to_string(kind))),
        #("description", json.nullable(description, json.string)),
      ])
  }
}

/// Decode a [`Schema`](#Schema) from the internal wire JSON.
@internal
pub fn schema_decoder() -> decode.Decoder(Schema) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "type_ref" -> {
      use module <- decode.field("module", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(TypeRef(module:, name:))
    }
    "scalar" -> {
      use scalar <- decode.field("scalar", decode.string)
      use description <- decode.field(
        "description",
        decode.optional(decode.string),
      )
      case scalar_kind_from_string(scalar) {
        Ok(kind) -> decode.success(Scalar(kind:, description:))
        Error(Nil) -> decode.failure(TypeRef("", ""), "ScalarKind")
      }
    }
    _ -> decode.failure(TypeRef("", ""), "Schema")
  }
}

fn scalar_kind_to_string(kind: ScalarKind) -> String {
  case kind {
    StringKind -> "string"
    IntKind -> "int"
    BoolKind -> "bool"
    FloatKind -> "float"
  }
}

fn scalar_kind_from_string(name: String) -> Result(ScalarKind, Nil) {
  case name {
    "string" -> Ok(StringKind)
    "int" -> Ok(IntKind)
    "bool" -> Ok(BoolKind)
    "float" -> Ok(FloatKind)
    _ -> Error(Nil)
  }
}
