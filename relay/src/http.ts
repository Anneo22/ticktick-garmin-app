export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify({ ok: status < 400, ...(status < 400 ? { data } : { error: data }) }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

const ERROR_DETAILS: Record<string, { message: string; retryable: boolean }> = {
  authorization_pending: { message: "Authorization is pending", retryable: true },
  authorization_expired: { message: "TickTick authorization expired", retryable: false },
  cursor_stale: { message: "List changed; refresh from the first page", retryable: true },
  invalid_callback: { message: "Invalid OAuth callback", retryable: false },
  invalid_device_secret: { message: "Invalid device secret", retryable: false },
  invalid_pairing: { message: "Invalid pairing", retryable: false },
  invalid_pairing_code: { message: "Invalid pairing code", retryable: false },
  invalid_request: { message: "Invalid request", retryable: false },
  invalid_state: { message: "Invalid OAuth state", retryable: false },
  mutation_outcome_unknown: { message: "Mutation outcome is unknown", retryable: false },
  not_found: { message: "Route not found", retryable: false },
  pairing_already_completed: { message: "Pairing already completed", retryable: false },
  pairing_expired: { message: "Pairing expired", retryable: false },
  rate_limited: { message: "Too many requests", retryable: true },
  request_rejected: { message: "TickTick rejected the request", retryable: false },
  temporarily_unavailable: { message: "Try again later", retryable: true },
  token_exchange_failed: { message: "Token exchange failed", retryable: true },
  unauthorized: { message: "Unauthorized", retryable: false },
};

export function error(code: keyof typeof ERROR_DETAILS, status = 400): Response {
  return json({ code, ...ERROR_DETAILS[code] }, status);
}

export async function body(request: Request): Promise<Record<string, unknown> | null> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.startsWith("application/json")) return null;
  try {
    const parsed: unknown = await request.json();
    return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

export function bearer(request: Request): string | null {
  const value = request.headers.get("authorization");
  return value?.startsWith("Bearer ") && value.length > 7 ? value.slice(7) : null;
}
