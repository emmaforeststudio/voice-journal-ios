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
    try {
      journal.body = await structureJournalBody(journal.body);
    } catch (error) {
      console.error("Paragraph structuring failed; returning the complete polished journal.", error);
    }

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
            "Keep distinct topics, events, time periods, and emotional reflections as separate sentences; do not join them into one long sentence.",
            "Do not add headings, bullet points, numbered lists, or other formatting to the journal body.",
            "Create a thoughtful title that represents the complete journal, not merely its first sentence or first event.",
            "If one event clearly dominates the journal, title that event.",
            "If several events share an emotional journey, title the emotional arc connecting them.",
            "For an emotional-arc title, name the actual transformation or resulting feeling instead of using a generic label such as Emotional Journey or Daily Reflections.",
            "If several unrelated events are similarly important, title the overall character of the day or reflection.",
            "Never title a minor detail merely because it appears first.",
            "Make the title specific enough to distinguish this journal from an ordinary day.",
            "Prefer a natural title of three to six words, and never exceed six words.",
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
              body: { type: "string" },
              emoji: { type: "string", enum: supportedMoodEmojis },
              language: { type: "string", enum: supportedLanguages },
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

  const journal = JSON.parse(content);
  return {
    title: journal.title,
    body: journal.body.trim(),
    emoji: journal.emoji,
    language: journal.language,
  };
}

async function structureJournalBody(body) {
  const sentences = segmentSentences(body);
  if (sentences.length < 2) return body.trim();

  const numberedSentences = sentences
    .map((sentence, index) => `${index + 1}. ${sentence}`)
    .join("\n");
  const result = await openAIRequest("/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0,
      messages: [
        {
          role: "system",
          content: [
            "Your only task is to choose semantic paragraph breaks for a personal journal.",
            "The journal is provided as numbered sentences.",
            "Return the sentence numbers that should END paragraphs.",
            "A paragraph should contain one coherent topic, event, time period, or emotional reflection.",
            "Start a new paragraph whenever the speaker changes subject, activity, event, time period, or emotional focus.",
            "Strong transitions such as later, afterward, in the afternoon, speaking of something else, or their equivalents normally begin a new paragraph.",
            "For a journal with two or more distinct subjects, you must create two or more paragraphs.",
            "For journals with four or more sentences, prefer two to four readable paragraphs unless every sentence develops one focused thought.",
            "Use one paragraph only when the entire journal genuinely discusses one focused thought.",
            "Always include the final sentence number as the final paragraph ending.",
            "Do not rewrite, summarize, remove, reorder, or add any text.",
          ].join(" "),
        },
        { role: "user", content: numberedSentences },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "journal_paragraph_breaks",
          strict: true,
          schema: {
            type: "object",
            properties: {
              paragraphEndSentenceNumbers: {
                type: "array",
                items: { type: "integer" },
              },
            },
            required: ["paragraphEndSentenceNumbers"],
            additionalProperties: false,
          },
        },
      },
    }),
  });

  const content = result.choices?.[0]?.message?.content;
  if (!content) return body.trim();

  const requestedBreaks = JSON.parse(content).paragraphEndSentenceNumbers;
  const breaks = new Set(
    Array.isArray(requestedBreaks)
      ? requestedBreaks.filter(
          (value) => Number.isInteger(value) && value > 0 && value <= sentences.length
        )
      : []
  );
  addStrongTransitionBreaks(sentences, breaks);
  breaks.add(sentences.length);

  const paragraphs = [];
  let current = [];
  for (const [index, sentence] of sentences.entries()) {
    current.push(sentence);
    if (breaks.has(index + 1)) {
      paragraphs.push(current.join(" "));
      current = [];
    }
  }

  return paragraphs.join("\n\n").trim();
}

function addStrongTransitionBreaks(sentences, breaks) {
  const transitionPattern = /^(later\b|afterward\b|afterwards\b|subsequently\b|in the (afternoon|evening)\b|that (afternoon|evening|night)\b|后来|之后|随后|下午|晚上|그 후|나중에|오후에는|저녁에는|その後|後で|午後は|夜は|später\b|danach\b|anschließend\b|am (nachmittag|abend)\b|plus tard\b|ensuite\b|après cela\b|dans l['’](après-midi|soirée)\b|más tarde\b|después\b|posteriormente\b|por la (tarde|noche)\b)/i;

  for (let index = 1; index < sentences.length; index += 1) {
    if (transitionPattern.test(sentences[index])) {
      breaks.add(index);
    }
  }
}

function segmentSentences(body) {
  const normalized = body
    .replace(/\r\n/g, "\n")
    .replace(/\n+/g, " ")
    .replace(/[ \t]+/g, " ")
    .trim();
  if (!normalized) return [];

  const segmenter = new Intl.Segmenter(undefined, { granularity: "sentence" });
  return [...segmenter.segment(normalized)]
    .map(({ segment }) => segment.trim())
    .filter(Boolean);
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
