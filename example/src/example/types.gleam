//// The data model for the example API. These public types are exactly what
//// oaisp projects into the OpenAPI document's `components/schemas`.

import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// How urgent a todo is — a fieldless union, projected as a string enum.
pub type Priority {
  Low
  Medium
  High
}

/// A user account.
///
/// `@format` directives attach an OpenAPI `string` `format` to a field without
/// changing its Gleam type — `email` stays a `String`, but the schema marks it
/// `format: email`. Pure metadata, the nearest Gleam gets to an F# `[DataType]`
/// attribute. `oaisp lint` checks every directive against the type's fields.
/// @format email: email
pub type User {
  User(id: String, name: String, email: Option(String))
}

/// A todo item. Exercises every shape oaisp models: scalars (`String`, `Int`,
/// `Float`, `Bool`), a `List`, an `Option`, a `Dict`, a nested record, and an
/// enum.
pub type Todo {
  Todo(
    id: String,
    title: String,
    done: Bool,
    rank: Int,
    score: Float,
    tags: List(String),
    note: Option(String),
    owner: User,
    priority: Priority,
    labels: Dict(String, Int),
  )
}

/// The fields accepted when creating a todo.
pub type NewTodo {
  NewTodo(title: String, priority: Priority, tags: List(String))
}

/// A page of todos.
pub type TodoPage {
  TodoPage(items: List(Todo), total: Int, next: Option(String))
}

/// The query accepted by `GET /todos`. `oaisp` reflects this record's fields
/// into individual query parameters (`with_query_record`), so the record is the
/// single source for the listing's query contract — both optional here.
pub type TodoQuery {
  TodoQuery(limit: Option(Int), tag: Option(String))
}

/// A structured API error.
pub type ApiError {
  ApiError(message: String, code: Int)
}
