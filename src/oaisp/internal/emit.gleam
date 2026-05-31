//// Serialise endpoint declarations plus document info into the internal wire
//// JSON exchanged between the running app and the CLI.
////
//// `oaisp.add_openapi` prints [`to_string`](#to_string) when invoked with
//// `--emit-endpoints`; the CLI reads it back with [`parse`](#parse). This wire
//// JSON is an internal protocol, not the OpenAPI document — that is built by
//// `oaisp/internal/merge`.

import gleam/dynamic/decode
import gleam/json
import oaisp/endpoint.{type Endpoint}
import oaisp/info.{type Info}

/// Everything `add_openapi` knows that the CLI needs: the document metadata and
/// the declared endpoints.
pub type Document {
  Document(info: Info, endpoints: List(Endpoint))
}

/// Encode a [`Document`](#Document) to the wire JSON.
pub fn encode(document: Document) -> json.Json {
  json.object([
    #("info", info.to_json(document.info)),
    #("endpoints", json.array(document.endpoints, endpoint.to_json)),
  ])
}

/// Encode a [`Document`](#Document) to a wire-JSON string for stdout.
pub fn to_string(document: Document) -> String {
  json.to_string(encode(document))
}

/// Decoder for a [`Document`](#Document) from the wire JSON.
pub fn decoder() -> decode.Decoder(Document) {
  use document_info <- decode.field("info", info.decoder())
  use endpoints <- decode.field("endpoints", decode.list(endpoint.decoder()))
  decode.success(Document(info: document_info, endpoints:))
}

/// Parse a wire-JSON string back into a [`Document`](#Document).
pub fn parse(input: String) -> Result(Document, json.DecodeError) {
  json.parse(input, decoder())
}
