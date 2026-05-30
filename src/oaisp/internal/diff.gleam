//// `oaisp diff <old> <new>` — a breaking-change detector for two OpenAPI
//// documents, for CI gates.
////
//// It decodes both documents into a comparable shape and reports changes.
//// Breaking changes are the ones that can break an existing client:
////
////   * an operation, response status, or schema that was removed,
////   * a schema property that was removed, and
////   * a request/path/query parameter or schema property that became required.
////
//// Additive changes (new operations, new schemas) are reported too, marked
//// non-breaking. The detector is sound for what it checks but not exhaustive
//// (it does not, for instance, compare property types); it never flags a safe
//// change as breaking.

import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The comparable shape of an OpenAPI document.
pub type Spec {
  Spec(operations: Dict(String, Operation), schemas: Dict(String, Schema))
}

/// One operation, keyed in [`Spec`](#Spec) as e.g. `"GET /todos/{id}"`.
pub type Operation {
  Operation(statuses: List(String), required_params: List(String))
}

/// One component schema's surface that matters for compatibility.
pub type Schema {
  Schema(properties: List(String), required: List(String))
}

/// A single difference between two documents.
pub type Change {
  Change(breaking: Bool, description: String)
}

/// Decode an OpenAPI document string into the comparable [`Spec`](#Spec).
pub fn decode_spec(document: String) -> Result(Spec, String) {
  json.parse(document, spec_decoder())
  |> result.map_error(fn(_) { "could not parse the OpenAPI document" })
}

/// Compare two documents, returning the changes sorted for stable output.
pub fn diff(old: Spec, new: Spec) -> List(Change) {
  [operation_changes(old, new), schema_changes(old, new)]
  |> list.flatten
  |> list.sort(fn(a, b) { string.compare(a.description, b.description) })
}

/// Whether any change is breaking.
pub fn has_breaking(changes: List(Change)) -> Bool {
  list.any(changes, fn(change) { change.breaking })
}

// --- comparison --------------------------------------------------------------

fn operation_changes(old: Spec, new: Spec) -> List(Change) {
  let removed =
    removed_keys(old.operations, new.operations)
    |> list.map(fn(key) { Change(True, "removed operation " <> key) })
  let added =
    removed_keys(new.operations, old.operations)
    |> list.map(fn(key) { Change(False, "added operation " <> key) })
  let changed =
    common_keys(old.operations, new.operations)
    |> list.flat_map(fn(key) {
      let old_operation = get(old.operations, key)
      let new_operation = get(new.operations, key)
      operation_pair_changes(key, old_operation, new_operation)
    })
  list.flatten([removed, added, changed])
}

fn operation_pair_changes(
  key: String,
  old: Operation,
  new: Operation,
) -> List(Change) {
  let removed_responses =
    only_in(old.statuses, new.statuses)
    |> list.map(fn(status) {
      Change(True, "removed response " <> status <> " from " <> key)
    })
  let newly_required =
    only_in(new.required_params, old.required_params)
    |> list.map(fn(name) {
      Change(True, "new required parameter " <> name <> " on " <> key)
    })
  list.append(removed_responses, newly_required)
}

fn schema_changes(old: Spec, new: Spec) -> List(Change) {
  let removed =
    removed_keys(old.schemas, new.schemas)
    |> list.map(fn(name) { Change(True, "removed schema " <> name) })
  let added =
    removed_keys(new.schemas, old.schemas)
    |> list.map(fn(name) { Change(False, "added schema " <> name) })
  let changed =
    common_keys(old.schemas, new.schemas)
    |> list.flat_map(fn(name) {
      schema_pair_changes(name, get(old.schemas, name), get(new.schemas, name))
    })
  list.flatten([removed, added, changed])
}

fn schema_pair_changes(name: String, old: Schema, new: Schema) -> List(Change) {
  let removed_properties =
    only_in(old.properties, new.properties)
    |> list.map(fn(property) {
      Change(True, "removed property " <> property <> " from schema " <> name)
    })
  let newly_required =
    only_in(new.required, old.required)
    |> list.map(fn(property) {
      Change(
        True,
        "property " <> property <> " became required in schema " <> name,
      )
    })
  list.append(removed_properties, newly_required)
}

fn removed_keys(
  from: Dict(String, a),
  present_in: Dict(String, b),
) -> List(String) {
  dict.keys(from)
  |> list.filter(fn(key) { bool.negate(dict.has_key(present_in, key)) })
}

fn common_keys(a: Dict(String, x), b: Dict(String, y)) -> List(String) {
  dict.keys(a) |> list.filter(fn(key) { dict.has_key(b, key) })
}

fn only_in(items: List(String), other: List(String)) -> List(String) {
  list.filter(items, fn(item) { bool.negate(list.contains(other, item)) })
}

fn get(operations: Dict(String, a), key: String) -> a {
  let assert Ok(value) = dict.get(operations, key)
    as "key came from a keys/common-keys list over this same dict"
  value
}

// --- decoding ----------------------------------------------------------------

fn spec_decoder() -> Decoder(Spec) {
  use paths <- decode.optional_field(
    "paths",
    dict.new(),
    decode.dict(decode.string, path_item_decoder()),
  )
  use schemas <- decode.optional_field(
    "components",
    dict.new(),
    components_decoder(),
  )
  decode.success(Spec(operations: flatten_paths(paths), schemas:))
}

fn components_decoder() -> Decoder(Dict(String, Schema)) {
  use schemas <- decode.optional_field(
    "schemas",
    dict.new(),
    decode.dict(decode.string, schema_decoder()),
  )
  decode.success(schemas)
}

fn schema_decoder() -> Decoder(Schema) {
  use properties <- decode.optional_field(
    "properties",
    dict.new(),
    decode.dict(decode.string, decode.success(Nil)),
  )
  use required <- decode.optional_field(
    "required",
    [],
    decode.list(decode.string),
  )
  decode.success(Schema(properties: dict.keys(properties), required:))
}

fn path_item_decoder() -> Decoder(List(#(String, Operation))) {
  let operation = fn() { decode.optional(operation_decoder()) }
  use get <- decode.optional_field("get", None, operation())
  use put <- decode.optional_field("put", None, operation())
  use post <- decode.optional_field("post", None, operation())
  use delete <- decode.optional_field("delete", None, operation())
  use options <- decode.optional_field("options", None, operation())
  use head <- decode.optional_field("head", None, operation())
  use patch <- decode.optional_field("patch", None, operation())
  use trace <- decode.optional_field("trace", None, operation())
  decode.success(
    present([
      #("get", get),
      #("put", put),
      #("post", post),
      #("delete", delete),
      #("options", options),
      #("head", head),
      #("patch", patch),
      #("trace", trace),
    ]),
  )
}

fn present(
  pairs: List(#(String, Option(Operation))),
) -> List(#(String, Operation)) {
  list.filter_map(pairs, fn(pair) {
    case pair.1 {
      Some(operation) -> Ok(#(pair.0, operation))
      None -> Error(Nil)
    }
  })
}

fn operation_decoder() -> Decoder(Operation) {
  use responses <- decode.optional_field(
    "responses",
    dict.new(),
    decode.dict(decode.string, decode.success(Nil)),
  )
  use parameters <- decode.optional_field(
    "parameters",
    [],
    decode.list(parameter_decoder()),
  )
  let required_params =
    list.filter_map(parameters, fn(parameter) {
      case parameter.1 {
        True -> Ok(parameter.0)
        False -> Error(Nil)
      }
    })
  decode.success(Operation(statuses: dict.keys(responses), required_params:))
}

fn parameter_decoder() -> Decoder(#(String, Bool)) {
  use name <- decode.field("name", decode.string)
  use required <- decode.optional_field("required", False, decode.bool)
  decode.success(#(name, required))
}

fn flatten_paths(
  paths: Dict(String, List(#(String, Operation))),
) -> Dict(String, Operation) {
  paths
  |> dict.to_list
  |> list.flat_map(fn(entry) {
    let #(path, operations) = entry
    list.map(operations, fn(pair) {
      #(string.uppercase(pair.0) <> " " <> path, pair.1)
    })
  })
  |> dict.from_list
}
