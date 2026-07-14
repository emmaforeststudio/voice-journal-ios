# Flara Day Backend

This backend keeps the OpenAI API key off the iPhone and out of GitHub. The app sends audio directly as `multipart/form-data`, and the backend forwards the audio to OpenAI.

## Local development

1. Duplicate `.env.example` as `.env`.
2. Replace the placeholder with the API key from the Flara Day Development project.
3. Start the backend:

```sh
./backend/start.sh
```

4. Verify it from the Mac:

```sh
curl http://localhost:8787/health
```

The iPhone and Mac must be connected to the same local network during development.

## Cloudflare Workers

The Worker entrypoint is `worker/index.mjs`, and `wrangler.toml` is configured for `flara-day-backend`.

Log in once:

```sh
pnpm dlx wrangler login
```

Set the OpenAI key as a Worker secret:

```sh
pnpm dlx wrangler secret put OPENAI_API_KEY
```

Deploy:

```sh
pnpm dlx wrangler deploy
```

After deployment, use the returned `workers.dev` URL as the app's Release `VOICE_JOURNAL_BACKEND_URL`.

## Scheduled future-letter email

Email delivery uses four Cloudflare/Resend pieces:

- **D1** stores device credentials, verified-email hashes, delivery status, and encrypted letters that are waiting to be sent.
- **Cron Triggers** run the delivery worker once per minute.
- **Cloudflare Workers** authenticate the app, verify recipient addresses, and send due letters.
- **Resend** delivers verification codes and future-letter emails.

The app does not need a user account. It creates a random device identifier and secret in the iOS Keychain. A recipient email must be verified on that device before a letter can be scheduled.

### First-time setup

Create the D1 database and copy its ID into `wrangler.toml`:

```sh
pnpm dlx wrangler d1 create flara-day-email
pnpm dlx wrangler d1 migrations apply flara-day-email --remote
```

Set these Worker secrets. Never commit their values:

```sh
pnpm dlx wrangler secret put LETTER_ENCRYPTION_KEY
pnpm dlx wrangler secret put EMAIL_AUTH_SECRET
pnpm dlx wrangler secret put RESEND_API_KEY
pnpm dlx wrangler secret put RESEND_FROM_EMAIL
```

`LETTER_ENCRYPTION_KEY` must be a Base64-encoded 32-byte random key. `EMAIL_AUTH_SECRET` should be a separate long random value. `RESEND_FROM_EMAIL` must use a sender/domain that is verified in Resend before mail can be sent to beta users.

The current D1 database and the first migration are already deployed to the Emma Forest Studio Cloudflare account. The encryption and authentication secrets are configured. Resend remains intentionally unconfigured until a Resend API key and verified sender are available.

### Delivery behavior

- Verification codes expire after 10 minutes and requests are rate-limited.
- Letters are encrypted with AES-GCM while waiting in D1.
- Delivery runs once per minute and retries transient failures with bounded backoff.
- Each Free-plan Cron invocation processes at most three due letters to stay conservative with Cloudflare's CPU allowance.
- After delivery or permanent failure, the full encrypted letter is replaced with a status-only encrypted tombstone. User deletion removes the remote record entirely.
- Provider errors are truncated and email addresses are redacted before storage.
- The app can cancel a scheduled email when the user deletes it before delivery.

### Health checks

```sh
curl https://flara-day-backend.emmaforeststudio.workers.dev/health
curl https://flara-day-backend.emmaforeststudio.workers.dev/v1/email-health
```

`providerConfigured` remains `false` until both Resend secrets are present.

### Tests

```sh
node --check worker/future-email.mjs
node --check worker/index.mjs
node --test worker/future-email.test.mjs
```
