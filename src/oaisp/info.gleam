//// The top-level metadata for the emitted OpenAPI document.

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
