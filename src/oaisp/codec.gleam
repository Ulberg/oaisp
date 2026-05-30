//// A codec bundles a decoder, an encoder, and a schema reference for a type.
////
//// The decoder and encoder are the runtime contract your handlers read and
//// write; the schema is what oaisp projects into the OpenAPI document. Keeping
//// all three in one opaque value is what stops the documented surface from
//// drifting away from the behaviour the server actually honours.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

/// A codec for a type `t`: how to decode it from JSON, how to encode it to
/// JSON, and how to refer to its schema in the emitted document.
///
/// Build one with [`codec`](#codec); read its parts back with
/// [`decoder`](#decoder), [`encoder`](#encoder), and [`schema`](#schema).
pub opaque type Codec(t) {
  Codec(decode: decode.Decoder(t), encode: fn(t) -> json.Json, schema: Schema)
}

/// How a value's schema is described in the OpenAPI document.
pub type Schema {
  /// A reference to a public Gleam type, resolved at merge time from the
  /// package interface. `module` is the full module path (e.g. `"myapp/types"`)
  /// and `name` is the type's name (e.g. `"Todo"`).
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

/// Bundle a decoder, an encoder, and a schema into a [`Codec`](#Codec).
pub fn codec(
  decode decode: decode.Decoder(t),
  encode encode: fn(t) -> json.Json,
  schema schema: Schema,
) -> Codec(t) {
  Codec(decode:, encode:, schema:)
}

/// A [`Schema`](#Schema) referring to a public Gleam type, resolved at merge
/// time from the package interface.
pub fn type_ref(module module: String, name name: String) -> Schema {
  TypeRef(module:, name:)
}

/// The decoder bundled in a codec — the runtime contract for reading values.
pub fn decoder(codec: Codec(t)) -> decode.Decoder(t) {
  codec.decode
}

/// The encoder bundled in a codec — the runtime contract for writing values.
pub fn encoder(codec: Codec(t)) -> fn(t) -> json.Json {
  codec.encode
}

/// The schema bundled in a codec — what oaisp projects into the document.
pub fn schema(codec: Codec(t)) -> Schema {
  codec.schema
}
