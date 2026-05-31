// A typed client built from the generated OpenAPI document with openapi-fetch.
//
// This file is type-checked (tsc --noEmit) against the types openapi-typescript
// generates from the example's openapi.json. If it compiles, the document
// faithfully describes every shape the example declares: typed query and path
// parameters, request bodies, enums, nullable `Option` fields, `Dict`s, nested
// records, and the various response codes.

import createClient from "openapi-fetch";
import type { paths, components } from "./api";

const client = createClient<paths>({ baseUrl: "http://localhost:8080" });

type Todo = components["schemas"]["Todo"];
type Priority = components["schemas"]["Priority"];

export async function demo() {
  // GET /todos — typed query params (limit: number, tag: string).
  const list = await client.GET("/todos", {
    params: { query: { limit: 10, tag: "home" } },
  });
  if (list.data) {
    const total: number = list.data.total;
    const items: Todo[] = list.data.items;
    items.forEach((todo) => {
      const priority: Priority = todo.priority; // "Low" | "Medium" | "High"
      const score: number = todo.score;
      console.log(todo.title, priority, total, score);
    });
  }

  // GET /todos/{id} — typed path param; Option(String) is nullable, Dict is a Record.
  const one = await client.GET("/todos/{id}", { params: { path: { id: "abc" } } });
  if (one.data) {
    const email: string | null | undefined = one.data.owner.email;
    const labels: Record<string, number> = one.data.labels;
    console.log(email, labels);
  }

  // POST /todos — a request body matching NewTodo.
  const created = await client.POST("/todos", {
    body: { title: "Write docs", priority: "High", tags: ["docs"] },
  });
  if (created.data) {
    const id: string = created.data.id;
    console.log(id);
  }

  // DELETE /todos/{id} — a 204 with no body.
  await client.DELETE("/todos/{id}", { params: { path: { id: "abc" } } });
}
