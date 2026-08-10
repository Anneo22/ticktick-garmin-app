import assert from "node:assert/strict";
import test from "node:test";
import { webcrypto } from "node:crypto";
import { decrypt, encrypt, fromBase64Url, randomSecret, sha256 } from "../src/crypto";

Object.defineProperty(globalThis, "crypto", { value: webcrypto });

test("random secrets are 256-bit url-safe values", () => {
  const value = randomSecret();
  assert.match(value, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(fromBase64Url(value).length, 32);
});

test("AES-GCM seals TickTick tokens and detects tampering", async () => {
  const key = randomSecret();
  const encrypted = await encrypt("ticktick-access-token", key);
  assert.notEqual(encrypted.ciphertext, "ticktick-access-token");
  assert.equal(await decrypt(encrypted, key), "ticktick-access-token");
  const changedFirstCharacter = encrypted.ciphertext[0] === "A" ? "B" : "A";
  await assert.rejects(decrypt({ ...encrypted, ciphertext: `${changedFirstCharacter}${encrypted.ciphertext.slice(1)}` }, key));
});

test("hashing is deterministic and never preserves the input", async () => {
  assert.equal(await sha256("relay-token"), await sha256("relay-token"));
  assert.notEqual(await sha256("relay-token"), "relay-token");
});
