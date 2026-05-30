//// The top-level metadata for the emitted OpenAPI document.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}

/// OpenAPI document metadata: the API's title and version, an optional
/// description, and the server URLs it is served from.
///
/// Build the common case with [`info`](#info) and spread to override the rest:
///
/// ```gleam
/// Info(..info("Todo API", "1.0.0"), description: Some("Manage todos"))
/// ```
pub type Info {
  Info(
    title: String,
    version: String,
    description: Option(String),
    servers: List(String),
  )
}

/// An [`Info`](#Info) with no description and no servers. Spread it to set
/// those fields.
pub fn info(title title: String, version version: String) -> Info {
  Info(title:, version:, description: None, servers: [])
}

/// Encode [`Info`](#Info) into the internal wire JSON.
@internal
pub fn to_json(info: Info) -> json.Json {
  json.object([
    #("title", json.string(info.title)),
    #("version", json.string(info.version)),
    #("description", json.nullable(info.description, json.string)),
    #("servers", json.array(info.servers, json.string)),
  ])
}

/// Decode [`Info`](#Info) from the internal wire JSON.
@internal
pub fn decoder() -> decode.Decoder(Info) {
  use title <- decode.field("title", decode.string)
  use version <- decode.field("version", decode.string)
  use description <- decode.field("description", decode.optional(decode.string))
  use servers <- decode.field("servers", decode.list(decode.string))
  decode.success(Info(title:, version:, description:, servers:))
}
