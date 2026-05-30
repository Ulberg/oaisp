import gleam/string
import oaisp/internal/codegen
import oaisp/internal/fs
import oaisp/internal/package_interface as pkg

fn package() -> pkg.Package {
  let assert Ok(content) = fs.read("test/fixtures/package_interface.json")
  let assert Ok(decoded) = pkg.decode_string(content)
  decoded
}

fn source() -> String {
  codegen.codecs(package())
}

fn has(fragment: String) -> Bool {
  string.contains(source(), fragment)
}

pub fn imports_the_type_module_test() {
  assert has("import shop/types as shop_types")
}

pub fn generates_record_decoder_and_encoder_test() {
  assert has("pub fn user_decoder() -> decode.Decoder(shop_types.User) {")
  assert has("pub fn user_encoder(value: shop_types.User) -> json.Json {")
  // An Option field decodes/encodes through optional/nullable.
  assert has("decode.field(\"email\", decode.optional(decode.string))")
  assert has("json.nullable(value.email, json.string)")
}

pub fn generates_enum_decoder_and_encoder_test() {
  assert has("\"Active\" -> decode.success(shop_types.Active)")
  assert has("shop_types.Active -> json.string(\"Active\")")
}

pub fn references_resolve_to_other_generated_codecs_test() {
  // Todo.owner: User and Todo.status: Status reference their codecs by name,
  // and Dict / List map to the right combinators.
  assert has("decode.field(\"owner\", user_decoder())")
  assert has("json.dict(value.labels, fn(key) { key }, json.int)")
  assert has("decode.field(\"tags\", decode.list(decode.string))")
}

pub fn skips_underivable_types_test() {
  // Token (positional newtype) and Event (union with payload) cannot be
  // derived soundly, so no codec is emitted for them.
  assert has("token_decoder") == False
  assert has("event_decoder") == False
}
