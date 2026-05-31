import gleam/json
import gleam/list
import gleam/option.{None}
import oaisp/param
import oaisp/schema

pub fn type_ref_test() {
  assert schema.type_ref("myapp/types", "Todo")
    == schema.TypeRef("myapp/types", "Todo")
}

pub fn param_string_test() {
  assert param.string() == schema.Scalar(schema.StringKind, None)
}

pub fn wire_round_trips_test() {
  // A type reference and each scalar survive the internal wire encode/decode.
  [
    schema.type_ref("myapp/types", "Todo"),
    param.string(),
    schema.Scalar(schema.IntKind, None),
    schema.Scalar(schema.BoolKind, None),
    schema.Scalar(schema.FloatKind, None),
  ]
  |> list.each(fn(reference) {
    let encoded = json.to_string(schema.schema_to_json(reference))
    let assert Ok(decoded) = json.parse(encoded, schema.schema_decoder())
    assert decoded == reference
  })
}
