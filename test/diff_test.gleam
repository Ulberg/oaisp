import gleam/list
import gleam/string
import oaisp/internal/diff

fn spec(document: String) -> diff.Spec {
  let assert Ok(decoded) = diff.decode_spec(document)
  decoded
}

fn breaking(changes: List(diff.Change), fragment: String) -> Bool {
  list.any(changes, fn(change) {
    change.breaking && string.contains(change.description, fragment)
  })
}

fn mentions(changes: List(diff.Change), fragment: String) -> Bool {
  list.any(changes, fn(change) { string.contains(change.description, fragment) })
}

pub fn identical_documents_have_no_changes_test() {
  let doc = "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{}}}}}}"
  assert diff.diff(spec(doc), spec(doc)) == []
}

pub fn removed_operation_is_breaking_test() {
  let old =
    "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{}}}},\"/b\":{\"post\":{\"responses\":{\"201\":{}}}}}}"
  let new = "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{}}}}}}"
  let changes = diff.diff(spec(old), spec(new))
  assert breaking(changes, "removed operation POST /b")
  assert diff.has_breaking(changes)
}

pub fn added_operation_is_not_breaking_test() {
  let old = "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{}}}}}}"
  let new =
    "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{}}}},\"/b\":{\"post\":{\"responses\":{}}}}}"
  let changes = diff.diff(spec(old), spec(new))
  assert mentions(changes, "added operation POST /b")
  assert diff.has_breaking(changes) == False
}

pub fn removed_response_is_breaking_test() {
  let old =
    "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{},\"404\":{}}}}}}"
  let new = "{\"paths\":{\"/a\":{\"get\":{\"responses\":{\"200\":{}}}}}}"
  assert breaking(
    diff.diff(spec(old), spec(new)),
    "removed response 404 from GET /a",
  )
}

pub fn newly_required_param_is_breaking_test() {
  let old =
    "{\"paths\":{\"/a\":{\"get\":{\"parameters\":[{\"name\":\"q\",\"in\":\"query\",\"required\":false}],\"responses\":{\"200\":{}}}}}}"
  let new =
    "{\"paths\":{\"/a\":{\"get\":{\"parameters\":[{\"name\":\"q\",\"in\":\"query\",\"required\":true}],\"responses\":{\"200\":{}}}}}}"
  assert breaking(
    diff.diff(spec(old), spec(new)),
    "new required parameter q on GET /a",
  )
}

pub fn removed_schema_is_breaking_test() {
  let old = "{\"components\":{\"schemas\":{\"T\":{\"type\":\"object\"}}}}"
  let new = "{\"components\":{\"schemas\":{}}}"
  assert breaking(diff.diff(spec(old), spec(new)), "removed schema T")
}

pub fn removed_property_is_breaking_test() {
  let old =
    "{\"components\":{\"schemas\":{\"T\":{\"properties\":{\"x\":{},\"y\":{}}}}}}"
  let new = "{\"components\":{\"schemas\":{\"T\":{\"properties\":{\"x\":{}}}}}}"
  assert breaking(
    diff.diff(spec(old), spec(new)),
    "removed property y from schema T",
  )
}

pub fn newly_required_property_is_breaking_test() {
  let old =
    "{\"components\":{\"schemas\":{\"T\":{\"properties\":{\"x\":{},\"y\":{}},\"required\":[\"x\"]}}}}"
  let new =
    "{\"components\":{\"schemas\":{\"T\":{\"properties\":{\"x\":{},\"y\":{}},\"required\":[\"x\",\"y\"]}}}}"
  assert breaking(
    diff.diff(spec(old), spec(new)),
    "property y became required in schema T",
  )
}
