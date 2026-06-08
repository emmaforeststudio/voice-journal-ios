import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

loadEnv(resolve(import.meta.dirname, ".env"));

const port = Number(process.env.PORT || 8787);
const apiKey = process.env.OPENAI_API_KEY;
const maxBodyBytes = 20 * 1024 * 1024;

const server = createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") {
      return sendJSON(response, 200, {
        status: "ok",
        openAIConfigured: Boolean(apiKey),
      });
    }

    if (request.method !== "POST" || request.url !== "/journal") {
      return sendJSON(response, 404, { error: "Not found" });
    }

    if (!apiKey) {
      return sendJSON(response, 503, {
        error: "OPENAI_API_KEY is missing from backend/.env",
      });
    }

    const body = await readJSONBody(request);
    const audio = Buffer.from(body.audioBase64 || "", "base64");

    if (audio.length === 0) {
      return sendJSON(response, 400, { error: "Audio is required" });
    }

    const transcript = await transcribe(audio);
    const journal = await polishJournal(transcript);

    return sendJSON(response, 200, { transcript, ...journal });
  } catch (error) {
    console.error(error);
    return sendJSON(response, 500, {
      error: error instanceof Error ? error.message : "Unexpected server error",
    });
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Voice Journal backend listening on http://0.0.0.0:${port}`);
  console.log(`OpenAI API key configured: ${Boolean(apiKey)}`);
});

async function transcribe(audio) {
  const form = new FormData();
  form.append("model", "gpt-4o-mini-transcribe");
  form.append("response_format", "json");
  form.append(
    "prompt",
    "This is a personal journal entry. Preserve the speaker's meaning and wording accurately."
  );
  form.append("file", new Blob([audio], { type: "audio/mp4" }), "journal.m4a");

  const result = await openAIRequest("/v1/audio/transcriptions", {
    method: "POST",
    body: form,
  });

  if (!result.text?.trim()) {
    throw new Error("OpenAI did not detect speech in the recording.");
  }

  return result.text.trim();
}

async function polishJournal(transcript) {
  const result = await openAIRequest("/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: [
            "You edit personal voice journals.",
            "Remove filler words, false starts, and accidental repetition.",
            "Correct obvious transcription mistakes only when context makes the correction clear.",
            "Preserve the writer's meaning, facts, emotional tone, and first-person voice.",
            "Do not invent events, advice, interpretations, or details.",
            "Create a thoughtful, specific title of at most six words.",
            "Choose exactly one emoji that best reflects the emotional tone.",
            "Detect whether the journal is primarily English or Chinese.",
            "Return the title and journal body in the same primary language as the speaker.",
          ].join(" "),
        },
        { role: "user", content: transcript },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "voice_journal",
          strict: true,
          schema: {
            type: "object",
            properties: {
              title: { type: "string" },
              body: { type: "string" },
              emoji: { type: "string" },
              language: { type: "string", enum: ["english", "chinese"] },
            },
            required: ["title", "body", "emoji", "language"],
            additionalProperties: false,
          },
        },
      },
    }),
  });

  const content = result.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI did not return a polished journal.");
  }

  return JSON.parse(content);
}

async function openAIRequest(path, options) {
  const response = await fetch(`https://api.openai.com${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      ...options.headers,
    },
  });

  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error?.message || `OpenAI request failed (${response.status})`);
  }

  return payload;
}

async function readJSONBody(request) {
  const chunks = [];
  let length = 0;

  for await (const chunk of request) {
    length += chunk.length;
    if (length > maxBodyBytes) {
      throw new Error("Recording is too large for the development backend.");
    }
    chunks.push(chunk);
  }

  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJSON(response, status, payload) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
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
