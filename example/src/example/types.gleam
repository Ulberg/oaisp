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

/// A structured API error.
pub type ApiError {
  ApiError(message: String, code: Int)
}
