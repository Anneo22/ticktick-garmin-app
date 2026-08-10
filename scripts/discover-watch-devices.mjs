import { readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MIN_API = [2, 4, 0];
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const connectIqRoot = join(process.env.HOME, "Library", "Application Support", "Garmin", "ConnectIQ");
const deviceRoot = join(connectIqRoot, "Devices");
const activeSdk = (await readFile(join(connectIqRoot, "current-sdk.cfg"), "utf8")).trim();
const sdkVersion = /connectiq-sdk-mac-([0-9.]+)/.exec(activeSdk)?.[1] ?? "unknown";

function versionParts(value) {
  return value.split(".").map(Number);
}

function compareVersions(left, right) {
  const a = versionParts(left);
  const b = versionParts(right);
  for (let index = 0; index < 3; index += 1) {
    const delta = (a[index] ?? 0) - (b[index] ?? 0);
    if (delta !== 0) return delta;
  }
  return 0;
}

const products = [];
for (const id of await readdir(deviceRoot)) {
  let metadata;
  try {
    metadata = JSON.parse(await readFile(join(deviceRoot, id, "compiler.json"), "utf8"));
  } catch {
    continue;
  }
  const watchApp = metadata.appTypes?.find((entry) => entry.type === "watchApp");
  const api = metadata.partNumbers?.map((entry) => entry.connectIQVersion).filter(Boolean).sort(compareVersions).at(-1);
  if (metadata.webDocDeviceGroup !== "Watches/Wearables" || !watchApp || !api || compareVersions(api, MIN_API.join(".")) < 0) continue;
  products.push({
    id,
    name: metadata.displayName,
    api,
    memory: watchApp.memoryLimit,
    family: metadata.deviceFamily,
    verifiedFrom: "sdk",
  });
}

products.sort((left, right) => left.id.localeCompare(right.id));
if (products.length < 100) throw new Error(`SDK watch discovery returned only ${products.length} products`);

const matrix = {
  source: "Garmin SDK compiler.json metadata; Watches/Wearables with watchApp support and Connect IQ API >= 2.4",
  generatedWithSdk: sdkVersion,
  products,
  representative: {
    primaryFenix8: "fenix847mm",
    roundAmoled: "venu3",
    roundMip: "fenix7",
    rectangular: "venusq2",
    buttonOnly: "instinct2",
    smallestInstinct: "instinct2s",
    semiRound: "fr735xt",
    narrowRectangle: "vivoactive_hr",
    largeRectangle: "venux1",
  },
};

await writeFile(join(root, "watch", "device-matrix.json"), `${JSON.stringify(matrix, null, 2)}\n`);
console.log(`devices: discovered ${products.length} SDK-verified watch products`);
