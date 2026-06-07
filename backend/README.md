# Voice Journal Development Backend

This local backend keeps the OpenAI API key off the iPhone and out of GitHub.

1. Duplicate `.env.example` as `.env`.
2. Replace the placeholder with the API key from the Voice Journal Development project.
3. Start the backend:

```sh
node backend/server.mjs
```

4. Verify it from the Mac:

```sh
curl http://localhost:8787/health
```

The iPhone and Mac must be connected to the same local network during development.
