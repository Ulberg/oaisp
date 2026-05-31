//// `oaisp lint` — static checks over the endpoint declarations.
////
//// Lint cannot see the hand-written router, so it does not check route
//// presence; it checks what the declarations alone can prove:
////
////   * every `type_ref` resolves to a public type in the package interface,
////   * a referenced type whose schema can't be derived is flagged (a warning),
////   * every `{placeholder}` in a path has a matching `with_path_param` (and
////     vice versa),
////   * no two endpoints declare the same method + path, and
////   * every `@format` directive in a referenced type's doc comment names a
////     real string field with a known format (a warning otherwise).

import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/set
import gleam/string
import oaisp/endpoint.{type Endpoint}
import oaisp/internal/package_interface as pkg
import oaisp/schema.{Scalar, TypeRef}

/// How serious a finding is. A `Violation` should fail a CI lint gate; a
/// `Warning` is advisory (the document is still sound, just less precise).
pub type Severity {
  Violation
  Warning
}

/// A single lint result, attributed to an operation (`"GET /todos/{id}"`).
pub type Finding {
  Finding(severity: Severity, location: String, message: String)
}

/// Run every check over `endpoints`, resolving type references against
/// `package`. Findings come back sorted, for stable output.
pub fn lint(endpoints: List(Endpoint), package: pkg.Package) -> List(Finding) {
  [
    duplicate_findings(endpoints),
    list.flat_map(endpoints, fn(e) { endpoint_findings(e, package) }),
  ]
  |> list.flatten
  |> list.sort(compare_findings)
}

/// Whether any finding is a [`Violation`](#Severity).
pub fn has_errors(findings: List(Finding)) -> Bool {
  list.any(findings, fn(finding) { finding.severity == Violation })
}

fn endpoint_findings(e: Endpoint, package: pkg.Package) -> List(Finding) {
  list.flatten([path_param_findings(e), type_ref_findings(e, package)])
}

fn duplicate_findings(endpoints: List(Endpoint)) -> List(Finding) {
  endpoints
  |> list.fold(dict.new(), fn(counts, e) {
    dict.upsert(counts, location(e), fn(existing) {
      option.unwrap(existing, 0) + 1
    })
  })
  |> dict.to_list
  |> list.filter_map(fn(entry) {
    let #(location, count) = entry
    case count > 1 {
      True ->
        Ok(Finding(
          Violation,
          location,
          "operation declared " <> int.to_string(count) <> " times",
        ))
      False -> Error(Nil)
    }
  })
}

fn path_param_findings(e: Endpoint) -> List(Finding) {
  let location = location(e)
  let placeholders = path_placeholders(endpoint.path(e))
  let declared = list.map(endpoint.path_params(e), fn(p) { p.name })

  let missing_declarations =
    placeholders
    |> list.filter(fn(name) { bool.negate(list.contains(declared, name)) })
    |> list.map(fn(name) {
      Finding(
        Violation,
        location,
        "path contains {"
          <> name
          <> "} but it is not declared with with_path_param",
      )
    })
  let missing_placeholders =
    declared
    |> list.filter(fn(name) { bool.negate(list.contains(placeholders, name)) })
    |> list.map(fn(name) {
      Finding(
        Violation,
        location,
        "path parameter \"" <> name <> "\" is declared but absent from the path",
      )
    })
  list.append(missing_declarations, missing_placeholders)
}

fn type_ref_findings(e: Endpoint, package: pkg.Package) -> List(Finding) {
  let location = location(e)
  e
  |> endpoint_type_refs
  |> list.flat_map(fn(reference) {
    let #(module, name) = reference
    let qualified = module <> "." <> name
    case pkg.resolve_type(package, module, name) {
      Error(_) -> [
        Finding(
          Violation,
          location,
          "type `" <> qualified <> "` is not a resolvable public type",
        ),
      ]
      Ok(pkg.Unmodelled(_)) -> [
        Finding(
          Warning,
          location,
          "type `"
            <> qualified
            <> "` is under-described (opaque, generic, or a union with payloads)",
        ),
      ]
      Ok(resolved) ->
        format_findings(location, qualified, resolved, package, module, name)
    }
  })
}

/// The set of OpenAPI `format` names oaisp recognises as well-known. A field may
/// carry any `format` (it is just an annotation), so an unrecognised one is a
/// [`Warning`](#Severity), not an error — it might be a vocabulary the consumer
/// understands. This is the standard JSON Schema / OpenAPI registry.
fn known_formats() -> set.Set(String) {
  set.from_list([
    "date-time", "date", "time", "duration", "email", "idn-email", "hostname",
    "idn-hostname", "ipv4", "ipv6", "uri", "uri-reference", "iri",
    "iri-reference", "uuid", "uri-template", "json-pointer",
    "relative-json-pointer", "regex", "password", "byte", "binary", "int32",
    "int64", "float", "double",
  ])
}

/// Validate the `@format` directives in a referenced type's doc comment against
/// its fields. Every check is a [`Warning`](#Severity): a directive oaisp can't
/// honour is silently dropped from the schema (which stays sound), so these
/// findings exist to stop a typo'd directive from passing unnoticed.
fn format_findings(
  location: String,
  qualified: String,
  resolved: pkg.ResolvedType,
  package: pkg.Package,
  module: String,
  name: String,
) -> List(Finding) {
  case pkg.format_directives(package, module, name) {
    Error(_) -> []
    Ok(directives) -> {
      let fields = string_field_names(resolved)
      let formats = known_formats()
      list.filter_map(directives, fn(directive) {
        case directive {
          pkg.MalformedFormat(line) ->
            Ok(warn(
              location,
              qualified,
              "malformed @format directive `"
                <> line
                <> "` (expected `@format <field>: <format>`)",
            ))
          pkg.FormatDirective(field:, format:) ->
            case dict.get(fields, field) {
              Error(Nil) ->
                Ok(warn(
                  location,
                  qualified,
                  "@format names field `"
                    <> field
                    <> "`, which is not a string field of the type",
                ))
              Ok(IsString) ->
                case set.contains(formats, format) {
                  True -> Error(Nil)
                  False ->
                    Ok(warn(
                      location,
                      qualified,
                      "@format `"
                        <> format
                        <> "` on field `"
                        <> field
                        <> "` is not a known OpenAPI format",
                    ))
                }
              Ok(NotString) ->
                Ok(warn(
                  location,
                  qualified,
                  "@format on field `"
                    <> field
                    <> "` is ignored: only string fields carry a format",
                ))
            }
        }
      })
    }
  }
}

/// Whether a record field can carry a string `format`.
type Stringness {
  IsString
  NotString
}

/// Map a record's field names to whether each can carry a string `format` (a
/// `String`, directly or inside an `Option`). Non-records have no fields.
fn string_field_names(
  resolved: pkg.ResolvedType,
) -> dict.Dict(String, Stringness) {
  case resolved {
    pkg.RecordType(fields, _) ->
      fields
      |> list.map(fn(field) { #(field.name, stringness(field.type_)) })
      |> dict.from_list
    _ -> dict.new()
  }
}

fn stringness(field_type: pkg.FieldType) -> Stringness {
  case field_type {
    pkg.StringType | pkg.FormattedStringType(..) -> IsString
    pkg.OptionType(inner) -> stringness(inner)
    _ -> NotString
  }
}

fn warn(location: String, qualified: String, detail: String) -> Finding {
  Finding(Warning, location, "type `" <> qualified <> "`: " <> detail)
}

fn endpoint_type_refs(e: Endpoint) -> List(#(String, String)) {
  [
    case endpoint.body(e) {
      Some(schema) -> [schema]
      None -> []
    },
    list.filter_map(endpoint.responses(e), fn(r) {
      option.to_result(r.body, Nil)
    }),
    list.map(endpoint.path_params(e), fn(p) { p.schema }),
    list.map(endpoint.query_params(e), fn(p) { p.schema }),
  ]
  |> list.flatten
  |> list.filter_map(fn(schema) {
    case schema {
      TypeRef(module:, name:) -> Ok(#(module, name))
      Scalar(..) -> Error(Nil)
    }
  })
  |> list.unique
}

fn path_placeholders(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter_map(fn(segment) {
    case string.starts_with(segment, "{") && string.ends_with(segment, "}") {
      True -> Ok(segment |> string.drop_start(1) |> string.drop_end(1))
      False -> Error(Nil)
    }
  })
}

fn location(e: Endpoint) -> String {
  string.uppercase(endpoint.method_to_string(endpoint.method(e)))
  <> " "
  <> endpoint.path(e)
}

fn compare_findings(a: Finding, b: Finding) -> order.Order {
  case string.compare(a.location, b.location) {
    order.Eq -> string.compare(a.message, b.message)
    other -> other
  }
}
