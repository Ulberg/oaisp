//// The core: project declared endpoints + document info + the package
//// interface into an OpenAPI 3.1 document.
////
//// Body and response `TypeRef`s become `$ref`s into `components/schemas`; the
//// referenced types are resolved transitively (a record pulls in the records
//// and enums it mentions) and emitted as JSON Schema. A reference oaisp cannot
//// resolve — a dependency type absent from this package's interface — is
//// soundly emitted as the permissive `{}` schema rather than a dangling ref.
////
//// Output is deterministic: components are sorted by name and every object's
//// keys are emitted in a fixed order, so the document diffs cleanly.

import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import oaisp/endpoint.{type Endpoint}
import oaisp/info.{type Info}
import oaisp/internal/package_interface as pkg
import oaisp/schema.{
  type ScalarKind, type Schema, BoolKind, FloatKind, IntKind, Scalar, StringKind,
  TypeRef,
}

const openapi_version = "3.1.0"

/// Build the OpenAPI 3.1 document for `endpoints` and `info`, resolving type
/// references against `package`.
pub fn to_openapi(
  endpoints: List(Endpoint),
  info: Info,
  package: pkg.Package,
) -> Json {
  let components = resolve_closure(package, seed_refs(endpoints))
  let resolvable = set.from_list(dict.keys(components))

  let head = [
    #("openapi", json.string(openapi_version)),
    #("info", info_object(info)),
  ]
  let servers = case info.servers {
    [] -> []
    urls -> [#("servers", json.array(urls, server_object))]
  }
  let paths = [#("paths", paths_object(endpoints, resolvable))]
  let components_part = case dict.is_empty(components) {
    True -> []
    False -> [
      #(
        "components",
        json.object([#("schemas", components_object(components, resolvable))]),
      ),
    ]
  }

  json.object(list.flatten([head, servers, paths, components_part]))
}

/// The OpenAPI document as a JSON string.
pub fn to_string(
  endpoints: List(Endpoint),
  info: Info,
  package: pkg.Package,
) -> String {
  json.to_string(to_openapi(endpoints, info, package))
}

fn server_object(url: String) -> Json {
  json.object([#("url", json.string(url))])
}

fn info_object(info: Info) -> Json {
  json.object(
    list.flatten([
      [
        #("title", json.string(info.title)),
        #("version", json.string(info.version)),
      ],
      optional("description", info.description),
    ]),
  )
}

// --- paths -------------------------------------------------------------------

fn paths_object(endpoints: List(Endpoint), resolvable: Set(String)) -> Json {
  ordered_paths(endpoints)
  |> list.map(fn(path) {
    let for_path = list.filter(endpoints, fn(e) { endpoint.path(e) == path })
    #(path, path_item(for_path, resolvable))
  })
  |> json.object
}

fn ordered_paths(endpoints: List(Endpoint)) -> List(String) {
  endpoints
  |> list.fold([], fn(seen, e) {
    let path = endpoint.path(e)
    case list.contains(seen, path) {
      True -> seen
      False -> [path, ..seen]
    }
  })
  |> list.reverse
}

fn path_item(endpoints: List(Endpoint), resolvable: Set(String)) -> Json {
  endpoints
  |> list.map(fn(e) {
    #(endpoint.method_to_string(endpoint.method(e)), operation(e, resolvable))
  })
  |> json.object
}

fn operation(e: Endpoint, resolvable: Set(String)) -> Json {
  let tags = case endpoint.tags(e) {
    [] -> []
    tags -> [#("tags", json.array(tags, json.string))]
  }
  let parameters =
    list.flatten([
      list.map(endpoint.path_params(e), parameter(_, "path", resolvable)),
      list.map(endpoint.query_params(e), parameter(_, "query", resolvable)),
    ])
  let parameters_part = case parameters {
    [] -> []
    ps -> [#("parameters", json.preprocessed_array(ps))]
  }
  let request_body = case endpoint.body(e) {
    None -> []
    Some(schema) -> [#("requestBody", request_body_object(schema, resolvable))]
  }

  json.object(
    list.flatten([
      tags,
      optional("summary", endpoint.summary(e)),
      optional("description", endpoint.description(e)),
      optional("operationId", endpoint.operation_id(e)),
      parameters_part,
      request_body,
      [#("responses", responses_object(endpoint.responses(e), resolvable))],
    ]),
  )
}

fn parameter(
  param: endpoint.Param,
  location: String,
  resolvable: Set(String),
) -> Json {
  let #(schema, description) = param_schema(param.schema, resolvable)
  json.object(
    list.flatten([
      [#("name", json.string(param.name)), #("in", json.string(location))],
      optional("description", description),
      [
        #("required", json.bool(param.required)),
        #("schema", oas_to_json(schema)),
      ],
    ]),
  )
}

fn request_body_object(schema: Schema, resolvable: Set(String)) -> Json {
  json.object([
    #("required", json.bool(True)),
    #("content", content(schema_oas(schema, resolvable))),
  ])
}

fn responses_object(
  responses: List(endpoint.Response),
  resolvable: Set(String),
) -> Json {
  responses
  |> list.map(fn(response) {
    #(int.to_string(response.status), response_object(response, resolvable))
  })
  |> json.object
}

fn response_object(
  response: endpoint.Response,
  resolvable: Set(String),
) -> Json {
  // OpenAPI requires a description on every response; fall back to the status
  // reason phrase when the declaration didn't give one.
  let description =
    option.unwrap(response.description, status_reason(response.status))
  let base = [#("description", json.string(description))]
  case response.body {
    None -> json.object(base)
    Some(schema) ->
      json.object(
        list.append(base, [
          #("content", content(schema_oas(schema, resolvable))),
        ]),
      )
  }
}

fn content(schema: Oas) -> Json {
  json.object([
    #("application/json", json.object([#("schema", oas_to_json(schema))])),
  ])
}

// --- components --------------------------------------------------------------

fn components_object(
  components: Dict(String, pkg.ResolvedType),
  resolvable: Set(String),
) -> Json {
  components
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    #(entry.0, oas_to_json(resolved_oas(entry.1, resolvable)))
  })
  |> json.object
}

/// Resolve every type reachable from `seeds`, keyed by component name.
fn resolve_closure(
  package: pkg.Package,
  seeds: List(#(String, String)),
) -> Dict(String, pkg.ResolvedType) {
  do_closure(package, seeds, set.new(), dict.new())
}

fn do_closure(
  package: pkg.Package,
  worklist: List(#(String, String)),
  visited: Set(String),
  acc: Dict(String, pkg.ResolvedType),
) -> Dict(String, pkg.ResolvedType) {
  case worklist {
    [] -> acc
    [#(module, name), ..rest] -> {
      let key = module <> "#" <> name
      case set.contains(visited, key) {
        True -> do_closure(package, rest, visited, acc)
        False -> {
          let visited = set.insert(visited, key)
          case pkg.resolve_type(package, module, name) {
            // Unresolvable references (e.g. dependency types) are not
            // components; they become `{}` where referenced.
            Error(_) -> do_closure(package, rest, visited, acc)
            Ok(resolved) ->
              do_closure(
                package,
                list.append(child_refs(resolved), rest),
                visited,
                dict.insert(acc, name, resolved),
              )
          }
        }
      }
    }
  }
}

fn child_refs(resolved: pkg.ResolvedType) -> List(#(String, String)) {
  case resolved {
    pkg.RecordType(fields, _) ->
      list.flat_map(fields, fn(field) { field_type_refs(field.type_) })
    _ -> []
  }
}

fn field_type_refs(field_type: pkg.FieldType) -> List(#(String, String)) {
  case field_type {
    pkg.RefType(module:, name:) -> [#(module, name)]
    pkg.ListType(element) -> field_type_refs(element)
    pkg.OptionType(inner) -> field_type_refs(inner)
    pkg.DictType(value) -> field_type_refs(value)
    pkg.TupleType(elements) -> list.flat_map(elements, field_type_refs)
    _ -> []
  }
}

// --- seed collection ---------------------------------------------------------

fn seed_refs(endpoints: List(Endpoint)) -> List(#(String, String)) {
  list.flat_map(endpoints, endpoint_refs)
}

fn endpoint_refs(e: Endpoint) -> List(#(String, String)) {
  [body_schemas(e), response_schemas(e), param_schemas(e)]
  |> list.flatten
  |> list.filter_map(type_ref)
}

fn type_ref(schema: Schema) -> Result(#(String, String), Nil) {
  case schema {
    TypeRef(module:, name:) -> Ok(#(module, name))
    Scalar(..) -> Error(Nil)
  }
}

fn body_schemas(e: Endpoint) -> List(Schema) {
  case endpoint.body(e) {
    Some(schema) -> [schema]
    None -> []
  }
}

fn response_schemas(e: Endpoint) -> List(Schema) {
  list.filter_map(endpoint.responses(e), fn(r) { option.to_result(r.body, Nil) })
}

fn param_schemas(e: Endpoint) -> List(Schema) {
  list.append(
    list.map(endpoint.path_params(e), fn(p) { p.schema }),
    list.map(endpoint.query_params(e), fn(p) { p.schema }),
  )
}

// --- schema (Oas) intermediate -----------------------------------------------

/// A JSON Schema node, built structurally so nullability and `anyOf` can be
/// expressed cleanly before serialisation.
type Oas {
  OString
  OInteger
  ONumber
  OBoolean
  ONull
  OArray(items: Oas)
  OTuple(elements: List(Oas))
  OMap(value: Oas)
  OObject(
    properties: List(#(String, Oas)),
    required: List(String),
    description: Option(String),
  )
  OEnum(values: List(String), description: Option(String))
  ORef(name: String)
  ONullable(inner: Oas)
  OAny(description: Option(String))
}

fn resolved_oas(resolved: pkg.ResolvedType, resolvable: Set(String)) -> Oas {
  case resolved {
    pkg.RecordType(fields, documentation) -> {
      let properties =
        list.map(fields, fn(field) {
          #(field.name, field_oas(field.type_, resolvable))
        })
      let required =
        list.filter_map(fields, fn(field) {
          case field.type_ {
            pkg.OptionType(_) -> Error(Nil)
            _ -> Ok(field.name)
          }
        })
      OObject(properties:, required:, description: documentation)
    }
    pkg.EnumType(variants, documentation) ->
      OEnum(values: variants, description: documentation)
    pkg.Unmodelled(documentation) -> OAny(documentation)
  }
}

fn field_oas(field_type: pkg.FieldType, resolvable: Set(String)) -> Oas {
  case field_type {
    pkg.StringType -> OString
    pkg.IntType -> OInteger
    pkg.FloatType -> ONumber
    pkg.BoolType -> OBoolean
    pkg.NilType -> ONull
    pkg.ListType(element) -> OArray(field_oas(element, resolvable))
    pkg.OptionType(inner) -> ONullable(field_oas(inner, resolvable))
    pkg.DictType(value) -> OMap(field_oas(value, resolvable))
    pkg.TupleType(elements) ->
      OTuple(list.map(elements, field_oas(_, resolvable)))
    pkg.RefType(_module, name) -> ref_or_any(name, resolvable)
    pkg.AnyType -> OAny(None)
  }
}

fn schema_oas(schema: Schema, resolvable: Set(String)) -> Oas {
  case schema {
    TypeRef(_module, name) -> ref_or_any(name, resolvable)
    Scalar(kind, _description) -> scalar_oas(kind)
  }
}

/// A parameter's schema plus the description it should carry at the parameter
/// level (OpenAPI parameter objects describe themselves, not via the schema).
fn param_schema(
  schema: Schema,
  resolvable: Set(String),
) -> #(Oas, Option(String)) {
  case schema {
    Scalar(kind, description) -> #(scalar_oas(kind), description)
    TypeRef(_module, name) -> #(ref_or_any(name, resolvable), None)
  }
}

fn scalar_oas(kind: ScalarKind) -> Oas {
  case kind {
    StringKind -> OString
    IntKind -> OInteger
    BoolKind -> OBoolean
    FloatKind -> ONumber
  }
}

fn ref_or_any(name: String, resolvable: Set(String)) -> Oas {
  case set.contains(resolvable, name) {
    True -> ORef(name)
    False -> OAny(None)
  }
}

fn oas_to_json(oas: Oas) -> Json {
  case oas {
    OString -> typed("string")
    // Gleam `Int` is arbitrary precision (a BEAM bignum), so it is neither
    // `int32` nor `int64`; attaching such a `format` would claim a bound the
    // value does not honour. Plain `integer` is the sound description.
    OInteger -> typed("integer")
    // Gleam `Float` is an IEEE-754 double on the BEAM, so `double` is exact.
    ONumber -> number_schema()
    OBoolean -> typed("boolean")
    ONull -> typed("null")
    OArray(items:) ->
      json.object([
        #("type", json.string("array")),
        #("items", oas_to_json(items)),
      ])
    OTuple(elements:) ->
      json.object([
        #("type", json.string("array")),
        #("prefixItems", json.array(elements, oas_to_json)),
      ])
    OMap(value:) ->
      json.object([
        #("type", json.string("object")),
        #("additionalProperties", oas_to_json(value)),
      ])
    OObject(properties:, required:, description:) ->
      object_to_json(properties, required, description)
    OEnum(values:, description:) -> enum_to_json(values, description)
    ORef(name:) ->
      json.object([#("$ref", json.string("#/components/schemas/" <> name))])
    ONullable(inner:) -> nullable_to_json(inner)
    OAny(description:) ->
      case description {
        None -> json.object([])
        Some(text) -> json.object([#("description", json.string(text))])
      }
  }
}

fn typed(name: String) -> Json {
  json.object([#("type", json.string(name))])
}

fn number_schema() -> Json {
  json.object([
    #("type", json.string("number")),
    #("format", json.string("double")),
  ])
}

fn object_to_json(
  properties: List(#(String, Oas)),
  required: List(String),
  description: Option(String),
) -> Json {
  let required_part = case required {
    [] -> []
    names -> [#("required", json.array(names, json.string))]
  }
  json.object(
    list.flatten([
      optional("description", description),
      [
        #("type", json.string("object")),
        #(
          "properties",
          json.object(list.map(properties, fn(p) { #(p.0, oas_to_json(p.1)) })),
        ),
      ],
      required_part,
    ]),
  )
}

fn enum_to_json(values: List(String), description: Option(String)) -> Json {
  json.object(
    list.flatten([
      optional("description", description),
      [
        #("type", json.string("string")),
        #("enum", json.array(values, json.string)),
      ],
    ]),
  )
}

fn nullable_to_json(inner: Oas) -> Json {
  case inner {
    OString -> type_array(["string", "null"])
    OInteger -> type_array(["integer", "null"])
    ONumber ->
      json.object([
        #("type", json.array(["number", "null"], json.string)),
        #("format", json.string("double")),
      ])
    OBoolean -> type_array(["boolean", "null"])
    ONull -> typed("null")
    other ->
      json.object([
        #("anyOf", json.preprocessed_array([oas_to_json(other), typed("null")])),
      ])
  }
}

fn type_array(types: List(String)) -> Json {
  json.object([#("type", json.array(types, json.string))])
}

fn optional(key: String, value: Option(String)) -> List(#(String, Json)) {
  case value {
    None -> []
    Some(text) -> [#(key, json.string(text))]
  }
}

fn status_reason(status: Int) -> String {
  case status {
    200 -> "OK"
    201 -> "Created"
    202 -> "Accepted"
    204 -> "No Content"
    301 -> "Moved Permanently"
    400 -> "Bad Request"
    401 -> "Unauthorized"
    403 -> "Forbidden"
    404 -> "Not Found"
    409 -> "Conflict"
    422 -> "Unprocessable Entity"
    429 -> "Too Many Requests"
    500 -> "Internal Server Error"
    _ -> "Response"
  }
}
