//// Inline scalar schema helpers for declaring path and query parameters,
//// where a full type reference would be overkill.

import gleam/option.{None}
import oaisp/schema.{
  type Schema, BoolKind, FloatKind, IntKind, Scalar, StringKind,
}

/// A string-typed parameter schema.
pub fn string() -> Schema {
  Scalar(StringKind, None)
}

/// An integer-typed parameter schema.
pub fn int() -> Schema {
  Scalar(IntKind, None)
}

/// A boolean-typed parameter schema.
pub fn bool() -> Schema {
  Scalar(BoolKind, None)
}

/// A float-typed parameter schema.
pub fn float() -> Schema {
  Scalar(FloatKind, None)
}
