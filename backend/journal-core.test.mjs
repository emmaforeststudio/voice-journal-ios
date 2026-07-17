import assert from "node:assert/strict";
import test from "node:test";
import { createJournalHandler, preserveOriginalScriptText } from "./journal-core.mjs";

const mixedTranscript = "Today 我很开心 그리고 mañana je vais bien.";

function audioRequest(path, fields = {}) {
  const form = new FormData();
  for (const [name, value] of Object.entries(fields)) {
    form.append(name, value);
  }
  form.append("audio", new Blob([new Uint8Array(2_048).fill(7)], { type: "audio/wav" }), "test.wav");
  return new Request(`https://example.com/${path}`, { method: "POST", body: form });
}

test("preview sends direct audio with the multilingual transcription prompt", async () => {
  let inspected = false;
  const handler = createJournalHandler({
    apiKey: "test-key",
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://api.openai.com/v1/audio/transcriptions");
      assert.equal(options.method, "POST");
      assert.equal(options.body.get("model"), "gpt-4o-transcribe");
      assert.equal(options.body.get("response_format"), "json");
      assert.match(options.body.get("prompt"), /English, Chinese, Korean, Spanish, French, German, and Japanese/);
      assert.match(options.body.get("prompt"), /Do not translate mixed-language speech/);
      assert.match(options.body.get("prompt"), /one or two words/);
      assert.match(options.body.get("prompt"), /괜찮아요/);
      assert.ok(options.body.get("file") instanceof Blob);
      inspected = true;
      return Response.json({ text: mixedTranscript });
    },
  });

  const response = await handler(audioRequest("preview"));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).transcript, mixedTranscript);
  assert.equal(inspected, true);
});

test("cleanup cannot remove short Chinese or Korean fragments from a transcript", () => {
  const transcript = "Today 我很开心 그리고 괜찮아요 before work.";
  assert.equal(
    preserveOriginalScriptText("Today I was happy before work.", transcript),
    transcript
  );
  assert.equal(
    preserveOriginalScriptText("Today 我很开心 그리고 괜찮아요 before work.", transcript),
    transcript
  );
});

test("journal completion preserves mixed-language text through transcription and cleanup", async () => {
  let call = 0;
  const handler = createJournalHandler({
    apiKey: "test-key",
    fetchImpl: async (url, options) => {
      call += 1;
      if (call === 1) {
        assert.equal(url, "https://api.openai.com/v1/audio/transcriptions");
        return Response.json({ text: mixedTranscript });
      }

      assert.equal(url, "https://api.openai.com/v1/chat/completions");
      const body = JSON.parse(options.body);
      assert.equal(body.model, "gpt-4o-mini");
      assert.match(body.messages[0].content, /Never translate, romanize, or replace mixed-language phrases/);
      assert.match(body.messages[1].content, new RegExp(mixedTranscript.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
      return Response.json({
        choices: [{
          message: {
            content: JSON.stringify({
              title: "A Multilingual Day",
              body: mixedTranscript,
              emoji: "😊",
              language: "english",
            }),
          },
        }],
      });
    },
  });

  const response = await handler(audioRequest("journal", { livePreviewTranscript: mixedTranscript }));
  assert.equal(response.status, 200);
  const journal = await response.json();
  assert.equal(journal.body, mixedTranscript);
  assert.equal(journal.language, "english");
  assert.equal(call, 2);
});
