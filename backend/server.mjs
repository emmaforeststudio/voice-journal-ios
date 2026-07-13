import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createJournalHandler } from "./journal-core.mjs";

loadEnv(resolve(import.meta.dirname, ".env"));

const port = Number(process.env.PORT || 8787);
const apiKey = process.env.OPENAI_API_KEY;
const previewSessions = new Map();
const handleJournalRequest = createJournalHandler({
  apiKey,
  previewSessions,
  fetchImpl: fetch,
});

const server = createServer(async (request, response) => {
  try {
    const body = await readRequestBody(request);
    const fetchRequest = new Request(`http://${request.headers.host || "localhost"}${request.url}`, {
      method: request.method,
      headers: request.headers,
      body: body.byteLength > 0 ? body : undefined,
    });
    const fetchResponse = await handleJournalRequest(fetchRequest);
    await writeFetchResponse(response, fetchResponse);
  } catch (error) {
    console.error(error);
    response.writeHead(500, { "Content-Type": "application/json" });
    response.end(JSON.stringify({
      error: error instanceof Error ? error.message : "Unexpected server error",
    }));
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Flara Day backend listening on http://0.0.0.0:${port}`);
  console.log(`OpenAI API key configured: ${Boolean(apiKey)}`);
});

async function readRequestBody(request) {
  if (request.method === "GET" || request.method === "HEAD") {
    return new Uint8Array();
  }

  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > 20 * 1024 * 1024) {
      throw new Error("Recording is too large for the development backend.");
    }
    chunks.push(chunk);
  }

  return Buffer.concat(chunks);
}

async function writeFetchResponse(response, fetchResponse) {
  response.writeHead(
    fetchResponse.status,
    Object.fromEntries(fetchResponse.headers.entries())
  );
  response.end(Buffer.from(await fetchResponse.arrayBuffer()));
}

function loadEnv(path) {
  try {
    const contents = readFileSync(path, "utf8");
    for (const line of contents.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const separator = trimmed.indexOf("=");
      if (separator < 1) continue;
      const key = trimmed.slice(0, separator).trim();
      const value = trimmed.slice(separator + 1).trim();
      if (!process.env[key]) process.env[key] = value;
    }
  } catch {
    // The health endpoint reports whether the local key has been configured.
  }
}
