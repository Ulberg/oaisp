import gleam/option.{Some}
import oaisp/internal/package_interface as pkg
import simplifile

fn fixture() -> pkg.Package {
  let assert Ok(content) =
    simplifile.read("test/fixtures/package_interface.json")
  let assert Ok(package) = pkg.decode_string(content)
  package
}

pub fn decode_real_fixture_test() {
  // The fixture is real `gleam export package-interface` output; decoding it is
  // the smoke test that our seam tracks the compiler's format.
  let _ = fixture()
  Nil
}

pub fn resolve_record_with_optional_field_test() {
  let assert Ok(resolved) = pkg.resolve_type(fixture(), "shop/types", "User")
  assert resolved
    == pkg.RecordType(
      [
        pkg.Field("id", pkg.StringType),
        pkg.Field("name", pkg.StringType),
        pkg.Field("email", pkg.OptionType(pkg.StringType)),
      ],
      Some("A user account."),
    )
}

pub fn resolve_record_with_all_field_kinds_test() {
  let assert Ok(resolved) = pkg.resolve_type(fixture(), "shop/types", "Todo")
  assert resolved
    == pkg.RecordType(
      [
        pkg.Field("id", pkg.StringType),
        pkg.Field("title", pkg.StringType),
        pkg.Field("done", pkg.BoolType),
        pkg.Field("rank", pkg.IntType),
        pkg.Field("score", pkg.FloatType),
        pkg.Field("tags", pkg.ListType(pkg.StringType)),
        pkg.Field("note", pkg.OptionType(pkg.StringType)),
        pkg.Field("owner", pkg.RefType("shop/types", "User")),
        pkg.Field("status", pkg.RefType("shop/types", "Status")),
        pkg.Field("labels", pkg.DictType(pkg.IntType)),
      ],
      Some(
        "A todo item, exercising scalars, lists, options, a nested record, a dict,\nand an enum field.",
      ),
    )
}

pub fn resolve_enum_test() {
  let assert Ok(resolved) = pkg.resolve_type(fixture(), "shop/types", "Status")
  assert resolved
    == pkg.EnumType(
      ["Active", "Done", "Archived"],
      Some("The lifecycle state of a todo."),
    )
}

pub fn newtype_with_positional_field_is_unmodelled_test() {
  let assert Ok(resolved) = pkg.resolve_type(fixture(), "shop/types", "Token")
  assert resolved
    == pkg.Unmodelled(Some(
      "A newtype with a single positional field — oaisp under-describes this.",
    ))
}

pub fn union_with_payload_is_unmodelled_test() {
  let assert Ok(resolved) = pkg.resolve_type(fixture(), "shop/types", "Event")
  assert resolved
    == pkg.Unmodelled(Some(
      "A sum type with payloads — oaisp under-describes this.",
    ))
}

pub fn missing_type_is_an_error_test() {
  assert pkg.resolve_type(fixture(), "shop/types", "Ghost")
    == Error(pkg.TypeNotFound("shop/types", "Ghost"))
}

pub fn missing_module_is_an_error_test() {
  assert pkg.resolve_type(fixture(), "shop/ghost", "Todo")
    == Error(pkg.ModuleNotFound("shop/ghost"))
}
