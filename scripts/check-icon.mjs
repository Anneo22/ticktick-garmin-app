// Independent oracle for the launcher artifacts. It decodes the shipped PNGs rather than
// trusting the renderer, because the previous defect was a valid 80x80 file whose mark
// occupied roughly 20x20 pixels at the origin and still looked correct in a directory listing.
import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const MIN_OCCUPANCY = 0.7;
const MAX_CENTRE_DRIFT = 0.06;
const SURFACE = [0x1a, 0x1a, 0x1a];

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

function decode(buffer) {
  assert.deepEqual([...buffer.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], "not a PNG");
  let offset = 8;
  let header;
  const data = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const payload = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") header = { width: payload.readUInt32BE(0), height: payload.readUInt32BE(4), depth: payload[8], colorType: payload[9] };
    if (type === "IDAT") data.push(payload);
    offset += 12 + length;
  }
  assert.ok(header, "PNG has no IHDR");
  assert.equal(header.depth, 8, "expected 8-bit channels");
  assert.equal(header.colorType, 6, "expected RGBA");
  const raw = inflateSync(Buffer.concat(data));
  const stride = header.width * 4;
  const pixels = Buffer.alloc(header.height * stride);
  for (let y = 0; y < header.height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride);
    for (let x = 0; x < stride; x += 1) {
      const left = x >= 4 ? pixels[y * stride + x - 4] : 0;
      const up = y > 0 ? pixels[(y - 1) * stride + x] : 0;
      const upLeft = y > 0 && x >= 4 ? pixels[(y - 1) * stride + x - 4] : 0;
      const value = filter === 0 ? line[x]
        : filter === 1 ? line[x] + left
        : filter === 2 ? line[x] + up
        : filter === 3 ? line[x] + ((left + up) >> 1)
        : line[x] + paeth(left, up, upLeft);
      pixels[y * stride + x] = value & 0xff;
    }
  }
  return { ...header, pixels };
}

// Foreground is anything that is neither transparent nor the flat surface fill, so a mark
// that hides in one corner of an otherwise correct canvas cannot pass.
function markBounds(image) {
  const bounds = { minX: image.width, minY: image.height, maxX: -1, maxY: -1, count: 0 };
  for (let y = 0; y < image.height; y += 1) {
    for (let x = 0; x < image.width; x += 1) {
      const offset = (y * image.width + x) * 4;
      const alpha = image.pixels[offset + 3];
      if (alpha < 200) continue;
      const delta = Math.max(
        Math.abs(image.pixels[offset] - SURFACE[0]),
        Math.abs(image.pixels[offset + 1] - SURFACE[1]),
        Math.abs(image.pixels[offset + 2] - SURFACE[2]),
      );
      if (delta < 24) continue;
      bounds.count += 1;
      bounds.minX = Math.min(bounds.minX, x);
      bounds.minY = Math.min(bounds.minY, y);
      bounds.maxX = Math.max(bounds.maxX, x);
      bounds.maxY = Math.max(bounds.maxY, y);
    }
  }
  return bounds;
}

async function check(path, expected) {
  const image = decode(await readFile(join(root, path)));
  assert.equal(image.width, expected, `${path}: width must be ${expected}`);
  assert.equal(image.height, expected, `${path}: height must be ${expected}`);

  const centre = (image.height / 2 | 0) * image.width * 4 + (image.width / 2 | 0) * 4;
  assert.equal(image.pixels[centre + 3], 255, `${path}: canvas centre must be opaque`);
  assert.ok(image.pixels[3] < 128, `${path}: rounded corner must stay transparent`);

  const bounds = markBounds(image);
  assert.ok(bounds.count > 0, `${path}: no mark pixels found`);
  const spanX = (bounds.maxX - bounds.minX + 1) / image.width;
  const spanY = (bounds.maxY - bounds.minY + 1) / image.height;
  assert.ok(spanX >= MIN_OCCUPANCY, `${path}: mark spans only ${(spanX * 100).toFixed(1)}% of the width`);
  assert.ok(spanY >= MIN_OCCUPANCY, `${path}: mark spans only ${(spanY * 100).toFixed(1)}% of the height`);

  const driftX = Math.abs((bounds.minX + bounds.maxX + 1) / 2 / image.width - 0.5);
  const driftY = Math.abs((bounds.minY + bounds.maxY + 1) / 2 / image.height - 0.5);
  assert.ok(driftX <= MAX_CENTRE_DRIFT, `${path}: mark is off-centre horizontally by ${(driftX * 100).toFixed(1)}%`);
  assert.ok(driftY <= MAX_CENTRE_DRIFT, `${path}: mark is off-centre vertically by ${(driftY * 100).toFixed(1)}%`);
  return `${path} ${expected}x${expected} mark ${(spanX * 100).toFixed(0)}x${(spanY * 100).toFixed(0)}%`;
}

const svg = await readFile(join(root, "watch", "resources", "drawables", "launcher_icon.svg"), "utf8");
assert.match(svg, /viewBox="0 0 100 100"/, "launcher SVG must use the authored design canvas");
assert.doesNotMatch(svg, /<text|<image|f97316|fb923c/i, "launcher mark must carry no letters, bitmaps, or legacy orange");

// The relay pages inline the same mark. Pin the two copies together so neither can drift.
const relay = await readFile(join(root, "relay", "src", "index.ts"), "utf8");
const elements = svg.match(/<(?:line|circle|rect)\b[^>]*\/>/g) ?? [];
assert.ok(elements.length >= 10, "launcher SVG lost its route-bridge elements");
for (const element of elements) {
  assert.ok(relay.includes(element), `relay route mark is missing the authored element ${element}`);
}

const results = [
  await check(join("watch", "resources", "drawables", "launcher_icon.png"), 80),
  await check(join("docs", "store", "launcher_icon_512.png"), 512),
];
console.log(`icon: ${results.join("; ")}`);
