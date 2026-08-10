import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const matrixPath = join(root, "watch", "device-matrix.json");
const templatePath = join(root, "watch", "manifest.xml.in");
const outputPath = join(root, "watch", "manifest.xml");
const matrix = JSON.parse(await readFile(matrixPath, "utf8"));

if (!Array.isArray(matrix.products) || matrix.products.length === 0) {
  throw new Error("watch/device-matrix.json has no SDK-verified product IDs");
}

for (const product of matrix.products) {
  if (!product.id || !product.name || product.verifiedFrom !== "sdk") {
    throw new Error("every product needs id, name, and verifiedFrom=sdk");
  }
}

const products = matrix.products
  .map((product) => `            <iq:product id="${product.id}"/>`)
  .join("\n");
const template = await readFile(templatePath, "utf8");
await writeFile(outputPath, template.replace("__PRODUCTS__", products));
console.log(`devices: generated manifest for ${matrix.products.length} SDK-verified products`);
