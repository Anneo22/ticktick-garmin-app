import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { decrypt, encrypt, randomSecret, sha256 } from "../src/crypto";
import worker, { tasksForInbox, tasksForView, type Env } from "../src/index";

Object.defineProperty(globalThis, "crypto", { value: webcrypto });

type Pairing = { id: string; userCode: string; secretHash: string; oauthCompletedAt: number | null; expiresAt: number; oauthStateHash?: string; oauthStateUsed?: boolean };
type StoredSession = { id: string; pairingId: string; bearerHash: string; ciphertext: string; iv: string; revoked: boolean };

class FakeD1 {
  pairing: Pairing | undefined;
  session: StoredSession | undefined;
  mutations = new Map<string, "pending" | "applied" | "unknown">();
  calls: Array<{ sql: string; values: unknown[] }> = [];

  prepare(sql: string) {
    return {
      bind: (...values: unknown[]) => ({
        first: async <T>() => this.first<T>(sql, values),
        run: async () => this.run(sql, values),
      }),
    };
  }

  private async first<T>(sql: string, values: unknown[]): Promise<T | null> {
    if (sql.startsWith("SELECT id, oauth_completed_at, expires_at FROM pairings WHERE device_secret_hash")) {
      const pairing = this.pairing;
      if (!pairing || pairing.secretHash !== values[0]) return null;
      return { id: pairing.id, oauth_completed_at: pairing.oauthCompletedAt, expires_at: pairing.expiresAt } as T;
    }
    if (sql.startsWith("SELECT id FROM pairings WHERE pairing_code")) {
      const pairing = this.pairing;
      return pairing && pairing.userCode === values[0] ? { id: pairing.id } as T : null;
    }
    if (sql.startsWith("SELECT id, expires_at FROM pairings WHERE oauth_state_hash")) {
      const pairing = this.pairing;
      return pairing && pairing.oauthStateHash === values[0] && !pairing.oauthStateUsed ? { id: pairing.id, expires_at: pairing.expiresAt } as T : null;
    }
    if (sql.startsWith("SELECT id, token_ciphertext, token_iv FROM sessions")) {
      return this.session && !this.session.revoked && this.session.bearerHash === values[0]
        ? { id: this.session.id, token_ciphertext: this.session.ciphertext, token_iv: this.session.iv } as T : null;
    }
    if (sql.startsWith("SELECT bearer_token_hash, revoked_at FROM sessions WHERE pairing_id")) {
      return this.session && this.session.pairingId === values[0]
        ? { bearer_token_hash: this.session.bearerHash, revoked_at: this.session.revoked ? 1 : null } as T : null;
    }
    if (sql.startsWith("SELECT status FROM mutations")) {
      const key = `${values[0]}:${values[1]}`;
      const status = this.mutations.get(key);
      return status ? { status } as T : null;
    }
    throw new Error(`Unexpected D1 read: ${sql}`);
  }

  private async run(sql: string, values: unknown[]) {
    this.calls.push({ sql, values });
    if (sql.startsWith("INSERT INTO pairings")) {
      this.pairing = { id: values[0] as string, userCode: values[1] as string, secretHash: values[2] as string, expiresAt: values[3] as number, oauthCompletedAt: null };
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE pairings SET oauth_state_hash")) {
      if (!this.pairing) return { meta: { changes: 0 } };
      this.pairing.oauthStateHash = values[0] as string;
      this.pairing.oauthStateUsed = false;
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE pairings SET oauth_state_used_at")) {
      if (!this.pairing || this.pairing.id !== values[1] || this.pairing.oauthStateHash !== values[2] || this.pairing.oauthStateUsed) return { meta: { changes: 0 } };
      this.pairing.oauthStateUsed = true;
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("INSERT INTO sessions")) {
      this.session = { id: values[0] as string, pairingId: values[1] as string, bearerHash: values[2] as string, ciphertext: values[3] as string, iv: values[4] as string, revoked: true };
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE pairings SET oauth_completed_at")) {
      if (this.pairing) this.pairing.oauthCompletedAt = values[0] as number;
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE sessions SET bearer_token_hash")) {
      if (!this.session || this.session.pairingId !== values[1] || !this.session.revoked) return { meta: { changes: 0 } };
      this.session.bearerHash = values[0] as string;
      this.session.revoked = false;
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("INSERT OR IGNORE INTO mutations")) {
      const key = `${values[0]}:${values[1]}`;
      if (this.mutations.has(key)) return { meta: { changes: 0 } };
      this.mutations.set(key, "pending");
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE mutations")) {
      this.mutations.set(`${values[1]}:${values[2]}`, values[0] as "applied" | "unknown");
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("DELETE FROM mutations")) {
      this.mutations.delete(`${values[0]}:${values[1]}`);
      return { meta: { changes: 1 } };
    }
    if (sql.startsWith("UPDATE sessions SET revoked_at")) {
      if (this.session) this.session.revoked = true;
      return { meta: { changes: 1 } };
    }
    throw new Error(`Unexpected D1 write: ${sql}`);
  }
}

const key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const baseEnv = (db: FakeD1): Env => ({
  DB: db as unknown as D1Database,
  TICKTICK_CLIENT_ID: "client-id",
  TICKTICK_CLIENT_SECRET: "client-secret",
  TICKTICK_REDIRECT_URI: "https://relay.test/v1/oauth/callback",
  TOKEN_ENCRYPTION_KEY: key,
  PAIRING_VERIFICATION_URL: "https://example.invalid/pair",
  RATE_LIMITER: { limit: async () => ({ success: true }) },
});

async function fixture(name: string): Promise<unknown> {
  return JSON.parse(await readFile(new URL(`../../contracts/fixtures/${name}`, import.meta.url), "utf8"));
}

async function authenticatedEnv(db: FakeD1): Promise<{ env: Env; relayToken: string }> {
  const relayToken = randomSecret();
  const sealed = await encrypt("ticktick-access-token", key);
  db.session = { id: "session-1", pairingId: "pairing-1", bearerHash: await sha256(relayToken), ciphertext: sealed.ciphertext, iv: sealed.iv, revoked: false };
  return { env: baseEnv(db), relayToken };
}

test("source-IP rate limits reject public and authenticated routes before database access", async () => {
  const db = new FakeD1();
  const keys: string[] = [];
  const env = {
    ...baseEnv(db),
    RATE_LIMITER: {
      limit: async ({ key: rateKey }: { key: string }) => {
        keys.push(rateKey);
        return { success: false };
      },
    },
  };
  const ip = "203.0.113.7";
  const headers = { "cf-connecting-ip": ip, "content-type": "application/json" };
  const requests = [
    new Request("https://relay.test/v1/pair/start", { method: "POST", headers, body: "{}" }),
    new Request("https://relay.test/v1/pair/status", { method: "POST", headers, body: JSON.stringify({ deviceSecret: randomSecret() }) }),
    new Request("https://relay.test/v1/pair/authorize?code=ABC234", { headers }),
    new Request("https://relay.test/v1/oauth/callback?code=oauth-code&state=oauth-state", { headers }),
    new Request("https://relay.test/v1/projects", { headers: { ...headers, authorization: `Bearer ${randomSecret()}` } }),
  ];
  for (const request of requests) {
    const response = await worker.fetch(request, env);
    assert.equal(response.status, 429);
    assert.equal((await response.json() as { error: { code: string } }).error.code, "rate_limited");
  }
  const addressHash = await sha256(ip);
  assert.deepEqual(keys, [
    `pair:start:${addressHash}`,
    `pair:status:${addressHash}`,
    `pair:authorize:${addressHash}`,
    `pair:callback:${addressHash}`,
    `api:${addressHash}`,
  ]);
  assert.equal(db.calls.length, 0);
});

test("pair start creates and returns the contract's device secret, without accepting one", async () => {
  const db = new FakeD1();
  const response = await worker.fetch(new Request("https://relay.test/v1/pair/start", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" }), baseEnv(db));
  const actual = await response.json() as { ok: boolean; data: Record<string, unknown> };
  const expected = await fixture("pair-start.json") as { ok: boolean; data: Record<string, unknown> };
  assert.equal(actual.ok, expected.ok);
  assert.deepEqual(Object.keys(actual.data).sort(), Object.keys(expected.data).sort());
  assert.match(actual.data.deviceSecret as string, /^[A-Za-z0-9_-]{43}$/);
  assert.match(actual.data.userCode as string, /^[A-Z2-9]{6}$/);
  assert.equal(actual.data.verificationUrl, expected.data.verificationUrl);
  assert.equal(actual.data.expiresIn, expected.data.expiresIn);
  assert.equal(actual.data.pollAfter, expected.data.pollAfter);
  assert.notEqual(db.pairing?.secretHash, actual.data.deviceSecret);
});

test("pair status follows the pending and one-time paired fixtures", async () => {
  const db = new FakeD1();
  const env = baseEnv(db);
  const deviceSecret = randomSecret();
  db.pairing = { id: "pairing-1", userCode: "ABC234", secretHash: await sha256(deviceSecret), oauthCompletedAt: null, expiresAt: Math.floor(Date.now() / 1000) + 60 };
  const pending = await worker.fetch(new Request("https://relay.test/v1/pair/status", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceSecret }) }), env);
  assert.deepEqual(await pending.json(), await fixture("pair-pending.json"));
  const sealed = await encrypt("ticktick-access-token", key);
  db.pairing.oauthCompletedAt = Math.floor(Date.now() / 1000);
  db.session = { id: "session-1", pairingId: "pairing-1", bearerHash: await sha256("pending:pairing-1"), ciphertext: sealed.ciphertext, iv: sealed.iv, revoked: true };
  const paired = await worker.fetch(new Request("https://relay.test/v1/pair/status", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceSecret }) }), env);
  const pairedData = await paired.json() as { ok: boolean; data: Record<string, string> };
  assert.equal(pairedData.ok, true);
  assert.equal(pairedData.data.status, "paired");
  assert.equal(pairedData.data.relayToken, deviceSecret);
  const repeated = await worker.fetch(new Request("https://relay.test/v1/pair/status", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceSecret }) }), env);
  assert.equal(repeated.status, 200);
  assert.deepEqual(await repeated.json(), pairedData);
});

test("an expired pairing can restart, while a completed grant remains deliverable", async () => {
  const db = new FakeD1();
  const env = baseEnv(db);
  const deviceSecret = randomSecret();
  db.pairing = { id: "pairing-1", userCode: "ABC234", secretHash: await sha256(deviceSecret), oauthCompletedAt: null, expiresAt: Math.floor(Date.now() / 1000) - 1 };
  const expired = await worker.fetch(new Request("https://relay.test/v1/pair/status", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceSecret }) }), env);
  assert.equal(expired.status, 410);

  const sealed = await encrypt("ticktick-access-token", key);
  db.pairing.oauthCompletedAt = Math.floor(Date.now() / 1000) - 1;
  db.session = { id: "session-1", pairingId: "pairing-1", bearerHash: await sha256("pending:pairing-1"), ciphertext: sealed.ciphertext, iv: sealed.iv, revoked: true };
  const completed = await worker.fetch(new Request("https://relay.test/v1/pair/status", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceSecret }) }), env);
  assert.equal(completed.status, 200);
  assert.equal((await completed.json() as { data: { relayToken: string } }).data.relayToken, deviceSecret);
});

test("OAuth authorization requests TickTick's read and write task scopes", async () => {
  const db = new FakeD1();
  db.pairing = { id: "pairing-1", userCode: "ABC234", secretHash: "hash", oauthCompletedAt: null, expiresAt: Math.floor(Date.now() / 1000) + 60 };
  const response = await worker.fetch(new Request("https://relay.test/v1/pair/authorize?code=ABC234"), baseEnv(db));
  assert.equal(response.status, 302);
  const target = new URL(response.headers.get("location")!);
  assert.equal(target.origin, "https://ticktick.com");
  assert.equal(target.searchParams.get("scope"), "tasks:read tasks:write");
  assert.match(target.searchParams.get("state")!, /^[A-Za-z0-9_-]{43}$/);
});

test("pairing codes are normalized before lookup", async () => {
  const db = new FakeD1();
  db.pairing = { id: "pairing-1", userCode: "ABC234", secretHash: "hash", oauthCompletedAt: null, expiresAt: Math.floor(Date.now() / 1000) + 60 };
  const response = await worker.fetch(new Request("https://relay.test/v1/pair/authorize?code=abc234"), baseEnv(db));
  assert.equal(response.status, 302);
  assert.equal(db.calls.find((call) => call.sql.startsWith("UPDATE pairings SET oauth_state_hash"))?.values[1], "pairing-1");
});

test("pairing page is self-contained, safely prefills a code, and posts only to the named authorize route", async () => {
  const response = await worker.fetch(new Request("https://relay.test/pair?code=ABC234"), baseEnv(new FakeD1()));
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html/);
  assert.match(response.headers.get("content-security-policy") ?? "", /form-action 'self' https:\/\/ticktick\.com(?:;|$)/);
  assert.match(html, /action="\/v1\/pair\/authorize"/);
  assert.match(html, /autocapitalize="characters"/);
  assert.match(html, /value="ABC234"/);
  assert.doesNotMatch(html, /client[_-]?secret|access[_-]?token/i);
  const unsafe = await worker.fetch(new Request("https://relay.test/pair?code=%22%3E%3Cscript%3E"), baseEnv(new FakeD1()));
  assert.doesNotMatch(await unsafe.text(), /<script>/);
});

const publicPages = async (): Promise<Array<{ name: string; html: string; policy: string }>> => {
  const pair = await worker.fetch(new Request("https://relay.test/pair"), baseEnv(new FakeD1()));
  const db = new FakeD1();
  const state = randomSecret();
  db.pairing = { id: "pairing-1", userCode: "ABC234", secretHash: "hash", oauthCompletedAt: null, expiresAt: Math.floor(Date.now() / 1000) + 60, oauthStateHash: await sha256(state), oauthStateUsed: false };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async () => Response.json({ access_token: "ticktick-access-token" })) as typeof fetch;
  const complete = await worker
    .fetch(new Request(`https://relay.test/v1/oauth/callback?code=oauth-code&state=${state}`), baseEnv(db))
    .finally(() => { globalThis.fetch = originalFetch; });
  return [
    { name: "pair", html: await pair.text(), policy: pair.headers.get("content-security-policy") ?? "" },
    { name: "complete", html: await complete.text(), policy: complete.headers.get("content-security-policy") ?? "" },
  ];
};

test("public pages are semantic, responsive, and drawn in the Garmin Bridge palette", async () => {
  for (const { name, html } of await publicPages()) {
    assert.match(html, /<html lang="en">/, `${name}: page must declare its language`);
    assert.match(html, /<meta name="viewport" content="width=device-width,initial-scale=1">/, `${name}: page must be responsive`);
    assert.match(html, /<main>[\s\S]*<\/main>/, `${name}: page must use a main landmark`);
    assert.match(html, /<header>[\s\S]*<h1>/, `${name}: page must use a header and a single heading`);
    assert.equal(html.match(/<h1>/g)?.length, 1, `${name}: page must have exactly one h1`);
    assert.match(html, /role="img" aria-label="Garmin Bridge route mark"/, `${name}: page must carry the route mark`);
    assert.match(html, /clamp\(/, `${name}: page must scale its type and padding fluidly`);
    for (const token of ["#1A1A1A", "#D4D4D4", "#FD4E5A", "#5A5CF5"]) {
      assert.ok(html.includes(token), `${name}: page must use the Garmin Bridge token ${token}`);
    }
    assert.doesNotMatch(html, /#f97316|#fb923c|orange/i, `${name}: page must carry no legacy orange`);
  }
});

test("public pages carry a strict per-response content security policy", async () => {
  for (const { name, html, policy } of await publicPages()) {
    assert.match(policy, /^default-src 'none';/, `${name}: policy must deny by default`);
    assert.doesNotMatch(policy, /unsafe-inline|unsafe-eval|unsafe-hashes/, `${name}: policy must not relax inline execution`);
    assert.match(policy, /script-src 'none'/, `${name}: policy must forbid script`);
    assert.match(policy, /object-src 'none'/, `${name}: policy must forbid plugins`);
    assert.match(policy, /base-uri 'none'/, `${name}: policy must pin the base URI`);
    assert.match(policy, /frame-ancestors 'none'/, `${name}: policy must forbid framing`);
    const styleNonce = /style-src 'nonce-([a-f0-9]{32})'/.exec(policy);
    assert.ok(styleNonce, `${name}: policy must carry a hex style nonce`);
    assert.ok(html.includes(`<style nonce="${styleNonce[1]}">`), `${name}: inline style must match the policy nonce`);
    assert.doesNotMatch(html, /<script|\son(?:click|load|error|focus|input|submit|change|mouse[a-z]+)=/i, `${name}: page must contain no script or inline handler`);
  }
});

test("public pages carry a fresh nonce per response", async () => {
  const nonces = new Set<string>();
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const response = await worker.fetch(new Request("https://relay.test/pair"), baseEnv(new FakeD1()));
    nonces.add(/nonce-([a-f0-9]{32})/.exec(response.headers.get("content-security-policy") ?? "")?.[1] ?? "");
  }
  assert.equal(nonces.size, 3);
});

test("public pages identify the product, never a person or a private host", async () => {
  for (const { name, html } of await publicPages()) {
    assert.match(html, /Garmin Bridge/, `${name}: page must name the product family`);
    assert.doesNotMatch(html, /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, `${name}: page must expose no email address`);
    assert.doesNotMatch(html, /mailto:/i, `${name}: page must expose no mail route`);
    for (const host of html.match(/[A-Za-z0-9.-]+\.workers\.dev/g) ?? []) {
      assert.equal(host, "ticktick-garmin-relay.garmin-bridge.workers.dev", `${name}: unexpected relay host ${host}`);
    }
  }
});

test("the pairing page states the three pairing steps in order", async () => {
  const response = await worker.fetch(new Request("https://relay.test/pair"), baseEnv(new FakeD1()));
  const html = await response.text();
  const steps = [...html.matchAll(/<li>(.*?)<\/li>/g)].map((match) => match[1]);
  assert.equal(steps.length, 3);
  assert.match(steps[0], /six-character code shown on your watch/);
  assert.match(steps[1], /Sign in to TickTick/);
  assert.match(steps[2], /Return to your watch and press START/);
  assert.match(html, /<label for="code">/);
  assert.match(html, /<input id="code"/);
});

test("the completion page sends the user back to the watch by touch or by START", async () => {
  const [, complete] = await publicPages();
  assert.match(complete.html, /Return to your watch/);
  assert.match(complete.html, /tap anywhere or press START/);
  assert.doesNotMatch(complete.html, /press Select/);
});

test("OAuth callback sends TickTick every required token-exchange field", async (context) => {
  const db = new FakeD1();
  const state = randomSecret();
  db.pairing = { id: "pairing-1", userCode: "ABC234", secretHash: "hash", oauthCompletedAt: null, expiresAt: Math.floor(Date.now() / 1000) + 60, oauthStateHash: await sha256(state), oauthStateUsed: false };
  let tokenRequest: Request | undefined;
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
    tokenRequest = input instanceof Request ? input : new Request(input, init);
    return Response.json({ access_token: "ticktick-access-token" });
  });
  try {
    const response = await worker.fetch(new Request(`https://relay.test/v1/oauth/callback?code=oauth-code&state=${state}`), baseEnv(db));
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type") ?? "", /^text\/html/);
    assert.match(await response.text(), /Return to your watch/);
    assert.equal(tokenRequest?.url, "https://ticktick.com/oauth/token");
    assert.equal(tokenRequest?.method, "POST");
    const form = new URLSearchParams(await tokenRequest?.text());
    assert.equal(form.get("code"), "oauth-code");
    assert.equal(form.get("grant_type"), "authorization_code");
    assert.equal(form.get("redirect_uri"), "https://relay.test/v1/oauth/callback");
    assert.equal(form.get("scope"), "tasks:read tasks:write");
    assert.match(tokenRequest?.headers.get("authorization") ?? "", /^Basic /);
    assert.equal(db.pairing.oauthStateUsed, true);
    assert.notEqual(db.session?.ciphertext, "ticktick-access-token");
  } finally {
    context.mock.restoreAll();
  }
});

test("project tasks use the named endpoint and normalize the contract fixture", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const expected = await fixture("tasks-today.json") as { data: { tasks: unknown[] } };
  const calls: Request[] = [];
  const originalFetch = globalThis.fetch;
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init);
    calls.push(request);
    return Response.json({ tasks: expected.data.tasks });
  });
  try {
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks?view=project&projectId=project-fixture-1", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    const actual = await response.json() as { ok: boolean; data: { tasks: unknown[]; syncedAt: string } };
    assert.equal(actual.ok, true);
    assert.deepEqual(actual.data.tasks, expected.data.tasks);
    assert.match(actual.data.syncedAt, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(calls.length, 1);
    assert.equal(new URL(calls[0].url).pathname, "/open/v1/project/project-fixture-1/data");
    assert.equal(calls[0].method, "GET");
    assert.equal(calls[0].headers.get("authorization"), "Bearer ticktick-access-token");
  } finally {
    context.mock.restoreAll();
    globalThis.fetch = originalFetch;
  }
});

test("malformed successful task payload is an upstream failure, not an empty list", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  context.mock.method(globalThis, "fetch", async () => new Response("<html>not json</html>", {
    status: 200,
    headers: { "content-type": "text/html" },
  }));
  try {
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks?view=project&projectId=project-1", {
      headers: { authorization: `Bearer ${relayToken}` },
    }), env);
    assert.equal(response.status, 502);
    const body = await response.json() as { ok: boolean; error: { code: string; retryable: boolean } };
    assert.equal(body.ok, false);
    assert.equal(body.error.code, "temporarily_unavailable");
    assert.equal(body.error.retryable, true);
  } finally {
    context.mock.restoreAll();
  }
});

test("Today puts current tasks first and overdue tasks one backward scroll away", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const now = new Date();
  const dayStart = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const upstreamTasks = [
    { id: "due-today", projectId: "project-1", title: "Due today", startDate: new Date(dayStart - 86_400_000).toISOString(), dueDate: new Date(dayStart + 3_600_000).toISOString(), status: 0 },
    { id: "due-only-today", projectId: "project-1", title: "Due only today", dueDate: new Date(dayStart + 5_400_000).toISOString(), status: 0 },
    { id: "due-yesterday", projectId: "project-1", title: "Due yesterday", startDate: new Date(dayStart - 172_800_000).toISOString(), dueDate: new Date(dayStart - 3_600_000).toISOString(), status: 0 },
    { id: "start-today", projectId: "project-1", title: "Starts today", startDate: new Date(dayStart + 7_200_000).toISOString(), status: 0 },
  ];
  context.mock.method(globalThis, "fetch", async () => Response.json(upstreamTasks));
  try {
    const headers = { authorization: `Bearer ${relayToken}` };
    const today = await worker.fetch(new Request("https://relay.test/v1/tasks?view=today&utcOffsetMinutes=0", { headers }), env);
    const overdue = await worker.fetch(new Request("https://relay.test/v1/tasks?view=overdue&utcOffsetMinutes=0", { headers }), env);
    const todayTasks = (await today.json() as { data: { tasks: Array<{ id: string; isOverdue?: boolean }> } }).data.tasks;
    const overdueTasks = (await overdue.json() as { data: { tasks: Array<{ id: string; isOverdue?: boolean }> } }).data.tasks;
    assert.deepEqual(todayTasks.map((task) => task.id), ["due-today", "due-only-today", "start-today", "due-yesterday"]);
    assert.equal(todayTasks[0].isOverdue, undefined);
    assert.equal(todayTasks[3].isOverdue, true);
    const overdueIds = overdueTasks.map((task) => task.id);
    assert.deepEqual(overdueIds, ["due-yesterday"]);
    assert.equal(overdueTasks[0].isOverdue, true);
  } finally {
    context.mock.restoreAll();
  }
});

test("Inbox contains only open tasks outside every named list", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const calls: Request[] = [];
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init);
    calls.push(request);
    const path = new URL(request.url).pathname;
    if (path.endsWith("/project")) {
      return Response.json([
        { id: "work", name: "Work" },
        { id: "personal", name: "Personal" },
      ]);
    }
    return Response.json({ tasks: [
      { id: "work-task", projectId: "work", title: "Inside Work", status: 0 },
      { id: "inbox-task", projectId: "inbox-internal", title: "Inbox task", status: 0 },
      { id: "unassigned-task", title: "Malformed task without project field", status: 0 },
    ] });
  });
  try {
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks?view=inbox", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    assert.equal(response.status, 200);
    const payload = await response.json() as { data: { tasks: Array<{ id: string; projectId: string }> } };
    assert.deepEqual(payload.data.tasks.map((task) => task.id), ["inbox-task"]);
    assert.equal(payload.data.tasks[0].projectId, "inbox-internal");
    assert.equal(calls.length, 2);
    const shapes = calls.map((call) => `${call.method} ${new URL(call.url).pathname}`).sort();
    assert.deepEqual(shapes, ["GET /open/v1/project", "POST /open/v1/task/filter"]);
  } finally {
    context.mock.restoreAll();
  }
});

test("Inbox derivation rejects a malformed list response", () => {
  assert.equal(tasksForInbox([{ id: "task-1", projectId: "inbox" }], { projects: [] }), null);
  assert.equal(tasksForInbox([{ id: "task-1", projectId: "inbox" }], [{ name: "Missing ID" }]), null);
});

test("projects are named, bounded, and normalized", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const expected = await fixture("projects.json") as { ok: boolean; data: { projects: unknown[] } };
  const originalFetch = globalThis.fetch;
  context.mock.method(globalThis, "fetch", async () => Response.json([
    ...(expected.data.projects as object[]),
    { id: "closed", name: "Closed", closed: true },
    { name: "Missing id" },
  ]));
  try {
    const response = await worker.fetch(new Request("https://relay.test/v1/projects", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    assert.deepEqual(await response.json(), expected);
  } finally {
    context.mock.restoreAll();
    globalThis.fetch = originalFetch;
  }
});

test("watch-facing task and project responses are bounded", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const originalFetch = globalThis.fetch;
  const longText = "x".repeat(2_000);
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request) => {
    const path = new URL(input instanceof Request ? input.url : input).pathname;
    return path.endsWith("/project")
      ? Response.json(Array.from({ length: 50 }, (_, index) => ({ id: `${index}-${longText}`, name: longText, color: longText, kind: longText, permission: longText, viewMode: longText })))
      : Response.json(Array.from({ length: 20 }, (_, index) => ({ id: `${index}-${longText}`, projectId: longText, title: longText, dueDate: longText, kind: longText, status: 0, isAllDay: true, priority: 5 })));
  });
  try {
    const tasksResponse = await worker.fetch(new Request("https://relay.test/v1/tasks?view=project&projectId=project-1", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    const taskText = await tasksResponse.text();
    const tasksBody = JSON.parse(taskText) as { data: { tasks: Array<{ title: string; id: string; projectId: string; dueDate: string; kind: string }> } };
    assert.equal(tasksBody.data.tasks.length, 20);
    assert.equal(tasksBody.data.tasks[0].title.length, 120);
    assert.equal(tasksBody.data.tasks[0].id.length, 128);
    assert.equal(tasksBody.data.tasks[0].projectId.length, 128);
    assert.equal(tasksBody.data.tasks[0].dueDate.length, 40);
    assert.equal(tasksBody.data.tasks[0].kind.length, 32);
    assert.ok(Buffer.byteLength(taskText) <= 16 * 1024, `task page exceeded watch budget: ${Buffer.byteLength(taskText)} bytes`);
    const projectsResponse = await worker.fetch(new Request("https://relay.test/v1/projects", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    const projectText = await projectsResponse.text();
    const projectsBody = JSON.parse(projectText) as { data: { projects: Array<{ id: string; name: string; color: string; kind: string }>; cursor: string } };
    assert.equal(projectsBody.data.projects.length, 30);
    assert.equal(projectsBody.data.projects[0].id.length, 128);
    assert.equal(projectsBody.data.projects[0].name.length, 80);
    assert.equal(projectsBody.data.projects[0].color.length, 16);
    assert.equal(projectsBody.data.projects[0].kind.length, 32);
    assert.ok(projectsBody.data.cursor.length <= 128);
    assert.ok(Buffer.byteLength(projectText) <= 16 * 1024, `project page exceeded watch budget: ${Buffer.byteLength(projectText)} bytes`);
    const nextProjectsResponse = await worker.fetch(new Request(`https://relay.test/v1/projects?cursor=${encodeURIComponent(projectsBody.data.cursor)}`, { headers: { authorization: `Bearer ${relayToken}` } }), env);
    const nextProjects = await nextProjectsResponse.json() as { data: { projects: unknown[]; cursor?: string } };
    assert.equal(nextProjects.data.projects.length, 20);
    assert.equal(nextProjects.data.cursor, undefined);
  } finally {
    context.mock.restoreAll();
    globalThis.fetch = originalFetch;
  }
});

test("task cursor remains stable when an earlier task disappears", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  let upstream = Array.from({ length: 21 }, (_, index) => ({ id: `task-${index.toString().padStart(2, "0")}`, projectId: "project-1", title: `Task ${index}` }));
  context.mock.method(globalThis, "fetch", async () => Response.json({ tasks: upstream }));
  try {
    const headers = { authorization: `Bearer ${relayToken}` };
    const first = await worker.fetch(new Request("https://relay.test/v1/tasks?view=project&projectId=project-1", { headers }), env);
    const firstPage = await first.json() as { data: { tasks: Array<{ id: string }>; cursor: string } };
    assert.equal(firstPage.data.tasks.length, 20);
    upstream = upstream.filter((task) => task.id !== "task-00");
    const second = await worker.fetch(new Request(`https://relay.test/v1/tasks?view=project&projectId=project-1&cursor=${firstPage.data.cursor}`, { headers }), env);
    const secondPage = await second.json() as { data: { tasks: Array<{ id: string }> } };
    assert.deepEqual(secondPage.data.tasks.map((task) => task.id), ["task-20"]);
  } finally {
    context.mock.restoreAll();
  }
});

test("a removed task-page anchor returns a distinct stale-cursor response", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  let upstream = Array.from({ length: 21 }, (_, index) => ({ id: `task-${index.toString().padStart(2, "0")}`, projectId: "project-1", title: `Task ${index}` }));
  context.mock.method(globalThis, "fetch", async () => Response.json({ tasks: upstream }));
  try {
    const headers = { authorization: `Bearer ${relayToken}` };
    const first = await worker.fetch(new Request("https://relay.test/v1/tasks?view=project&projectId=project-1", { headers }), env);
    const firstPage = await first.json() as { data: { cursor: string } };
    upstream = upstream.filter((task) => task.id !== firstPage.data.cursor);
    const second = await worker.fetch(new Request(`https://relay.test/v1/tasks?view=project&projectId=project-1&cursor=${firstPage.data.cursor}`, { headers }), env);
    assert.equal(second.status, 409);
    assert.equal((await second.json() as { error: { code: string } }).error.code, "cursor_stale");
  } finally {
    context.mock.restoreAll();
  }
});

test("task pagination preserves upstream order across mixed identifier characters", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const ids = ["-", "_", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G", "a", "b"];
  context.mock.method(globalThis, "fetch", async () => Response.json({
    tasks: ids.map((id) => ({ id, projectId: "project-1", title: `Task ${id}` })),
  }));
  try {
    const headers = { authorization: `Bearer ${relayToken}` };
    const first = await worker.fetch(new Request("https://relay.test/v1/tasks?view=project&projectId=project-1", { headers }), env);
    const firstPage = await first.json() as { data: { tasks: Array<{ id: string }>; cursor: string } };
    const second = await worker.fetch(new Request(`https://relay.test/v1/tasks?view=project&projectId=project-1&cursor=${encodeURIComponent(firstPage.data.cursor)}`, { headers }), env);
    const secondPage = await second.json() as { data: { tasks: Array<{ id: string }> } };
    assert.deepEqual(
      [...firstPage.data.tasks, ...secondPage.data.tasks].map((task) => task.id),
      ids,
    );
  } finally {
    context.mock.restoreAll();
  }
});

test("overdue tasks use the same documented POST filter shape", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const calls: Request[] = [];
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init);
    calls.push(request);
    return Response.json({ tasks: [] });
  });
  try {
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks?view=overdue&utcOffsetMinutes=60", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    assert.equal(response.status, 200);
    assert.deepEqual([calls[0].method, new URL(calls[0].url).pathname], ["POST", "/open/v1/task/filter"]);
    const filter = JSON.parse(await calls[0].text()) as { status: number[] };
    assert.deepEqual(filter, { status: [0] });
  } finally {
    context.mock.restoreAll();
  }
});

test("Today requires a valid watch UTC offset and fetches every open task before classification", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const calls: Request[] = [];
  const originalFetch = globalThis.fetch;
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init);
    calls.push(request);
    return Response.json({ tasks: [] });
  });
  try {
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks?view=today&utcOffsetMinutes=840", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    assert.equal(response.status, 200);
    const filter = JSON.parse(await calls[0].text()) as { status: number[] };
    assert.deepEqual(filter, { status: [0] });

    const missing = await worker.fetch(new Request("https://relay.test/v1/tasks?view=today", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    assert.equal(missing.status, 400);
    const invalid = await worker.fetch(new Request("https://relay.test/v1/tasks?view=today&utcOffsetMinutes=900", { headers: { authorization: `Bearer ${relayToken}` } }), env);
    assert.equal(invalid.status, 400);
  } finally {
    context.mock.restoreAll();
    globalThis.fetch = originalFetch;
  }
});

test("timezone-aware Today classification survives a DST transition", () => {
  const londonNoonOnSpringChange = Date.parse("2026-03-29T11:00:00Z");
  const tasks = [
    { id: "before-change", dueDate: "2026-03-29T00:30:00Z", timeZone: "Europe/London" },
    { id: "after-midnight", dueDate: "2026-03-29T23:30:00Z", timeZone: "Europe/London" },
  ];
  assert.deepEqual(tasksForView(tasks, "today", 60, londonNoonOnSpringChange).map((task) => task.id), ["before-change"]);
});

test("completion is an idempotent relay operation with a fixed TickTick path", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  const calls: Request[] = [];
  context.mock.method(globalThis, "fetch", async (input: string | URL | Request, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init);
    calls.push(request);
    return Response.json({ id: "task-1" });
  });
  try {
    const headers = { authorization: `Bearer ${relayToken}`, "content-type": "application/json" };
    const payload = { mutationId: "complete-1", projectId: "project-1" };
    const request = () => new Request("https://relay.test/v1/tasks/task-1/complete", { method: "POST", headers, body: JSON.stringify(payload) });
    const response = await worker.fetch(request(), env);
    const expected = await fixture("mutation-ok.json") as { ok: boolean; data: { status: string } };
    assert.deepEqual(await response.json(), { ok: expected.ok, data: { mutationId: payload.mutationId, status: expected.data.status } });
    const retried = await worker.fetch(request(), env);
    assert.equal(retried.status, 200);
    assert.deepEqual(calls.map((call) => [call.method, new URL(call.url).pathname]), [
      ["POST", "/open/v1/project/project-1/task/task-1/complete"],
    ]);
    assert.equal(await calls[0].text(), "");
  } finally {
    context.mock.restoreAll();
  }
});

test("network-ambiguous mutations are recorded as unknown and never replayed", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  let attempts = 0;
  context.mock.method(globalThis, "fetch", async () => {
    attempts += 1;
    throw new TypeError("network lost after write");
  });
  try {
    const headers = { authorization: `Bearer ${relayToken}`, "content-type": "application/json" };
    const request = () => new Request("https://relay.test/v1/tasks/task-1/complete", { method: "POST", headers, body: JSON.stringify({ mutationId: "unknown-1", projectId: "project-1" }) });
    const first = await worker.fetch(request(), env);
    const expected = { ok: false, error: { code: "mutation_outcome_unknown", message: "Mutation outcome is unknown", retryable: false } };
    assert.equal(first.status, 409);
    assert.deepEqual(await first.json(), expected);
    const repeated = await worker.fetch(request(), env);
    assert.equal(repeated.status, 409);
    assert.deepEqual(await repeated.json(), expected);
    assert.equal(attempts, 1);
  } finally {
    context.mock.restoreAll();
  }
});

test("a pre-existing pending mutation is treated as unknown and never replayed", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  db.mutations.set("session-1:interrupted-1", "pending");
  let attempts = 0;
  context.mock.method(globalThis, "fetch", async () => {
    attempts += 1;
    return Response.json({ id: "task-1" });
  });
  try {
    const request = new Request("https://relay.test/v1/tasks/task-1/complete", {
      method: "POST",
      headers: { authorization: `Bearer ${relayToken}`, "content-type": "application/json" },
      body: JSON.stringify({ mutationId: "interrupted-1", projectId: "project-1" }),
    });
    const response = await worker.fetch(request, env);
    assert.equal(response.status, 409);
    assert.equal((await response.json() as { error: { code: string } }).error.code, "mutation_outcome_unknown");
    assert.equal(attempts, 0);
  } finally {
    context.mock.restoreAll();
  }
});

test("an explicit upstream failure clears pending mutation state for a retry", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  let attempts = 0;
  context.mock.method(globalThis, "fetch", async () => {
    attempts += 1;
    return attempts === 1 ? new Response(null, { status: 503 }) : Response.json({ id: "task-1" });
  });
  try {
    const headers = { authorization: `Bearer ${relayToken}`, "content-type": "application/json" };
    const payload = { mutationId: "retry-1", projectId: "project-1" };
    const first = await worker.fetch(new Request("https://relay.test/v1/tasks/task-1/complete", { method: "POST", headers, body: JSON.stringify(payload) }), env);
    assert.equal(first.status, 502);
    assert.deepEqual(await first.json(), { ok: false, error: { code: "temporarily_unavailable", message: "Try again later", retryable: true } });
    const repeated = await worker.fetch(new Request("https://relay.test/v1/tasks/task-1/complete", { method: "POST", headers, body: JSON.stringify(payload) }), env);
    assert.equal(repeated.status, 200);
    assert.equal(attempts, 2);
  } finally {
    context.mock.restoreAll();
  }
});

test("expired TickTick authorization is non-retryable and clears pending mutation state", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  context.mock.method(globalThis, "fetch", async () => new Response(null, { status: 401 }));
  try {
    const headers = { authorization: `Bearer ${relayToken}`, "content-type": "application/json" };
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks/task-1/complete", { method: "POST", headers, body: JSON.stringify({ mutationId: "expired-1", projectId: "project-1" }) }), env);
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { ok: false, error: { code: "authorization_expired", message: "TickTick authorization expired", retryable: false } });
    assert.equal(db.mutations.has("session-1:expired-1"), false);
    assert.equal(db.session?.revoked, true);
  } finally {
    context.mock.restoreAll();
  }
});

test("permanent TickTick mutation rejection is never labeled retryable", async (context) => {
  const db = new FakeD1();
  const { env, relayToken } = await authenticatedEnv(db);
  context.mock.method(globalThis, "fetch", async () => new Response(null, { status: 400 }));
  try {
    const headers = { authorization: `Bearer ${relayToken}`, "content-type": "application/json" };
    const response = await worker.fetch(new Request("https://relay.test/v1/tasks/task-1/complete", { method: "POST", headers, body: JSON.stringify({ mutationId: "rejected-1", projectId: "project-1" }) }), env);
    assert.equal(response.status, 422);
    assert.deepEqual(await response.json(), { ok: false, error: { code: "request_rejected", message: "TickTick rejected the request", retryable: false } });
    assert.equal(db.mutations.has("session-1:rejected-1"), false);
  } finally {
    context.mock.restoreAll();
  }
});

test("the relay has no catch-all upstream proxy", async () => {
  const response = await worker.fetch(new Request("https://relay.test/v1/anything?url=https://example.test"), baseEnv(new FakeD1()));
  assert.deepEqual(await response.json(), { ok: false, error: { code: "not_found", message: "Route not found", retryable: false } });
});

test("scheduled cleanup enforces pairing, revoked-session, and mutation retention", async () => {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  const db = {
    prepare(sql: string) {
      return {
        bind: (...values: unknown[]) => ({
          run: async () => {
            calls.push({ sql, values });
            return { meta: { changes: 0 } };
          },
        }),
      };
    },
  };
  await worker.scheduled({} as ScheduledController, baseEnv(db as unknown as FakeD1));
  assert.deepEqual(calls.map((call) => call.sql), [
    "DELETE FROM mutations WHERE session_id IN (SELECT id FROM sessions WHERE revoked_at IS NOT NULL AND revoked_at < ?)",
    "DELETE FROM sessions WHERE revoked_at IS NOT NULL AND revoked_at < ?",
    "DELETE FROM pairings WHERE expires_at < ? AND NOT EXISTS (SELECT 1 FROM sessions WHERE sessions.pairing_id = pairings.id)",
  ]);
  assert.equal((calls[2].values[0] as number) - (calls[1].values[0] as number), 0);
});
