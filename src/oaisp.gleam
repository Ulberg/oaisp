//// oaisp — a code-first OpenAPI 3.1 generator for Wisp applications on the BEAM.
////
//// You write request/response types and endpoint declarations as ordinary
//// Gleam code; one CLI command (`gleam run -m oaisp/cli generate`) emits a
//// truthful OpenAPI 3.1 document at build time. The Gleam code is the single
//// source of truth; the spec is a sound projection of it.
////
//// This module is the public surface. It re-exports the core types so callers
//// can lean on a single `oaisp.*` namespace; the builder combinators live on
//// [`oaisp/endpoint`](./oaisp/endpoint.html), the scalar param helpers on
//// [`oaisp/param`](./oaisp/param.html), and the CLI on
//// [`oaisp/cli`](./oaisp/cli.html).

import oaisp/codec
import oaisp/endpoint
import oaisp/info

/// The version of the oaisp library.
pub const version: String = "0.1.0"

/// A codec bundling a decoder, encoder, and schema for a type. See
/// [`oaisp/codec`](./oaisp/codec.html).
pub type Codec(t) =
  codec.Codec(t)

/// How a value's schema is described in the document. See
/// [`oaisp/codec`](./oaisp/codec.html).
pub type Schema =
  codec.Schema

/// The primitive kinds an inline scalar schema can take.
pub type ScalarKind =
  codec.ScalarKind

/// A single endpoint declaration. See [`oaisp/endpoint`](./oaisp/endpoint.html).
pub type Endpoint =
  endpoint.Endpoint

/// An HTTP method oaisp can document.
pub type Method =
  endpoint.Method

/// The top-level metadata for the emitted document. See
/// [`oaisp/info`](./oaisp/info.html).
pub type Info =
  info.Info
