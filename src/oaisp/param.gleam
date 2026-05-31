//// Inline scalar schema helpers for declaring path and query parameters,
//// where a full type reference would be overkill.

import gleam/option.{None}
import oaisp/schema.{type Schema, Scalar, StringKind}

/// A string-typed parameter schema.
pub fn string() -> Schema {
  Scalar(StringKind, None)
}
