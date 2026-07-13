const maxBodyBytes = 20 * 1024 * 1024;
const previewSessionTTL = 30 * 60 * 1000;

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

export function createJournalHandler({ apiKey, previewSessions = null, fetchImpl = fetch } = {}) {
  return async function handleJournalRequest(request) {
    try {
      const url = new URL(request.url);

      if (request.method === "GET" && url.pathname === "/health") {
        return jsonResponse(200, {
          status: "ok",
          openAIConfigured: Boolean(apiKey),
        });
      }

      if (request.method !== "POST" || !["/journal", "/preview"].includes(url.pathname)) {
        return jsonResponse(404, { error: "Not found" });
      }

      if (!apiKey) {
        return jsonResponse(503, {
          error: "OPENAI_API_KEY is missing from the backend environment.",
        });
      }

      const { audio, metadata } = await readJournalUpload(request);
      if (audio.byteLength === 0) {
        return jsonResponse(400, { error: "Audio is required" });
      }

      if (url.pathname === "/preview") {
        const transcript = await transcribe(audio, { apiKey, fetchImpl, allowEmpty: true });
        if (!metadata.sessionId || !previewSessions) {
          return jsonResponse(200, { transcript, chunkTranscript: transcript });
        }

        cleanupPreviewSessions(previewSessions);
        const session = previewSessions.get(metadata.sessionId) || { transcript: "" };
        const mergedTranscript = mergePreviewTranscript(session.transcript, transcript);
        previewSessions.set(metadata.sessionId, {
          transcript: mergedTranscript,
          updatedAt: Date.now(),
        });
        return jsonResponse(200, {
          transcript: mergedTranscript,
          chunkTranscript: transcript,
        });
      }

      const transcript = await transcribe(audio, { apiKey, fetchImpl });
      const journal = await polishJournal(transcript, metadata.livePreviewTranscript, {
        apiKey,
        fetchImpl,
      });
      try {
        journal.body = await structureJournalBody(journal.body, { apiKey, fetchImpl });
      } catch (error) {
        console.error("Paragraph structuring failed; returning the complete polished journal.", error);
      }

      return jsonResponse(200, { transcript, ...journal });
    } catch (error) {
      console.error(error);
      return jsonResponse(500, {
        error: error instanceof Error ? error.message : "Unexpected server error",
      });
    }
  };
}

async function readJournalUpload(request) {
  const contentType = request.headers.get("content-type") || "";
  if (contentType.toLowerCase().includes("multipart/form-data")) {
    const form = await request.formData();
    const audioPart = form.get("audio") || form.get("file");
    if (!audioPart || typeof audioPart === "string") {
      return { audio: new Uint8Array(), metadata: formMetadata(form) };
    }

    if (audioPart.size > maxBodyBytes) {
      throw new Error("Recording is too large for the backend.");
    }

    return {
      audio: new Uint8Array(await audioPart.arrayBuffer()),
      metadata: formMetadata(form),
    };
  }

  const body = await request.json();
  const audio = decodeBase64(body.audioBase64 || "");
  if (audio.byteLength > maxBodyBytes) {
    throw new Error("Recording is too large for the backend.");
  }

  return {
    audio,
    metadata: {
      livePreviewTranscript: stringValue(body.livePreviewTranscript),
      sessionId: stringValue(body.sessionId),
      sequence: stringValue(body.sequence),
      chunkStartTime: stringValue(body.chunkStartTime),
      chunkEndTime: stringValue(body.chunkEndTime),
    },
  };
}

function formMetadata(form) {
  return {
    livePreviewTranscript: formString(form, "livePreviewTranscript"),
    sessionId: formString(form, "sessionId"),
    sequence: formString(form, "sequence"),
    chunkStartTime: formString(form, "chunkStartTime"),
    chunkEndTime: formString(form, "chunkEndTime"),
  };
}

function formString(form, key) {
  const value = form.get(key);
  return typeof value === "string" ? value : "";
}

function stringValue(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

function decodeBase64(value) {
  if (!value) return new Uint8Array();
  if (typeof Buffer !== "undefined") {
    return new Uint8Array(Buffer.from(value, "base64"));
  }

  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function transcribe(audio, { apiKey, fetchImpl, allowEmpty = false }) {
  const form = new FormData();
  form.append("model", "gpt-4o-mini-transcribe");
  form.append("response_format", "json");
  form.append(
    "prompt",
    [
      "This is a personal journal entry.",
      "The speaker may code-switch or mix languages within the same sentence.",
      "Transcribe exactly what is spoken, preserving each language in its original script when clear.",
      "Do not translate mixed-language speech into one language.",
      "Preserve proper nouns, app names, and informal wording accurately.",
    ].join(" ")
  );
  form.append("file", new Blob([audio], { type: "audio/wav" }), "journal.wav");

  const result = await openAIRequest("/v1/audio/transcriptions", {
    apiKey,
    fetchImpl,
    method: "POST",
    body: form,
  });

  if (!result.text?.trim()) {
    if (allowEmpty) return "";
    throw new Error("OpenAI did not detect speech in the recording.");
  }

  return result.text.trim();
}

function cleanupPreviewSessions(previewSessions) {
  const now = Date.now();
  for (const [sessionId, session] of previewSessions) {
    if (now - session.updatedAt > previewSessionTTL) {
      previewSessions.delete(sessionId);
    }
  }
}

function mergePreviewTranscript(existing, next) {
  const previous = typeof existing === "string" ? existing.trim() : "";
  const incoming = typeof next === "string" ? next.trim() : "";
  if (!incoming) return previous;
  if (!previous) return incoming;
  if (previous.includes(incoming)) return previous;

  const wordMergeIndex = overlappingWordMergeIndex(previous, incoming);
  if (wordMergeIndex > 0) {
    return joinTranscriptParts(previous, incoming.slice(wordMergeIndex));
  }

  const charMergeIndex = overlappingCharacterMergeIndex(previous, incoming);
  if (charMergeIndex > 0) {
    return joinTranscriptParts(previous, incoming.slice(charMergeIndex));
  }

  return joinTranscriptParts(previous, incoming);
}

function overlappingWordMergeIndex(previous, incoming) {
  const previousWords = wordSpans(previous);
  const incomingWords = wordSpans(incoming);
  const maxOverlap = Math.min(20, previousWords.length, incomingWords.length);

  for (let count = maxOverlap; count > 0; count -= 1) {
    const previousSlice = previousWords.slice(previousWords.length - count).map(({ text }) => text);
    const incomingSlice = incomingWords.slice(0, count).map(({ text }) => text);
    if (previousSlice.every((word, index) => word === incomingSlice[index])) {
      return incomingWords[count - 1].end;
    }
  }

  return 0;
}

function overlappingCharacterMergeIndex(previous, incoming) {
  const previousTail = previous.slice(-120);
  const incomingHead = incoming.slice(0, 120);
  const maxOverlap = Math.min(previousTail.length, incomingHead.length);

  for (let count = maxOverlap; count >= 8; count -= 1) {
    if (normalizeText(previousTail.slice(-count)) === normalizeText(incomingHead.slice(0, count))) {
      return count;
    }
  }

  return 0;
}

function wordSpans(text) {
  const spans = [];
  const pattern = /[\p{L}\p{N}]+/gu;
  let match;
  while ((match = pattern.exec(text))) {
    spans.push({
      text: normalizeText(match[0]),
      start: match.index,
      end: match.index + match[0].length,
    });
  }
  return spans;
}

function normalizeText(text) {
  return text
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "")
    .trim();
}

function joinTranscriptParts(previous, incoming) {
  const next = incoming.trim();
  if (!next) return previous.trim();
  const separator = /[\s"'([{]$/.test(previous) || /^[\s.,!?;:'")\]}]/.test(next) ? "" : " ";
  return `${previous.trim()}${separator}${next}`.trim();
}

async function polishJournal(transcript, livePreviewTranscript = "", { apiKey, fetchImpl }) {
  const preview = typeof livePreviewTranscript === "string"
    ? livePreviewTranscript.trim()
    : "";
  const result = await openAIRequest("/v1/chat/completions", {
    apiKey,
    fetchImpl,
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
            "Use the language field for the dominant language only.",
            "The journal body must preserve intentional code-switching and mixed-language wording from the transcript.",
            "Do not translate phrases into the dominant language when the speaker originally used another language.",
            "Write the title in the dominant language's natural script.",
            "Only use an English title when the primary language is english.",
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

async function structureJournalBody(body, { apiKey, fetchImpl }) {
  const sentences = segmentSentences(body);
  if (sentences.length < 2) return body.trim();

  const numberedSentences = sentences
    .map((sentence, index) => `${index + 1}. ${sentence}`)
    .join("\n");
  const result = await openAIRequest("/v1/chat/completions", {
    apiKey,
    fetchImpl,
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

async function openAIRequest(path, { apiKey, fetchImpl, ...options }) {
  const response = await fetchImpl(`https://api.openai.com${path}`, {
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

function jsonResponse(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
