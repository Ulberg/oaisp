// Calls the running example server with a client created from the generated
// OpenAPI spec (openapi-fetch), and asserts the responses. Proves the document
// matches a real server end to end. Run by live.sh after the server is up.

import createClient from "openapi-fetch";
import assert from "node:assert/strict";

const client = createClient({ baseUrl: "http://localhost:8080" });

// GET /todos/{id} — path param; every modelled shape comes back as declared.
const one = await client.GET("/todos/{id}", { params: { path: { id: "abc" } } });
assert.equal(one.response.status, 200, "GET /todos/{id}");
assert.equal(one.data.id, "abc");
assert.equal(one.data.priority, "High"); // enum
assert.equal(one.data.owner.name, "Ada"); // nested record
assert.equal(one.data.note, null); // Option(None)
assert.equal(one.data.labels.urgent, 2); // Dict
assert.ok(Array.isArray(one.data.tags)); // List

// GET /todos — query params; paginated response.
const list = await client.GET("/todos", {
  params: { query: { limit: 10, tag: "home" } },
});
assert.equal(list.response.status, 200, "GET /todos");
assert.equal(list.data.total, 2);
assert.equal(list.data.items.length, 2);

// POST /todos — request body.
const created = await client.POST("/todos", {
  body: { title: "x", priority: "Low", tags: [] },
});
assert.equal(created.response.status, 201, "POST /todos");
assert.equal(created.data.id, "created-id");

// DELETE /todos/{id} — 204 with no body.
const deleted = await client.DELETE("/todos/{id}", {
  params: { path: { id: "abc" } },
});
assert.equal(deleted.response.status, 204, "DELETE /todos/{id}");

// A 404 surfaces as a typed error envelope.
const missing = await client.GET("/todos/{id}", {
  params: { path: { id: "missing" } },
});
assert.equal(missing.response.status, 404, "missing todo");
assert.equal(missing.error.code, 404);

console.log("✅ live round-trip passed (5 calls)");
