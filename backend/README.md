# Flara Day Backend

The backend keeps OpenAI and email-provider secrets off the iPhone. The app sends
audio directly as `multipart/form-data`; the backend forwards it to OpenAI and
returns transcription and journal results.

The Worker also provides optional title-and-body translation. Translation
requests contain text rather than audio and return one version in the target
language selected in the app's Transcript Output setting.

## Production

- Worker: `flara-day-backend`
- URL: `https://flara-day-backend.emmaforeststudio.workers.dev`
- D1, Cron, recipient verification, encrypted pending-letter storage, and Resend
  delivery are configured.
- Support: `/support`
- Privacy: `/privacy`

Health checks:

```sh
curl https://flara-day-backend.emmaforeststudio.workers.dev/health
curl https://flara-day-backend.emmaforeststudio.workers.dev/v1/email-health
```

Expected email health: `databaseConfigured: true` and
`providerConfigured: true`.

## Models

- Live preview: `gpt-4o-mini-transcribe`
- Final journal and future-letter transcription: `gpt-4o-transcribe`
- Cleanup, title, emoji/mood, and language handling: `gpt-4o-mini`
- Optional journal and future-letter translation: `gpt-4o-mini`

Live preview is off by default in the app.
Both preview and final transcription requests use OpenAI automatic
voice-activity chunking so multilingual switches are evaluated around natural
speech boundaries instead of as one monolithic audio block.

During cleanup, minority writing-system spans are replaced with immutable
placeholders and restored afterward. This lets the cleanup pass normalize the
dominant language without translating or dropping brief language switches.
Chinese and Japanese pause-generated character spacing is normalized locally;
Korean and Latin word spacing is preserved. If cleanup omits protected content,
the backend returns the complete, locally normalized transcript instead.

## Translation

- `POST /translate` accepts `title`, `body`, and `targetLanguage` as JSON.
- The iPhone always retains the original version and caches one translated
  version so switching does not repeatedly call OpenAI.
- Settings is the single source of truth for the target language.
- Draft Future Letters can deliver either Original or the configured translated
  version. Scheduled and delivered letters are not changed by later preference
  updates.

## Long Recordings

- The app permits up to 30 minutes in one recording during the selected-friends
  beta, with a 60-minute on-device daily transcription allowance.
- Audio is recorded as 16 kHz mono PCM to reduce upload size while preserving
  the speech frequency range.
- Final audio longer than six minutes is uploaded as overlapping six-minute WAV
  chunks so each Worker request remains under the configured body-size limit.
- The app passes the end of each transcript to the next chunk as continuity
  context, merges the results, and sends the complete text to
  `POST /journal-text` for one cleanup and title-generation pass.
- The local daily counter is beta cost protection only. A public paid release
  must enforce allowances on the backend.

## Local Development

1. Duplicate `.env.example` as `.env`.
2. Add a development OpenAI API key.
3. Run `./backend/start.sh`.
4. Verify `curl http://localhost:8787/health`.

Debug and Release use the production Worker by default. To test this local
backend from Xcode, temporarily change the target's Debug
`VOICE_JOURNAL_BACKEND_URL` build setting to the Mac's reachable LAN URL. The Mac
and iPhone must then share a local network. Do not commit that temporary URL.

## Cloudflare Deployment

Log in once, set secrets privately, apply migrations, and deploy:

```sh
pnpm dlx wrangler login
pnpm dlx wrangler d1 migrations apply flara-day-email --remote
pnpm dlx wrangler deploy
```

Required Worker secrets:

- `OPENAI_API_KEY`
- `LETTER_ENCRYPTION_KEY` (Base64-encoded 32-byte key)
- `EMAIL_AUTH_SECRET`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`

Never commit secret values. `RESEND_FROM_EMAIL` must use the verified studio
sending domain.

## Future-Letter Delivery

- The app creates a random device ID and secret in the iOS Keychain; no account
  is required.
- Verification codes expire after ten minutes and requests are rate-limited.
- Pending addresses, titles, and letter bodies are encrypted with AES-GCM in D1.
- Cron runs once per minute and retries transient provider failures.
- Free-plan batches process at most three due letters per invocation.
- Successful or permanently failed letters are scrubbed to status-only tombstones.
- Deleting a pending letter removes its remote record.
- Provider errors are truncated and email addresses are redacted before storage.

See `AppStore/RESEND_SETUP_CHECKLIST.md` for release testing, monitoring, and
secret-rotation notes.

## Tests

```sh
node --check journal-core.mjs
node --test journal-core.test.mjs
node --check worker/future-email.mjs
node --check worker/index.mjs
node --test worker/future-email.test.mjs
```
