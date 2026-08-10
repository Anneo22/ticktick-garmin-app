const encoder = new TextEncoder();
const decoder = new TextDecoder();

function arrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

export function base64Url(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function fromBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid base64url");
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((value.length + 3) % 4);
  const decoded = atob(padded);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

export function randomSecret(bytes = 32): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256(value: string): Promise<string> {
  return base64Url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
}

async function aesKey(encodedKey: string): Promise<CryptoKey> {
  const raw = fromBase64Url(encodedKey);
  if (raw.length !== 32) throw new Error("TOKEN_ENCRYPTION_KEY must be 32 bytes");
  return crypto.subtle.importKey("raw", arrayBuffer(raw), "AES-GCM", false, ["encrypt", "decrypt"]);
}

export interface EncryptedValue { ciphertext: string; iv: string }

export async function encrypt(value: string, encodedKey: string): Promise<EncryptedValue> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv: arrayBuffer(iv) }, await aesKey(encodedKey), encoder.encode(value));
  return { ciphertext: base64Url(new Uint8Array(ciphertext)), iv: base64Url(iv) };
}

export async function decrypt(value: EncryptedValue, encodedKey: string): Promise<string> {
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: arrayBuffer(fromBase64Url(value.iv)) },
    await aesKey(encodedKey),
    arrayBuffer(fromBase64Url(value.ciphertext)),
  );
  return decoder.decode(plaintext);
}
