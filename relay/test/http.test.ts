import assert from "node:assert/strict";
import test from "node:test";
import { bearer, body, error, json } from "../src/http";

test("JSON envelopes are compact and never cache tokens", async () => {
  const response = json({ token: "one-time" });
  assert.deepEqual(await response.json(), { ok: true, data: { token: "one-time" } });
  assert.equal(response.headers.get("cache-control"), "no-store");
  const failed = error("unauthorized", 401);
  assert.deepEqual(await failed.json(), { ok: false, error: { code: "unauthorized", message: "Unauthorized", retryable: false } });
});

test("bearer parsing rejects every non-Bearer scheme", () => {
  assert.equal(bearer(new Request("https://relay.test", { headers: { authorization: "Bearer abc" } })), "abc");
  assert.equal(bearer(new Request("https://relay.test", { headers: { authorization: "Basic abc" } })), null);
});

test("only JSON object bodies are accepted", async () => {
  assert.deepEqual(await body(new Request("https://relay.test", { method: "POST", headers: { "content-type": "application/json" }, body: "{\"a\":1}" })), { a: 1 });
  assert.equal(await body(new Request("https://relay.test", { method: "POST", headers: { "content-type": "application/json" }, body: "[]" })), null);
});
