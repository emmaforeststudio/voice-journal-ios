import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

loadEnv(resolve(import.meta.dirname, ".env"));

const port = Number(process.env.PORT || 8787);
const apiKey = process.env.OPENAI_API_KEY;
const maxBodyBytes = 20 * 1024 * 1024;
const supportedMoodEmojis = ["🙂", "😊", "🥲", "😌", "😔", "😤", "🥰", "🤔", "😴", "✨"];
const supportedLanguages = [
  "english",
  "chinese",
  "korean",
  "japanese",
  "german",
  "french",
  "spanish",
  "other",
];

const server = createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/health") {
      return sendJSON(response, 200, {
        status: "ok",
        openAIConfigured: Boolean(apiKey),
      });
    }

    if (request.method !== "POST" || !["/journal", "/preview"].includes(request.url)) {
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

    const transcript = await transcribe(audio, request.url === "/preview");
    if (request.url === "/preview") {
      return sendJSON(response, 200, { transcript });
    }
    const journal = await polishJournal(transcript, body.livePreviewTranscript);

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

async function transcribe(audio, allowEmpty = false) {
  const form = new FormData();
  form.append("model", "gpt-4o-mini-transcribe");
  form.append("response_format", "json");
  form.append(
    "prompt",
    "This is a personal journal entry. Preserve the speaker's meaning and wording accurately."
  );
  form.append("file", new Blob([audio], { type: "audio/wav" }), "journal.wav");

  const result = await openAIRequest("/v1/audio/transcriptions", {
    method: "POST",
    body: form,
  });

  if (!result.text?.trim()) {
    if (allowEmpty) return "";
    throw new Error("OpenAI did not detect speech in the recording.");
  }

  return result.text.trim();
}

async function polishJournal(transcript, livePreviewTranscript = "") {
  const preview = typeof livePreviewTranscript === "string"
    ? livePreviewTranscript.trim()
    : "";
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
            "The final audio transcription is the primary source.",
            "The latest live preview is a recovery source that may contain earlier speech omitted from the final transcription.",
            "Preserve every distinct thought found in either source, while removing duplicated wording that appears in both.",
            "Never discard an earlier topic merely because it appears only in the live preview.",
            "Keep thoughts in their spoken order; when the live preview recovers earlier speech, place it before a final-only ending.",
            "Organize the journal into natural paragraphs based on meaningful changes in topic, event, time, or emotion.",
            "Return each paragraph as a separate item in the paragraphs array.",
            "When there are two clearly different events or topics, return them as separate paragraphs even if each one is brief.",
            "A clear time transition combined with a change of activity, such as moving from a morning family event to afternoon work, starts a new paragraph.",
            "Strong time-transition phrases such as later, afterward, in the afternoon, or their equivalents must begin a new paragraph.",
            "Keep one paragraph when the journal contains only one coherent thought, and do not over-segment the writing.",
            "Do not add headings, bullet points, numbered lists, or other formatting to the journal body.",
            "Create a thoughtful, specific title of at most six words.",
            "Do not put emoji in the title or journal body; use only the dedicated emoji field.",
            `Choose exactly one emoji from this set that best reflects the emotional tone: ${supportedMoodEmojis.join(" ")}`,
            "Classify the primary language using exactly one of these labels: english, chinese, korean, japanese, german, french, spanish, other.",
            "The title and journal body must both be written in the same primary language as the speaker.",
          ].join(" "),
        },
        {
          role: "user",
          content: [
            "FINAL AUDIO TRANSCRIPTION:",
            transcript,
            "",
            "LATEST LIVE PREVIEW:",
            preview || "(unavailable)",
          ].join("\n"),
        },
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
              paragraphs: {
                type: "array",
                items: { type: "string" },
              },
              emoji: { type: "string", enum: supportedMoodEmojis },
              language: { type: "string", enum: supportedLanguages },
            },
            required: ["title", "paragraphs", "emoji", "language"],
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

  const journal = JSON.parse(content);
  const paragraphs = Array.isArray(journal.paragraphs)
    ? journal.paragraphs.map((paragraph) => paragraph.trim()).filter(Boolean)
    : [];
  if (paragraphs.length === 0) {
    throw new Error("OpenAI did not return any journal paragraphs.");
  }

  return {
    title: journal.title,
    body: paragraphs.join("\n\n"),
    emoji: journal.emoji,
    language: journal.language,
  };
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
