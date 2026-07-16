import assert from "node:assert/strict";
import test from "node:test";
import {
  escapeHTML,
  formatWrittenContext,
  handleFutureEmailRequest,
  normalizeEmail,
  retryDelayMilliseconds,
} from "./future-email.mjs";

test("normalizeEmail trims and lowercases an address", () => {
  assert.equal(normalizeEmail("  Emma@Example.COM "), "emma@example.com");
});

test("normalizeEmail rejects malformed addresses", () => {
  assert.throws(() => normalizeEmail("not-an-email"), /valid email address/);
});

test("escapeHTML protects future-letter markup", () => {
  assert.equal(
    escapeHTML(`<script>alert("x")</script> & 'hello'`),
    "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#39;hello&#39;"
  );
});

test("written context includes the original local date and relative age", () => {
  assert.equal(
    formatWrittenContext(
      "2025-07-16T23:12:00.000Z",
      "America/Chicago",
      "2026-07-16T23:12:00.000Z"
    ),
    "Written July 16, 2025 at 6:12 PM · 1 year ago"
  );
  assert.equal(
    formatWrittenContext(
      "2026-06-16T23:12:00.000Z",
      "America/Chicago",
      "2026-07-16T23:12:00.000Z"
    ),
    "Written June 16, 2026 at 6:12 PM · 1 month ago"
  );
});

test("delivery retries back off and cap at twelve hours", () => {
  assert.equal(retryDelayMilliseconds(1), 60_000);
  assert.equal(retryDelayMilliseconds(2), 5 * 60_000);
  assert.equal(retryDelayMilliseconds(5), 12 * 60 * 60_000);
  assert.equal(retryDelayMilliseconds(20), 12 * 60 * 60_000);
});

test("email routes translate missing device credentials into JSON 401", async () => {
  const request = new Request(
    "https://example.com/v1/future-letters/00000000-0000-4000-8000-000000000001",
    { headers: { "X-Flara-Device-ID": "00000000-0000-4000-8000-000000000002" } }
  );
  const response = await handleFutureEmailRequest(request, {
    DB: {},
    EMAIL_AUTH_SECRET: "test-secret",
  });

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), {
    error: "Device credentials are missing or invalid.",
    code: "invalid_device_credentials",
  });
});
