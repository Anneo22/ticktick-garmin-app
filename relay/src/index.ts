import { decrypt, encrypt, randomSecret, sha256 } from "./crypto";
import { bearer, body, error, json } from "./http";

export interface Env {
  DB: D1Database;
  TICKTICK_CLIENT_ID: string;
  TICKTICK_CLIENT_SECRET: string;
  TICKTICK_REDIRECT_URI: string;
  TOKEN_ENCRYPTION_KEY: string;
  PAIRING_VERIFICATION_URL: string;
  RATE_LIMITER: { limit(input: { key: string }): Promise<{ success: boolean }> };
}

type Pairing = { id: string; oauth_completed_at: number | null; expires_at: number };
type Session = { id: string; token_ciphertext: string; token_iv: string };
type PairingSession = { bearer_token_hash: string; revoked_at: number | null };
type Task = Record<string, unknown>;
const PAIRING_TTL_SECONDS = 600;
const POLL_AFTER_SECONDS = 3;
const USER_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const TICKTICK_API = "https://api.ticktick.com/open/v1";
const MAX_TASKS = 20;
const MAX_PROJECTS = 30;

function now(): number { return Math.floor(Date.now() / 1000); }
function isoNow(): string { return new Date().toISOString(); }
function isDeviceSecret(value: unknown): value is string { return typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value); }
function isMutationId(value: unknown): value is string { return typeof value === "string" && /^[A-Za-z0-9_-]{1,96}$/.test(value); }
function isIdentifier(value: string | undefined): value is string { return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value); }
function userCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes, (byte) => USER_CODE_ALPHABET[byte % USER_CODE_ALPHABET.length]).join("");
}

async function rateLimit(env: Env, key: string): Promise<Response | null> {
  return (await env.RATE_LIMITER.limit({ key })).success ? null : error("rate_limited", 429);
}

function authorizationUrl(env: Env, state: string): string {
  const url = new URL("https://ticktick.com/oauth/authorize");
  url.search = new URLSearchParams({
    client_id: env.TICKTICK_CLIENT_ID,
    redirect_uri: env.TICKTICK_REDIRECT_URI,
    response_type: "code",
    scope: "tasks:read tasks:write",
    state,
  }).toString();
  return url.toString();
}

// Garmin Bridge public surface (concept seed d39802f1). The route mark below is the launcher
// geometry element-for-element; scripts/check-icon.mjs fails if the two ever drift apart.
// The pages are product-identified only: no maintainer name, address, or personal host.
const ROUTE_MARK = `<svg viewBox="0 0 100 100" width="64" height="64" role="img" aria-label="Garmin Bridge route mark"><rect x="0" y="0" width="100" height="100" rx="22" fill="#1A1A1A"/><line x1="18" y1="78" x2="82" y2="78" stroke="#5A5CF5" stroke-width="5" stroke-linecap="round"/><line x1="50" y1="26" x2="82" y2="78" stroke="#D4D4D4" stroke-width="9" stroke-linecap="round"/><line x1="18" y1="78" x2="50" y2="26" stroke="#FD4E5A" stroke-width="9" stroke-linecap="round"/><circle cx="18" cy="78" r="8" fill="#1A1A1A"/><circle cx="18" cy="78" r="8" fill="none" stroke="#D4D4D4" stroke-width="5"/><circle cx="82" cy="78" r="8" fill="#1A1A1A"/><circle cx="82" cy="78" r="8" fill="none" stroke="#D4D4D4" stroke-width="5"/><circle cx="50" cy="26" r="11" fill="#1A1A1A"/><circle cx="50" cy="26" r="11" fill="none" stroke="#FD4E5A" stroke-width="6"/><circle cx="50" cy="26" r="4" fill="#FD4E5A"/></svg>`;

const STYLES = `:root{--surface:#1A1A1A;--text:#D4D4D4;--coral:#FD4E5A;--klein:#5A5CF5;--muted:#8A8A8A;--line:#333333}
*{box-sizing:border-box}
body{margin:0;background:var(--surface);color:var(--text);font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:32rem;margin:0 auto;padding:clamp(1.5rem,6vw,3.5rem) 1.25rem}
header{display:flex;flex-direction:column;gap:.6rem;align-items:flex-start}
.eyebrow{margin:0;color:var(--klein);font-size:.78rem;letter-spacing:.16em;text-transform:uppercase}
h1{margin:0;font-size:clamp(1.35rem,5vw,2rem);line-height:1.15;font-weight:650}
ol{margin:2rem 0 2.25rem;padding:0;list-style:none;counter-reset:step}
li{counter-increment:step;position:relative;margin-left:.85rem;padding:0 0 1.4rem 2.6rem;border-left:2px solid var(--line)}
li:last-child{border-left-color:transparent;padding-bottom:0}
li::before{content:counter(step);position:absolute;left:-.95rem;top:-.15rem;width:1.8rem;height:1.8rem;border-radius:50%;border:2px solid var(--line);background:var(--surface);color:var(--muted);display:grid;place-items:center;font-size:.85rem}
li:first-child::before{border-color:var(--coral);color:var(--coral)}
label{display:block;margin-bottom:.45rem;color:var(--muted);font-size:.85rem}
input{width:100%;padding:.85rem;font:inherit;font-size:1.2rem;letter-spacing:.3em;text-transform:uppercase;color:var(--text);background:#141414;border:1px solid var(--line);border-radius:.6rem}
input:focus-visible{outline:2px solid var(--klein);outline-offset:2px}
button{width:100%;margin-top:1.1rem;padding:.95rem;font:inherit;font-weight:700;color:var(--surface);background:var(--coral);border:0;border-radius:.6rem;cursor:pointer}
button:hover{filter:brightness(1.08)}
button:focus-visible{outline:2px solid var(--klein);outline-offset:2px}
.lede{margin:2rem 0 0;font-size:1.1rem}
.lede strong{color:var(--coral);font-weight:650}
footer p{margin:2.25rem 0 0;color:var(--muted);font-size:.85rem}
@media (max-width:24rem){main{padding-inline:1rem}li{padding-left:2.2rem}}`;

function nonce(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function htmlPage(title: string, main: string, policy: string): Response {
  const styleNonce = nonce();
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark">
<title>${title}</title><style nonce="${styleNonce}">${STYLES}</style></head>
<body><main>${main}</main></body></html>`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": `default-src 'none'; style-src 'nonce-${styleNonce}'; img-src 'none'; script-src 'none'; object-src 'none'; ${policy}base-uri 'none'; frame-ancestors 'none'`,
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}

function pairingPage(request: Request): Response {
  const code = new URL(request.url).searchParams.get("code")?.toUpperCase() ?? null;
  const safeCode = code !== null && /^[A-Z2-9]{6}$/.test(code) ? code : "";
  return htmlPage("Pair TickTick for Garmin", `<header>${ROUTE_MARK}<p class="eyebrow">Garmin Bridge</p><h1>Pair TickTick for Garmin</h1></header>
<ol><li>Enter the six-character code shown on your watch.</li><li>Sign in to TickTick and approve access to your tasks.</li><li>Return to your watch and press START to load your tasks.</li></ol>
<form action="/v1/pair/authorize" method="get"><label for="code">Pairing code</label><input id="code" name="code" minlength="6" maxlength="6" pattern="[A-Za-z2-9]{6}" inputmode="latin" autocapitalize="characters" autocomplete="one-time-code" spellcheck="false" value="${safeCode}" required><button type="submit">Continue to TickTick</button></form>
<footer><p>This page only exchanges a pairing code. Your TickTick password is entered on TickTick and never reaches this service.</p></footer>`,
    "form-action 'self' https://ticktick.com; ");
}

function pairingCompletePage(): Response {
  return htmlPage("Watch paired", `<header>${ROUTE_MARK}<p class="eyebrow">Garmin Bridge</p><h1>Watch paired</h1></header>
<p class="lede"><strong>Return to your watch</strong> and tap anywhere or press START to load your tasks.</p>
<footer><p>You can close this page. Disconnect at any time from the watch Account view.</p></footer>`, "");
}

async function tickTickToken(env: Env, code: string): Promise<string | null> {
  const credentials = btoa(`${env.TICKTICK_CLIENT_ID}:${env.TICKTICK_CLIENT_SECRET}`);
  const response = await fetch("https://ticktick.com/oauth/token", {
    method: "POST",
    headers: { authorization: `Basic ${credentials}`, "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ code, grant_type: "authorization_code", redirect_uri: env.TICKTICK_REDIRECT_URI, scope: "tasks:read tasks:write" }),
  });
  if (!response.ok) return null;
  const payload: unknown = await response.json();
  return typeof payload === "object" && payload !== null && "access_token" in payload && typeof payload.access_token === "string" ? payload.access_token : null;
}

async function startPairing(request: Request, env: Env): Promise<Response> {
  const clientAddress = request.headers.get("cf-connecting-ip") ?? "unknown";
  const limited = await rateLimit(env, `pair:start:${await sha256(clientAddress)}`);
  if (limited) return limited;
  const input = await body(request);
  if (input !== null && Object.keys(input).length > 0) return error("invalid_request");
  const createdAt = now();
  const deviceSecret = randomSecret();
  const pairing = { id: randomSecret(16), code: userCode(), secretHash: await sha256(deviceSecret) };
  await env.DB.prepare("INSERT INTO pairings (id, pairing_code, device_secret_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)")
    .bind(pairing.id, pairing.code, pairing.secretHash, createdAt + PAIRING_TTL_SECONDS, createdAt).run();
  return json({ deviceSecret, userCode: pairing.code, verificationUrl: env.PAIRING_VERIFICATION_URL, expiresIn: PAIRING_TTL_SECONDS, pollAfter: POLL_AFTER_SECONDS });
}

async function authorizePairing(request: Request, env: Env): Promise<Response> {
  const code = new URL(request.url).searchParams.get("code")?.toUpperCase();
  if (!code || !/^[A-Z2-9]{6}$/.test(code)) return error("invalid_pairing_code");
  const clientAddress = request.headers.get("cf-connecting-ip") ?? "unknown";
  const limited = await rateLimit(env, `pair:authorize:${await sha256(clientAddress)}`);
  if (limited) return limited;
  const pairing = await env.DB.prepare("SELECT id FROM pairings WHERE pairing_code = ? AND expires_at > ? AND oauth_completed_at IS NULL")
    .bind(code, now()).first<{ id: string }>();
  if (!pairing) return error("pairing_expired", 410);
  const state = randomSecret();
  const changed = await env.DB.prepare("UPDATE pairings SET oauth_state_hash = ?, oauth_state_used_at = NULL WHERE id = ? AND oauth_completed_at IS NULL AND expires_at > ?")
    .bind(await sha256(state), pairing.id, now()).run();
  if (!changed.meta.changes) return error("pairing_expired", 410);
  return Response.redirect(authorizationUrl(env, state), 302);
}

async function oauthCallback(request: Request, env: Env): Promise<Response> {
  const clientAddress = request.headers.get("cf-connecting-ip") ?? "unknown";
  const limited = await rateLimit(env, `pair:callback:${await sha256(clientAddress)}`);
  if (limited) return limited;
  const query = new URL(request.url).searchParams;
  const code = query.get("code");
  const state = query.get("state");
  if (!code || !state) return error("invalid_callback");
  const stateHash = await sha256(state);
  const pairing = await env.DB.prepare("SELECT id, expires_at FROM pairings WHERE oauth_state_hash = ? AND oauth_state_used_at IS NULL")
    .bind(stateHash).first<{ id: string; expires_at: number }>();
  if (!pairing || pairing.expires_at <= now()) return error("invalid_state");
  const consumed = await env.DB.prepare("UPDATE pairings SET oauth_state_used_at = ? WHERE id = ? AND oauth_state_hash = ? AND oauth_state_used_at IS NULL")
    .bind(now(), pairing.id, stateHash).run();
  if (!consumed.meta.changes) return error("invalid_state");
  const token = await tickTickToken(env, code);
  if (!token) return error("token_exchange_failed", 502);
  const sealed = await encrypt(token, env.TOKEN_ENCRYPTION_KEY);
  await env.DB.prepare("INSERT INTO sessions (id, pairing_id, bearer_token_hash, token_ciphertext, token_iv, created_at, revoked_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .bind(randomSecret(16), pairing.id, await sha256(`pending:${pairing.id}`), sealed.ciphertext, sealed.iv, now(), now()).run();
  await env.DB.prepare("UPDATE pairings SET oauth_completed_at = ? WHERE id = ?").bind(now(), pairing.id).run();
  return pairingCompletePage();
}

async function pairingStatus(request: Request, env: Env): Promise<Response> {
  const clientAddress = request.headers.get("cf-connecting-ip") ?? "unknown";
  const limited = await rateLimit(env, `pair:status:${await sha256(clientAddress)}`);
  if (limited) return limited;
  const input = await body(request);
  if (!isDeviceSecret(input?.deviceSecret)) return error("invalid_device_secret");
  const secretHash = await sha256(input.deviceSecret);
  const pairing = await env.DB.prepare("SELECT id, oauth_completed_at, expires_at FROM pairings WHERE device_secret_hash = ?")
    .bind(secretHash).first<Pairing>();
  if (!pairing) return error("invalid_pairing", 403);
  if (pairing.expires_at <= now() && !pairing.oauth_completed_at) return error("pairing_expired", 410);
  if (!pairing.oauth_completed_at) return json({ status: "pending", pollAfter: POLL_AFTER_SECONDS });
  const pairingSession = await env.DB.prepare("SELECT bearer_token_hash, revoked_at FROM sessions WHERE pairing_id = ?")
    .bind(pairing.id).first<PairingSession>();
  if (!pairingSession) return error("pairing_already_completed", 409);
  if (pairingSession.bearer_token_hash === secretHash) {
    return pairingSession.revoked_at === null ? json({ status: "paired", relayToken: input.deviceSecret }) : error("pairing_already_completed", 409);
  }
  const issued = await env.DB.prepare("UPDATE sessions SET bearer_token_hash = ?, revoked_at = NULL WHERE pairing_id = ? AND revoked_at IS NOT NULL")
    .bind(secretHash, pairing.id).run();
  return issued.meta.changes ? json({ status: "paired", relayToken: input.deviceSecret }) : error("pairing_already_completed", 409);
}

async function session(request: Request, env: Env): Promise<{ session: Session } | Response> {
  const clientAddress = request.headers.get("cf-connecting-ip") ?? "unknown";
  const limited = await rateLimit(env, `api:${await sha256(clientAddress)}`);
  if (limited) return limited;
  const relayToken = bearer(request);
  if (!relayToken || !isDeviceSecret(relayToken)) return error("unauthorized", 401);
  const found = await env.DB.prepare("SELECT id, token_ciphertext, token_iv FROM sessions WHERE bearer_token_hash = ? AND revoked_at IS NULL")
    .bind(await sha256(relayToken)).first<Session>();
  return found ? { session: found } : error("unauthorized", 401);
}

async function tickTickRequest(env: Env, relaySession: Session, path: string, method: string, payload?: unknown): Promise<Response> {
  const accessToken = await decrypt({ ciphertext: relaySession.token_ciphertext, iv: relaySession.token_iv }, env.TOKEN_ENCRYPTION_KEY);
  return fetch(`${TICKTICK_API}${path}`, {
    method,
    headers: { authorization: `Bearer ${accessToken}`, ...(payload === undefined ? {} : { "content-type": "application/json" }) },
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
  });
}

async function expireSession(env: Env, relaySession: Session): Promise<void> {
  await env.DB.prepare("UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL").bind(now(), relaySession.id).run();
}

function taskList(payload: unknown): Task[] | null {
  if (Array.isArray(payload)) return payload.filter((item): item is Task => typeof item === "object" && item !== null);
  if (typeof payload === "object" && payload !== null && "tasks" in payload && Array.isArray(payload.tasks)) {
    return payload.tasks.filter((item): item is Task => typeof item === "object" && item !== null);
  }
  return null;
}

function normalizeTask(task: Task): Record<string, unknown> {
  const normalized: Record<string, unknown> = {};
  for (const key of ["id", "projectId", "dueDate", "isAllDay", "isOverdue", "priority", "status", "kind"] as const) {
    const value = task[key];
    if (typeof value === "string") {
      const limit = key === "dueDate" ? 40 : key === "kind" ? 32 : 128;
      normalized[key] = value.slice(0, limit);
    }
    else if (typeof value === "number" || typeof value === "boolean") normalized[key] = value;
  }
  const title = typeof task.title === "string" ? task.title : typeof task.content === "string" ? task.content : "";
  return { ...normalized, title: title.slice(0, 120) };
}

function normalizeProject(project: Record<string, unknown>): Record<string, unknown> | null {
  if (typeof project.id !== "string" || typeof project.name !== "string") return null;
  const normalized: Record<string, unknown> = { id: project.id.slice(0, 128), name: project.name.slice(0, 80) };
  for (const key of ["color", "kind", "permission", "viewMode"] as const) {
    const value = project[key];
    if (typeof value === "string") normalized[key] = value.slice(0, key === "color" ? 16 : 32);
  }
  if (typeof project.closed === "boolean") normalized.closed = project.closed;
  return normalized;
}

async function projects(request: Request, env: Env): Promise<Response> {
  const authenticated = await session(request, env);
  if (authenticated instanceof Response) return authenticated;
  const response = await tickTickRequest(env, authenticated.session, "/project", "GET");
  if (response.status === 401 || response.status === 403) {
    await expireSession(env, authenticated.session);
    return error("authorization_expired", 401);
  }
  if (!response.ok) return error("temporarily_unavailable", 502);
  const payload = await response.json().catch(() => null);
  if (!Array.isArray(payload)) return error("temporarily_unavailable", 502);
  const normalized = payload
    .map((project) => typeof project === "object" && project !== null ? normalizeProject(project as Record<string, unknown>) : null)
    .filter((project): project is Record<string, unknown> & { id: string } => project !== null && project.closed !== true && typeof project.id === "string");
  const cursor = new URL(request.url).searchParams.get("cursor");
  if (cursor !== null && !isIdentifier(cursor)) return error("invalid_request");
  const cursorIndex = cursor === null ? -1 : normalized.findIndex((project) => project.id === cursor);
  if (cursor !== null && cursorIndex < 0) return error("cursor_stale", 409);
  const remaining = normalized.slice(cursorIndex + 1);
  const projectPage = remaining.slice(0, MAX_PROJECTS);
  return json({ projects: projectPage, ...(remaining.length > MAX_PROJECTS ? { cursor: projectPage[projectPage.length - 1].id } : {}) });
}

function page(tasks: Task[], cursor: string | null): { tasks: Record<string, unknown>[]; cursor?: string; syncedAt: string } | null {
  const sorted = tasks
    .map(normalizeTask)
    .filter((task): task is Record<string, unknown> & { id: string; projectId: string } =>
      typeof task.id === "string" && isIdentifier(task.id) &&
      typeof task.projectId === "string" && isIdentifier(task.projectId));
  const cursorIndex = cursor === null ? -1 : sorted.findIndex((task) => task.id === cursor);
  if (cursor !== null && cursorIndex < 0) return null;
  const remaining = sorted.slice(cursorIndex + 1);
  const taskPage = remaining.slice(0, MAX_TASKS);
  return {
    tasks: taskPage,
    ...(remaining.length > MAX_TASKS ? { cursor: taskPage[taskPage.length - 1].id } : {}),
    syncedAt: isoNow(),
  };
}

function localDateKey(utcOffsetMinutes: number, timestamp = Date.now()): string {
  const offsetMs = utcOffsetMinutes * 60_000;
  const local = new Date(timestamp + offsetMs);
  return `${local.getUTCFullYear().toString().padStart(4, "0")}-${(local.getUTCMonth() + 1).toString().padStart(2, "0")}-${local.getUTCDate().toString().padStart(2, "0")}`;
}

function dateKey(task: Task, utcOffsetMinutes: number): string | null {
  const value = typeof task.dueDate === "string" ? task.dueDate : typeof task.startDate === "string" ? task.startDate : null;
  if (value === null) return null;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return null;
  if (typeof task.timeZone === "string") {
    try {
      const parts = new Intl.DateTimeFormat("en", { timeZone: task.timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(timestamp);
      const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
      if (values.year && values.month && values.day) return `${values.year}-${values.month}-${values.day}`;
    } catch {
      // Fall back to the watch's current offset if TickTick supplies an invalid timezone.
    }
  }
  return localDateKey(utcOffsetMinutes, timestamp);
}

export function tasksForView(tasks: Task[], view: "today" | "overdue", utcOffsetMinutes: number, timestamp = Date.now()): Task[] {
  const today = localDateKey(utcOffsetMinutes, timestamp);
  const classified = tasks.map((task) => ({ task, effectiveDate: dateKey(task, utcOffsetMinutes) }));
  const overdue = classified
    .filter(({ effectiveDate }) => effectiveDate !== null && effectiveDate < today)
    .map(({ task }) => ({ ...task, isOverdue: true }));
  if (view === "overdue") return overdue;
  const dueToday = classified
    .filter(({ effectiveDate }) => effectiveDate === today)
    .map(({ task }) => task);
  // Today stays the landing point. Overdue tasks follow the Today rows in the cyclic watch list,
  // so one upward/backward move from the first Today task reveals the most recent overdue task.
  return dueToday.concat(overdue);
}

// TickTick's documented Open API exposes the user's lists but no named Inbox endpoint.
// The all-open-task response still contains Inbox tasks. A task belongs to Inbox when its
// projectId is absent from the complete project response. Official Task objects always carry a
// projectId, including Inbox's internal list ID. Keep this derivation isolated so a
// future official Inbox endpoint can replace it without changing the watch contract.
export function tasksForInbox(tasks: Task[], projectPayload: unknown): Task[] | null {
  if (!Array.isArray(projectPayload)) return null;
  const projectIds = new Set<string>();
  for (const project of projectPayload) {
    if (typeof project !== "object" || project === null || !("id" in project) || typeof project.id !== "string") return null;
    projectIds.add(project.id);
  }
  return tasks.filter((task) => typeof task.projectId === "string" && !projectIds.has(task.projectId));
}

async function tasks(request: Request, env: Env): Promise<Response> {
  const query = new URL(request.url).searchParams;
  const view = query.get("view");
  let path: string;
  let method: "GET" | "POST";
  let requestPayload: Record<string, unknown> | undefined;
  let dateView: "today" | "overdue" | null = null;
  let utcOffsetMinutes = 0;
  if (view === "today" || view === "overdue" || view === "inbox") {
    if (view === "inbox") {
      path = "/task/filter";
      method = "POST";
      requestPayload = { status: [0] };
    } else {
      const offsetInput = query.get("utcOffsetMinutes");
      utcOffsetMinutes = offsetInput !== null && /^-?\d{1,4}$/.test(offsetInput) ? Number(offsetInput) : Number.NaN;
      if (!Number.isInteger(utcOffsetMinutes) || utcOffsetMinutes < -840 || utcOffsetMinutes > 840) return error("invalid_request");
      path = "/task/filter";
      method = "POST";
      requestPayload = { status: [0] };
      dateView = view;
    }
  } else if (view === "project" && isIdentifier(query.get("projectId") ?? undefined)) {
    path = `/project/${encodeURIComponent(query.get("projectId")!)}/data`;
    method = "GET";
  }
  else return error("invalid_request");
  const cursor = query.get("cursor");
  if (cursor !== null && !isIdentifier(cursor)) return error("invalid_request");
  const authenticated = await session(request, env);
  if (authenticated instanceof Response) return authenticated;
  if (view === "inbox") {
    const [taskResponse, projectResponse] = await Promise.all([
      tickTickRequest(env, authenticated.session, path, method, requestPayload),
      tickTickRequest(env, authenticated.session, "/project", "GET"),
    ]);
    if ([taskResponse.status, projectResponse.status].some((status) => status === 401 || status === 403)) {
      await expireSession(env, authenticated.session);
      return error("authorization_expired", 401);
    }
    if (!taskResponse.ok || !projectResponse.ok) return error("temporarily_unavailable", 502);
    const taskPayload = await taskResponse.json().catch(() => null);
    const projectPayload = await projectResponse.json().catch(() => null);
    const receivedTasks = taskList(taskPayload);
    const inboxTasks = receivedTasks === null ? null : tasksForInbox(receivedTasks, projectPayload);
    if (inboxTasks === null) return error("temporarily_unavailable", 502);
    const resultPage = page(inboxTasks, cursor);
    return resultPage ? json(resultPage) : error("cursor_stale", 409);
  }
  const response = await tickTickRequest(env, authenticated.session, path, method, requestPayload);
  if (response.status === 401 || response.status === 403) {
    await expireSession(env, authenticated.session);
    return error("authorization_expired", 401);
  }
  if (!response.ok) return error("temporarily_unavailable", 502);
  const responsePayload = await response.json().catch(() => null);
  const receivedTasks = taskList(responsePayload);
  if (receivedTasks === null) return error("temporarily_unavailable", 502);
  const resultPage = page(dateView === null ? receivedTasks : tasksForView(receivedTasks, dateView, utcOffsetMinutes), cursor);
  return resultPage ? json(resultPage) : error("cursor_stale", 409);
}

async function mutate(request: Request, env: Env, path: string, mutationId: string, upstreamPayload?: unknown, method = "POST"): Promise<Response> {
  if (!isMutationId(mutationId)) return error("invalid_request");
  const authenticated = await session(request, env);
  if (authenticated instanceof Response) return authenticated;
  const recorded = await env.DB.prepare("INSERT OR IGNORE INTO mutations (session_id, mutation_id, status, created_at) VALUES (?, ?, ?, ?)")
    .bind(authenticated.session.id, mutationId, "pending", now()).run();
  if (!recorded.meta.changes) {
    const existing = await env.DB.prepare("SELECT status FROM mutations WHERE session_id = ? AND mutation_id = ?")
      .bind(authenticated.session.id, mutationId).first<{ status: string }>();
    if (existing?.status === "applied") return json({ mutationId, status: "applied" });
    return error("mutation_outcome_unknown", 409);
  }
  let response: Response;
  try {
    response = await tickTickRequest(env, authenticated.session, path, method, upstreamPayload);
  } catch {
    await env.DB.prepare("UPDATE mutations SET status = ? WHERE session_id = ? AND mutation_id = ?").bind("unknown", authenticated.session.id, mutationId).run();
    return error("mutation_outcome_unknown", 409);
  }
  if (!response.ok) {
    await env.DB.prepare("DELETE FROM mutations WHERE session_id = ? AND mutation_id = ? AND status = ?").bind(authenticated.session.id, mutationId, "pending").run();
    if (response.status === 401 || response.status === 403) {
      await expireSession(env, authenticated.session);
      return error("authorization_expired", 401);
    }
    return response.status === 408 || response.status === 429 || response.status >= 500
      ? error("temporarily_unavailable", 502)
      : error("request_rejected", 422);
  }
  await env.DB.prepare("UPDATE mutations SET status = ? WHERE session_id = ? AND mutation_id = ?").bind("applied", authenticated.session.id, mutationId).run();
  return json({ mutationId, status: "applied" });
}

async function unpair(request: Request, env: Env): Promise<Response> {
  const authenticated = await session(request, env);
  if (authenticated instanceof Response) return authenticated;
  await env.DB.prepare("UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL").bind(now(), authenticated.session.id).run();
  return json({ revoked: true });
}

async function cleanup(env: Env): Promise<void> {
  const current = now();
  const revokedCutoff = current;
  await env.DB.prepare("DELETE FROM mutations WHERE session_id IN (SELECT id FROM sessions WHERE revoked_at IS NOT NULL AND revoked_at < ?)").bind(revokedCutoff).run();
  await env.DB.prepare("DELETE FROM sessions WHERE revoked_at IS NOT NULL AND revoked_at < ?").bind(revokedCutoff).run();
  await env.DB.prepare("DELETE FROM pairings WHERE expires_at < ? AND NOT EXISTS (SELECT 1 FROM sessions WHERE sessions.pairing_id = pairings.id)").bind(current).run();
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/pair" && request.method === "GET") return pairingPage(request);
    if (url.pathname === "/v1/pair/start" && request.method === "POST") return startPairing(request, env);
    if (url.pathname === "/v1/pair/status" && request.method === "POST") return pairingStatus(request, env);
    if (url.pathname === "/v1/pair/authorize" && request.method === "GET") return authorizePairing(request, env);
    if (url.pathname === "/v1/oauth/callback" && request.method === "GET") return oauthCallback(request, env);
    if (url.pathname === "/v1/unpair" && request.method === "POST") return unpair(request, env);
    if (url.pathname === "/v1/projects" && request.method === "GET") return projects(request, env);
    if (url.pathname === "/v1/tasks" && request.method === "GET") return tasks(request, env);
    const task = /^\/v1\/tasks\/([A-Za-z0-9_-]+)\/complete$/.exec(url.pathname);
    if (task && request.method === "POST") {
      const input = await body(request);
      if (!input) return error("invalid_request");
      if (typeof input.projectId !== "string" || !isIdentifier(input.projectId) || !isMutationId(input.mutationId)) return error("invalid_request");
      return mutate(request, env, `/project/${encodeURIComponent(input.projectId)}/task/${encodeURIComponent(task[1])}/complete`, input.mutationId);
    }
    return error("not_found", 404);
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await cleanup(env);
  },
};
