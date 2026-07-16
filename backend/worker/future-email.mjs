const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const MAX_BODY_LENGTH = 50_000;
const MAX_TITLE_LENGTH = 300;
const VERIFICATION_LIFETIME_MS = 10 * 60 * 1000;
const VERIFICATION_COOLDOWN_MS = 60 * 1000;
const VERIFICATION_RETENTION_MS = 24 * 60 * 60 * 1000;
const MAX_VERIFICATION_REQUESTS_PER_HOUR = 5;
const MAX_VERIFICATION_ATTEMPTS = 5;
const MAX_DELIVERY_HORIZON_MS = 100 * 365.25 * 24 * 60 * 60 * 1000;
const SENDING_LEASE_MS = 10 * 60 * 1000;
const MAX_DELIVERY_ATTEMPTS = 5;
const MAX_DELIVERIES_PER_CRON = 3;

export async function handleFutureEmailRequest(request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/v1/email-") && !url.pathname.startsWith("/v1/future-letters")) {
    return null;
  }

  if (request.method === "GET" && url.pathname === "/v1/email-health") {
    return jsonResponse({
      ok: true,
      databaseConfigured: Boolean(env.DB),
      providerConfigured: Boolean(env.RESEND_API_KEY && env.RESEND_FROM_EMAIL),
    });
  }

  if (!env.DB) {
    return errorResponse(503, "email_not_configured", "Email delivery is not configured yet.");
  }

  try {
    if (request.method === "POST" && url.pathname === "/v1/email-verifications/request") {
      return await requestEmailVerification(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/email-verifications/confirm") {
      return await confirmEmailVerification(request, env);
    }

    if (request.method === "GET" && url.pathname === "/v1/email-verifications/status") {
      return await emailVerificationStatus(request, env, url);
    }

    if (request.method === "DELETE" && url.pathname === "/v1/email-device") {
      return await deleteEmailDeviceData(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/future-letters") {
      return await scheduleFutureEmail(request, env);
    }

    const letterMatch = url.pathname.match(/^\/v1\/future-letters\/([0-9a-f-]{36})$/i);
    if (letterMatch && request.method === "GET") {
      return await futureEmailStatus(request, env, letterMatch[1].toLowerCase());
    }

    if (letterMatch && request.method === "DELETE") {
      return await cancelFutureEmail(request, env, letterMatch[1].toLowerCase());
    }

    return errorResponse(404, "not_found", "Not found.");
  } catch (error) {
    if (error instanceof APIError) {
      return errorResponse(error.status, error.code, error.message, error.details);
    }
    console.error("Future email request failed", error instanceof Error ? error.message : "Unknown error");
    return errorResponse(500, "internal_error", "The email service was unable to complete the request.");
  }
}

export async function processDueFutureEmails(env, now = Date.now(), fetchImpl = fetch) {
  if (!env.DB) {
    console.warn("Future email delivery skipped because D1 is not configured.");
    return { processed: 0, sent: 0, failed: 0 };
  }

  if (Math.floor(now / (60 * 1000)) % 60 === 0) {
    await env.DB.prepare(
      "DELETE FROM email_verification_requests WHERE requested_at < ?1"
    ).bind(now - VERIFICATION_RETENTION_MS).run();
  }

  if (!env.RESEND_API_KEY || !env.RESEND_FROM_EMAIL) {
    return { processed: 0, sent: 0, failed: 0 };
  }

  const staleSendingBefore = now - SENDING_LEASE_MS;
  const due = await env.DB.prepare(
    `SELECT id, encrypted_payload, attempt_count
       FROM future_email_letters
      WHERE delivery_at <= ?1
        AND (
          (status IN ('scheduled', 'retry') AND next_attempt_at <= ?1)
          OR (status = 'sending' AND updated_at <= ?2)
        )
      ORDER BY delivery_at ASC
      LIMIT ?3`
  ).bind(now, staleSendingBefore, MAX_DELIVERIES_PER_CRON).all();

  let sent = 0;
  let failed = 0;
  for (const row of due.results ?? []) {
    const claim = await env.DB.prepare(
      `UPDATE future_email_letters
          SET status = 'sending', attempt_count = attempt_count + 1, updated_at = ?2
        WHERE id = ?1
          AND (
            (status IN ('scheduled', 'retry') AND next_attempt_at <= ?2)
            OR (status = 'sending' AND updated_at <= ?3)
          )`
    ).bind(row.id, now, staleSendingBefore).run();

    if ((claim.meta?.changes ?? 0) !== 1) continue;

    const attempt = Number(row.attempt_count ?? 0) + 1;
    try {
      const payload = await decryptPayload(row.encrypted_payload, env.LETTER_ENCRYPTION_KEY);
      const providerID = await sendLetterEmail(payload, row.id, env, fetchImpl);
      const deliveredAt = Date.now();
      const tombstone = await encryptPayload({ delivered: true }, env.LETTER_ENCRYPTION_KEY);
      await env.DB.prepare(
        `UPDATE future_email_letters
            SET status = 'sent', provider_id = ?2, delivered_at = ?3,
                updated_at = ?3, last_error = NULL, encrypted_payload = ?4
          WHERE id = ?1`
      ).bind(row.id, providerID, deliveredAt, tombstone).run();
      sent += 1;
    } catch (error) {
      const permanent = attempt >= MAX_DELIVERY_ATTEMPTS;
      const nextAttemptAt = now + retryDelayMilliseconds(attempt);
      const encryptedPayload = permanent
        ? await encryptPayload({ failed: true }, env.LETTER_ENCRYPTION_KEY)
        : row.encrypted_payload;
      await env.DB.prepare(
        `UPDATE future_email_letters
            SET status = ?2, next_attempt_at = ?3, updated_at = ?4,
                last_error = ?5, encrypted_payload = ?6
          WHERE id = ?1`
      ).bind(
        row.id,
        permanent ? "failed" : "retry",
        nextAttemptAt,
        Date.now(),
        safeProviderError(error),
        encryptedPayload
      ).run();
      failed += 1;
    }
  }

  return { processed: (due.results ?? []).length, sent, failed };
}

async function requestEmailVerification(request, env) {
  requireEmailConfiguration(env);
  const body = await readJSON(request);
  const email = normalizeEmail(body.email);
  const auth = await authenticateDevice(request, env, true);
  const now = Date.now();
  const emailHash = await hmacHex(env.EMAIL_AUTH_SECRET, `email:${email}`);

  const latest = await env.DB.prepare(
    `SELECT requested_at
       FROM email_verification_requests
      WHERE device_id = ?1 AND email_hash = ?2
      ORDER BY requested_at DESC LIMIT 1`
  ).bind(auth.deviceID, emailHash).first();
  if (latest && now - Number(latest.requested_at) < VERIFICATION_COOLDOWN_MS) {
    throw new APIError(429, "verification_rate_limited", "Please wait a minute before requesting another code.");
  }

  const hourly = await env.DB.prepare(
    `SELECT COUNT(*) AS count
       FROM email_verification_requests
      WHERE device_id = ?1 AND requested_at >= ?2`
  ).bind(auth.deviceID, now - 60 * 60 * 1000).first();
  if (Number(hourly?.count ?? 0) >= MAX_VERIFICATION_REQUESTS_PER_HOUR) {
    throw new APIError(429, "verification_rate_limited", "Too many verification requests. Please try again later.");
  }

  const code = randomVerificationCode();
  const requestID = crypto.randomUUID();
  const codeHash = await hmacHex(
    env.EMAIL_AUTH_SECRET,
    `code:${auth.deviceID}:${emailHash}:${code}`
  );

  await env.DB.prepare(
    `INSERT INTO email_verification_requests
      (id, device_id, email_hash, code_hash, requested_at, expires_at, attempts)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)`
  ).bind(requestID, auth.deviceID, emailHash, codeHash, now, now + VERIFICATION_LIFETIME_MS).run();

  try {
    await sendResendEmail({
      to: email,
      subject: "Your Flara Day verification code",
      text: `Your Flara Day verification code is ${code}. It expires in 10 minutes.`,
      html: `<p>Your Flara Day verification code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p><p>It expires in 10 minutes.</p>`,
      idempotencyKey: `verify-${requestID}`,
    }, env, fetch);
  } catch (error) {
    await env.DB.prepare("DELETE FROM email_verification_requests WHERE id = ?1").bind(requestID).run();
    throw error;
  }

  return jsonResponse({ sent: true, expiresInSeconds: VERIFICATION_LIFETIME_MS / 1000 });
}

async function confirmEmailVerification(request, env) {
  requireEmailConfiguration(env);
  const body = await readJSON(request);
  const email = normalizeEmail(body.email);
  const code = String(body.code ?? "").trim();
  if (!/^\d{6}$/.test(code)) {
    throw new APIError(400, "invalid_verification_code", "Enter the six-digit verification code.");
  }

  const auth = await authenticateDevice(request, env, false);
  const now = Date.now();
  const emailHash = await hmacHex(env.EMAIL_AUTH_SECRET, `email:${email}`);
  const verification = await env.DB.prepare(
    `SELECT id, code_hash, expires_at, attempts
       FROM email_verification_requests
      WHERE device_id = ?1 AND email_hash = ?2 AND consumed_at IS NULL
      ORDER BY requested_at DESC LIMIT 1`
  ).bind(auth.deviceID, emailHash).first();

  if (!verification || Number(verification.expires_at) < now) {
    throw new APIError(410, "verification_expired", "The verification code expired. Request a new one.");
  }
  if (Number(verification.attempts) >= MAX_VERIFICATION_ATTEMPTS) {
    throw new APIError(429, "verification_attempts_exceeded", "Request a new verification code.");
  }

  const submittedHash = await hmacHex(
    env.EMAIL_AUTH_SECRET,
    `code:${auth.deviceID}:${emailHash}:${code}`
  );
  if (submittedHash !== verification.code_hash) {
    await env.DB.prepare(
      "UPDATE email_verification_requests SET attempts = attempts + 1 WHERE id = ?1"
    ).bind(verification.id).run();
    throw new APIError(400, "invalid_verification_code", "That verification code is incorrect.");
  }

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO verified_emails (device_id, email_hash, encrypted_email, verified_at)
       VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(device_id, email_hash) DO UPDATE SET
         encrypted_email = excluded.encrypted_email,
         verified_at = excluded.verified_at`
    ).bind(auth.deviceID, emailHash, "verified", now),
    env.DB.prepare("DELETE FROM email_verification_requests WHERE id = ?1").bind(verification.id),
  ]);

  return jsonResponse({ verified: true, email });
}

async function emailVerificationStatus(request, env, url) {
  const email = normalizeEmail(url.searchParams.get("email"));
  const auth = await authenticateDevice(request, env, false);
  const emailHash = await hmacHex(env.EMAIL_AUTH_SECRET, `email:${email}`);
  const row = await env.DB.prepare(
    "SELECT verified_at FROM verified_emails WHERE device_id = ?1 AND email_hash = ?2"
  ).bind(auth.deviceID, emailHash).first();
  return jsonResponse({ verified: Boolean(row), verifiedAt: row?.verified_at ?? null });
}

async function scheduleFutureEmail(request, env) {
  requireEmailConfiguration(env);
  const body = await readJSON(request);
  const auth = await authenticateDevice(request, env, false);
  const id = normalizedUUID(body.id, "letter id");
  const email = normalizeEmail(body.email);
  const title = String(body.title ?? "").trim().slice(0, MAX_TITLE_LENGTH);
  const letterBody = String(body.body ?? "").trim();
  const deliveryAt = new Date(body.deliveryAt).getTime();
  const now = Date.now();
  const requestedWrittenAt = new Date(body.writtenAt).getTime();
  const writtenAt = Number.isFinite(requestedWrittenAt) && requestedWrittenAt <= now + 5 * 60_000
    ? requestedWrittenAt
    : now;
  const timeZone = normalizedTimeZone(body.timeZone);

  if (!letterBody || letterBody.length > MAX_BODY_LENGTH) {
    throw new APIError(400, "invalid_letter_body", `The letter must contain between 1 and ${MAX_BODY_LENGTH} characters.`);
  }
  if (!Number.isFinite(deliveryAt) || deliveryAt < now + 30_000) {
    throw new APIError(400, "invalid_delivery_time", "Choose a delivery time at least 30 seconds in the future.");
  }
  if (deliveryAt - now > MAX_DELIVERY_HORIZON_MS) {
    throw new APIError(400, "invalid_delivery_time", "The delivery date is too far in the future.");
  }

  const emailHash = await hmacHex(env.EMAIL_AUTH_SECRET, `email:${email}`);
  const verified = await env.DB.prepare(
    "SELECT verified_at FROM verified_emails WHERE device_id = ?1 AND email_hash = ?2"
  ).bind(auth.deviceID, emailHash).first();
  if (!verified) {
    throw new APIError(403, "email_not_verified", "Verify this email address before scheduling the letter.");
  }

  const existing = await env.DB.prepare(
    "SELECT device_id, status FROM future_email_letters WHERE id = ?1"
  ).bind(id).first();
  if (existing) {
    if (existing.device_id !== auth.deviceID) {
      throw new APIError(409, "letter_id_conflict", "That letter identifier is already in use.");
    }
    throw new APIError(409, "letter_already_scheduled", "This letter is already scheduled.", { status: existing.status });
  }

  const encryptedPayload = await encryptPayload({
    email,
    title,
    body: letterBody,
    writtenAt: new Date(writtenAt).toISOString(),
    timeZone,
  }, env.LETTER_ENCRYPTION_KEY);
  await env.DB.prepare(
    `INSERT INTO future_email_letters
      (id, device_id, encrypted_payload, delivery_at, status, attempt_count,
       next_attempt_at, created_at, updated_at)
     VALUES (?1, ?2, ?3, ?4, 'scheduled', 0, ?4, ?5, ?5)`
  ).bind(id, auth.deviceID, encryptedPayload, deliveryAt, now).run();

  return jsonResponse({ id, status: "scheduled", deliveryAt: new Date(deliveryAt).toISOString() }, 201);
}

async function futureEmailStatus(request, env, id) {
  const auth = await authenticateDevice(request, env, false);
  const row = await env.DB.prepare(
    `SELECT id, delivery_at, status, attempt_count, delivered_at, canceled_at
       FROM future_email_letters WHERE id = ?1 AND device_id = ?2`
  ).bind(id, auth.deviceID).first();
  if (!row) throw new APIError(404, "letter_not_found", "The scheduled letter was not found.");
  return jsonResponse(publicLetterStatus(row));
}

async function cancelFutureEmail(request, env, id) {
  const auth = await authenticateDevice(request, env, false);
  const result = await env.DB.prepare(
    `DELETE FROM future_email_letters
      WHERE id = ?1 AND device_id = ?2 AND status != 'sending'`
  ).bind(id, auth.deviceID).run();
  if ((result.meta?.changes ?? 0) === 1) {
    return new Response(null, { status: 204 });
  }

  const row = await env.DB.prepare(
    "SELECT status FROM future_email_letters WHERE id = ?1 AND device_id = ?2"
  ).bind(id, auth.deviceID).first();
  if (!row) return new Response(null, { status: 204 });
  throw new APIError(409, "letter_cannot_be_canceled", "This letter can no longer be canceled.", { status: row.status });
}

async function deleteEmailDeviceData(request, env) {
  const auth = await authenticateDevice(request, env, false);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM email_verification_requests WHERE device_id = ?1").bind(auth.deviceID),
    env.DB.prepare("DELETE FROM verified_emails WHERE device_id = ?1").bind(auth.deviceID),
    env.DB.prepare("DELETE FROM future_email_letters WHERE device_id = ?1").bind(auth.deviceID),
    env.DB.prepare("DELETE FROM devices WHERE id = ?1").bind(auth.deviceID),
  ]);
  return new Response(null, { status: 204 });
}

async function authenticateDevice(request, env, allowCreate) {
  if (!env.EMAIL_AUTH_SECRET) {
    throw new APIError(503, "email_not_configured", "Email authentication is not configured.");
  }
  const deviceID = normalizedUUID(request.headers.get("x-flara-device-id"), "device id");
  const authorization = request.headers.get("authorization") ?? "";
  const secret = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (!/^[A-Za-z0-9_-]{40,100}$/.test(secret)) {
    throw new APIError(401, "invalid_device_credentials", "Device credentials are missing or invalid.");
  }

  const secretHash = await hmacHex(env.EMAIL_AUTH_SECRET, `device:${secret}`);
  const existing = await env.DB.prepare(
    "SELECT secret_hash FROM devices WHERE id = ?1"
  ).bind(deviceID).first();
  const now = Date.now();

  if (!existing) {
    if (!allowCreate) {
      throw new APIError(401, "device_not_registered", "Verify an email address on this device first.");
    }
    await env.DB.prepare(
      "INSERT INTO devices (id, secret_hash, created_at, last_seen_at) VALUES (?1, ?2, ?3, ?3)"
    ).bind(deviceID, secretHash, now).run();
  } else if (existing.secret_hash !== secretHash) {
    throw new APIError(401, "invalid_device_credentials", "Device credentials are invalid.");
  } else {
    await env.DB.prepare("UPDATE devices SET last_seen_at = ?2 WHERE id = ?1").bind(deviceID, now).run();
  }

  return { deviceID };
}

async function sendLetterEmail(payload, letterID, env, fetchImpl) {
  const subject = payload.title || "A letter from your past self";
  const escapedBody = escapeHTML(payload.body).replace(/\n/g, "<br>");
  const writtenContext = formatWrittenContext(payload.writtenAt, payload.timeZone);
  const writtenHTML = writtenContext
    ? `<p style="margin:8px 0 22px;color:#6b7672;font-size:14px">${escapeHTML(writtenContext)}</p>`
    : "";
  const writtenText = writtenContext ? `\n${writtenContext}\n` : "";
  const html = `<!doctype html><html><body style="margin:0;background:#f3faf7;color:#17201d;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif"><div style="max-width:640px;margin:0 auto;padding:40px 24px"><p style="color:#4f776b;font-weight:600">Flara Day</p><h1 style="font-size:28px">${escapeHTML(subject)}</h1>${writtenHTML}<div style="font-size:18px;line-height:1.65;background:#ffffff;padding:28px;border-radius:12px">${escapedBody}</div><p style="margin-top:24px;color:#6b7672;font-size:13px">This future letter was scheduled privately in Flara Day.</p></div></body></html>`;
  return sendResendEmail({
    to: payload.email,
    subject,
    text: `${subject}\n${writtenText}\n${payload.body}\n\nThis future letter was scheduled privately in Flara Day.`,
    html,
    idempotencyKey: `future-letter-${letterID}`,
  }, env, fetchImpl);
}

async function sendResendEmail(email, env, fetchImpl) {
  requireEmailConfiguration(env);
  const response = await fetchImpl("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.RESEND_API_KEY}`,
      "content-type": "application/json",
      "idempotency-key": email.idempotencyKey,
    },
    body: JSON.stringify({
      from: env.RESEND_FROM_EMAIL,
      to: [email.to],
      subject: email.subject,
      text: email.text,
      html: email.html,
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.id) {
    throw new Error(`Resend request failed with status ${response.status}: ${data.message ?? data.name ?? "unknown error"}`);
  }
  return data.id;
}

function requireEmailConfiguration(env) {
  if (!env.RESEND_API_KEY || !env.RESEND_FROM_EMAIL || !env.LETTER_ENCRYPTION_KEY || !env.EMAIL_AUTH_SECRET) {
    throw new APIError(503, "email_not_configured", "Email delivery is not configured yet.");
  }
}

async function readJSON(request) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 100_000) throw new APIError(413, "request_too_large", "The request is too large.");
  try {
    return await request.json();
  } catch {
    throw new APIError(400, "invalid_json", "The request body must be valid JSON.");
  }
}

export function normalizeEmail(value) {
  const email = String(value ?? "").trim().toLowerCase();
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new APIError(400, "invalid_email", "Enter a valid email address.");
  }
  return email;
}

function normalizedTimeZone(value) {
  const candidate = String(value ?? "UTC").trim() || "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: candidate }).format();
    return candidate;
  } catch {
    return "UTC";
  }
}

function normalizedUUID(value, fieldName) {
  const candidate = String(value ?? "").trim().toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(candidate)) {
    throw new APIError(400, "invalid_identifier", `The ${fieldName} is invalid.`);
  }
  return candidate;
}

function randomVerificationCode() {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);
  return String(values[0] % 1_000_000).padStart(6, "0");
}

async function hmacHex(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function encryptPayload(payload, base64Key) {
  const key = await encryptionKey(base64Key);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(payload));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext);
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return bytesToBase64(combined);
}

async function decryptPayload(value, base64Key) {
  const combined = base64ToBytes(value);
  if (combined.length < 29) throw new Error("Encrypted letter payload is invalid.");
  const key = await encryptionKey(base64Key);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: combined.slice(0, 12) },
    key,
    combined.slice(12)
  );
  return JSON.parse(new TextDecoder().decode(plaintext));
}

async function encryptionKey(base64Key) {
  if (!base64Key) throw new Error("Letter encryption key is missing.");
  const bytes = base64ToBytes(base64Key);
  if (bytes.length !== 32) throw new Error("Letter encryption key must contain 32 bytes.");
  return crypto.subtle.importKey("raw", bytes, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64ToBytes(value) {
  const binary = atob(String(value ?? ""));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function retryDelayMilliseconds(attempt) {
  return [60_000, 5 * 60_000, 30 * 60_000, 2 * 60 * 60_000, 12 * 60 * 60_000][
    Math.min(Math.max(attempt - 1, 0), 4)
  ];
}

export function escapeHTML(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function formatWrittenContext(writtenAt, timeZone = "UTC", deliveredAt = Date.now()) {
  const writtenDate = new Date(writtenAt);
  const deliveredDate = new Date(deliveredAt);
  if (!Number.isFinite(writtenDate.getTime()) || !Number.isFinite(deliveredDate.getTime())) {
    return null;
  }

  const formattedDate = new Intl.DateTimeFormat("en-US", {
    timeZone: normalizedTimeZone(timeZone),
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(writtenDate);
  const elapsedDays = Math.max(0, Math.floor((deliveredDate.getTime() - writtenDate.getTime()) / 86_400_000));

  let age;
  if (elapsedDays === 0) {
    age = "today";
  } else if (elapsedDays < 30) {
    age = `${elapsedDays} ${elapsedDays === 1 ? "day" : "days"} ago`;
  } else if (elapsedDays < 365) {
    const months = Math.max(1, Math.floor(elapsedDays / 30));
    age = `${months} ${months === 1 ? "month" : "months"} ago`;
  } else {
    const years = Math.max(1, Math.floor(elapsedDays / 365));
    age = `${years} ${years === 1 ? "year" : "years"} ago`;
  }

  return `Written ${formattedDate} · ${age}`;
}

function safeProviderError(error) {
  return String(error instanceof Error ? error.message : "Unknown provider error")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[email redacted]")
    .slice(0, 500);
}

function publicLetterStatus(row) {
  return {
    id: row.id,
    status: row.status,
    deliveryAt: new Date(Number(row.delivery_at)).toISOString(),
    attemptCount: Number(row.attempt_count ?? 0),
    deliveredAt: row.delivered_at ? new Date(Number(row.delivered_at)).toISOString() : null,
    canceledAt: row.canceled_at ? new Date(Number(row.canceled_at)).toISOString() : null,
  };
}

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function errorResponse(status, code, message, details) {
  return jsonResponse({ error: message, code, ...(details ? { details } : {}) }, status);
}

class APIError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}
