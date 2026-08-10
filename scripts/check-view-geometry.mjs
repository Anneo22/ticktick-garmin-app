// Enforces the one-geometry rule in TaskListView: layout() is the only place that computes a
// rectangle, and hit testing reads the stored bounds. A second copy of the geometry is how a
// touch target silently stops matching what was painted.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = await readFile(join(root, "watch", "source", "TaskListView.mc"), "utf8");

function body(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `TaskListView must define ${name}`);
  let depth = 0;
  for (let index = source.indexOf("{", start); index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(start, index + 1);
    }
  }
  throw new Error(`unterminated ${name}`);
}

function code(text) {
  return text.replace(/^\s*\/\/.*$/gm, "");
}

const STORES = ["rowBounds", "nodeBounds", "navBounds", "actionBounds", "actionKind"];
for (const store of STORES) {
  assert.match(source, new RegExp(`\\bvar ${store};`), `TaskListView must store ${store}`);
}

const layout = body("layout") + body("layoutRoute");
for (const producer of ["rowBounds.add", "nodeBounds.add", "navBounds.add"]) {
  const total = source.split(producer).length - 1;
  const inLayout = layout.split(producer).length - 1;
  assert.equal(total, inLayout, `${producer} may only be called from the layout pass`);
  assert.equal(total, 1, `${producer} must have exactly one call site`);
}
assert.equal(source.split("actionBounds = actionButtonBounds").length - 1, 1, "the action target must be laid out in exactly one place");
assert.ok(body("handleAction").includes("actionKind"), "a rendered action must keep its immutable semantic kind");

const hitTest = code(body("handleTap") + body("tapNode"));
for (const operator of ["/", "*", "getWidth()", "getHeight()"]) {
  assert.ok(!hitTest.includes(operator), `hit testing must not recompute geometry (found "${operator}")`);
}
assert.ok(hitTest.includes("contains("), "hit testing must compare against stored bounds");

// The drawing pass must read the stored bounds rather than deriving its own rectangles.
for (const drawer of ["drawRoute", "drawNavigation", "drawCompactRows", "drawActionButton"]) {
  const drawn = body(drawer);
  assert.ok(
    /rowBounds|navBounds|actionBounds/.test(drawn),
    `${drawer} must draw from the stored bounds`,
  );
}

// Garmin Bridge palette only: no stray accent colour may enter the watch UI.
const palette = ["0xFD4E5A", "0x5A5CF5", "0x1A1A1A", "0xD4D4D4"];
for (const token of palette) {
  assert.ok(source.includes(token), `TaskListView must define the Garmin Bridge token ${token}`);
}
for (const hex of source.match(/0x[0-9A-Fa-f]{6}/g) ?? []) {
  assert.ok(
    [...palette, "0x888888", "0x666666"].includes(hex),
    `TaskListView uses off-palette colour ${hex}`,
  );
}

console.log("view: one geometry, palette clean");
