import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}
import oaisp/codec
import oaisp/param

pub fn type_ref_test() {
  assert codec.type_ref("myapp/types", "Todo")
    == codec.TypeRef("myapp/types", "Todo")
}

pub fn schema_accessor_test() {
  let c =
    codec.codec(
      decode: decode.string,
      encode: json.string,
      schema: codec.type_ref("myapp/types", "Todo"),
    )
  assert codec.schema(c) == codec.TypeRef("myapp/types", "Todo")
}

pub fn encoder_accessor_round_trips_test() {
  let c =
    codec.codec(
      decode: decode.string,
      encode: json.string,
      schema: codec.type_ref("a", "B"),
    )
  let encode = codec.encoder(c)
  assert json.to_string(encode("hi")) == "\"hi\""
}

pub fn param_scalars_test() {
  assert param.string() == codec.Scalar(codec.StringKind, None)
  assert param.int() == codec.Scalar(codec.IntKind, None)
  assert param.bool() == codec.Scalar(codec.BoolKind, None)
  assert param.float() == codec.Scalar(codec.FloatKind, None)
}
