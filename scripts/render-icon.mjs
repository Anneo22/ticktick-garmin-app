// Authors the Garmin Bridge launcher mark once and emits every artifact from that one geometry:
// the SVG source of truth, the 80x80 watch launcher PNG, and the 512x512 Store PNG.
// The mark is a route bridge: a span between two anchored stops with the route arching over it,
// the travelled leg lit in hot coral. No TickTick logo, no letters (concept seed d39802f1).
import { deflateSync } from "node:zlib";
import { writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export const PALETTE = {
  surface: "#1A1A1A",
  text: "#D4D4D4",
  coral: "#FD4E5A",
  klein: "#5A5CF5",
};

// Geometry on a 100x100 design canvas. Every output scales this and nothing else.
const APEX = [50, 26];
const LEFT = [18, 78];
const RIGHT = [82, 78];

export const SHAPES = [
  { kind: "roundedRect", x: 0, y: 0, w: 100, h: 100, r: 22, fill: PALETTE.surface },
  { kind: "segment", from: LEFT, to: RIGHT, width: 5, stroke: PALETTE.klein },
  { kind: "segment", from: APEX, to: RIGHT, width: 9, stroke: PALETTE.text },
  { kind: "segment", from: LEFT, to: APEX, width: 9, stroke: PALETTE.coral },
  { kind: "disc", c: LEFT, r: 8, fill: PALETTE.surface },
  { kind: "ring", c: LEFT, r: 8, width: 5, stroke: PALETTE.text },
  { kind: "disc", c: RIGHT, r: 8, fill: PALETTE.surface },
  { kind: "ring", c: RIGHT, r: 8, width: 5, stroke: PALETTE.text },
  { kind: "disc", c: APEX, r: 11, fill: PALETTE.surface },
  { kind: "ring", c: APEX, r: 11, width: 6, stroke: PALETTE.coral },
  { kind: "disc", c: APEX, r: 4, fill: PALETTE.coral },
];

export function toSvg() {
  const body = SHAPES.map((shape) => {
    if (shape.kind === "roundedRect") {
      return `  <rect x="${shape.x}" y="${shape.y}" width="${shape.w}" height="${shape.h}" rx="${shape.r}" fill="${shape.fill}"/>`;
    }
    if (shape.kind === "segment") {
      return `  <line x1="${shape.from[0]}" y1="${shape.from[1]}" x2="${shape.to[0]}" y2="${shape.to[1]}" stroke="${shape.stroke}" stroke-width="${shape.width}" stroke-linecap="round"/>`;
    }
    if (shape.kind === "disc") {
      return `  <circle cx="${shape.c[0]}" cy="${shape.c[1]}" r="${shape.r}" fill="${shape.fill}"/>`;
    }
    return `  <circle cx="${shape.c[0]}" cy="${shape.c[1]}" r="${shape.r}" fill="none" stroke="${shape.stroke}" stroke-width="${shape.width}"/>`;
  }).join("\n");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100" role="img" aria-label="Garmin Bridge route mark">\n${body}\n</svg>\n`;
}

function rgb(hex) {
  return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
}

function roundedRectDistance(px, py, shape) {
  const halfW = shape.w / 2;
  const halfH = shape.h / 2;
  const dx = Math.abs(px - (shape.x + halfW)) - (halfW - shape.r);
  const dy = Math.abs(py - (shape.y + halfH)) - (halfH - shape.r);
  const outside = Math.hypot(Math.max(dx, 0), Math.max(dy, 0));
  return outside + Math.min(Math.max(dx, dy), 0) - shape.r;
}

function segmentDistance(px, py, from, to) {
  const vx = to[0] - from[0];
  const vy = to[1] - from[1];
  const wx = px - from[0];
  const wy = py - from[1];
  const lengthSquared = vx * vx + vy * vy;
  const t = lengthSquared === 0 ? 0 : Math.min(1, Math.max(0, (wx * vx + wy * vy) / lengthSquared));
  return Math.hypot(wx - t * vx, wy - t * vy);
}

function distance(px, py, shape) {
  if (shape.kind === "roundedRect") return roundedRectDistance(px, py, shape);
  if (shape.kind === "segment") return segmentDistance(px, py, shape.from, shape.to) - shape.width / 2;
  if (shape.kind === "disc") return Math.hypot(px - shape.c[0], py - shape.c[1]) - shape.r;
  return Math.abs(Math.hypot(px - shape.c[0], py - shape.c[1]) - shape.r) - shape.width / 2;
}

// Analytic one-pixel antialiasing keeps the mark crisp at launcher size instead of blurring it.
export function raster(size) {
  const scale = size / 100;
  const pixels = new Uint8ClampedArray(size * size * 4);
  for (const shape of SHAPES) {
    const [r, g, b] = rgb(shape.fill ?? shape.stroke);
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        const signed = distance((x + 0.5) / scale, (y + 0.5) / scale, shape) * scale;
        const coverage = Math.min(1, Math.max(0, 0.5 - signed));
        if (coverage <= 0) continue;
        const offset = (y * size + x) * 4;
        const dstAlpha = pixels[offset + 3] / 255;
        const outAlpha = coverage + dstAlpha * (1 - coverage);
        for (let channel = 0; channel < 3; channel += 1) {
          const source = [r, g, b][channel];
          pixels[offset + channel] = (source * coverage + pixels[offset + channel] * dstAlpha * (1 - coverage)) / outAlpha;
        }
        pixels[offset + 3] = outAlpha * 255;
      }
    }
  }
  return pixels;
}

const CRC_TABLE = Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit += 1) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  return value >>> 0;
});

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typed = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typed));
  return Buffer.concat([length, typed, crc]);
}

export function encodePng(size, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8;
  header[9] = 6;
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y += 1) {
    raw[y * (size * 4 + 1)] = 0;
    Buffer.from(pixels.buffer, y * size * 4, size * 4).copy(raw, y * (size * 4 + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

if (fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const targets = [
    [join(root, "watch", "resources", "drawables", "launcher_icon.png"), 80],
    [join(root, "docs", "store", "launcher_icon_512.png"), 512],
  ];
  await writeFile(join(root, "watch", "resources", "drawables", "launcher_icon.svg"), toSvg());
  for (const [path, size] of targets) {
    await writeFile(path, encodePng(size, raster(size)));
  }
  console.log(`icon: rendered SVG plus ${targets.map(([, size]) => `${size}x${size}`).join(" and ")} PNG`);
}
