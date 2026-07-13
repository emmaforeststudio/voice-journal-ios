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
