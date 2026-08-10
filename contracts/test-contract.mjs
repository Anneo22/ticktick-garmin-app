import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(root, "fixtures");
const files = (await readdir(fixtureDir)).filter((name) => name.endsWith(".json"));

assert.ok(files.length >= 7, "contract fixture set is incomplete");

for (const file of files) {
  const value = JSON.parse(await readFile(join(fixtureDir, file), "utf8"));
  assert.equal(typeof value.ok, "boolean", `${file}: ok must be boolean`);
  assert.notEqual("data" in value, "error" in value, `${file}: exactly one envelope payload is required`);

  if (value.ok) {
    assert.equal(typeof value.data, "object", `${file}: data must be an object`);
  } else {
    assert.equal(typeof value.error.code, "string", `${file}: error code is required`);
    assert.equal(typeof value.error.message, "string", `${file}: error message is required`);
    assert.equal(typeof value.error.retryable, "boolean", `${file}: retryable is required`);
  }

  const bytes = Buffer.byteLength(JSON.stringify(value));
  assert.ok(bytes <= 16 * 1024, `${file}: fixture exceeds the 16 KB watch response budget`);
}

const tasks = JSON.parse(await readFile(join(fixtureDir, "tasks-today.json"), "utf8"));
assert.ok(tasks.data.tasks.length <= 20, "task page must remain bounded");
for (const task of tasks.data.tasks) {
  assert.equal(typeof task.id, "string");
  assert.equal(typeof task.projectId, "string");
  assert.equal(typeof task.title, "string");
  assert.equal(task.status, 0, "today fixture must contain open tasks only");
}

const inbox = JSON.parse(await readFile(join(fixtureDir, "tasks-inbox.json"), "utf8"));
assert.ok(inbox.data.tasks.length <= 20, "Inbox page must remain bounded");
assert.ok(inbox.data.tasks.every((task) => typeof task.projectId === "string"), "every visible Inbox task must remain completable");

const relayClient = await readFile(join(root, "..", "watch", "source", "RelayClient.mc"), "utf8");
assert.match(relayClient, /utcOffsetMinutes/, "watch must send its local UTC offset to date views");
assert.match(relayClient, /\/v1\/projects/, "watch and relay must share the projects route");

const taskController = await readFile(join(root, "..", "watch", "source", "TaskController.mc"), "utf8");
assert.match(taskController, /Comm\.openWebPage/, "watch must open the phone pairing flow");
assert.match(taskController, /mutation_outcome_unknown/, "watch must distinguish uncertain mutations from retryable failures");

console.log(`contract: ${files.length} fixtures valid`);
