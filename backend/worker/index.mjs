import { createJournalHandler } from "../journal-core.mjs";
import { privacyPolicyHtml, supportHtml } from "./public-pages.mjs";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/support") {
      return htmlResponse(supportHtml);
    }

    if (request.method === "GET" && url.pathname === "/privacy") {
      return htmlResponse(privacyPolicyHtml);
    }

    const handleJournalRequest = createJournalHandler({
      apiKey: env.OPENAI_API_KEY,
      fetchImpl: fetch,
    });
    return handleJournalRequest(request);
  },
};

function htmlResponse(html) {
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
    },
  });
}
