# Resend Setup Checklist

The Cloudflare Worker, D1 database, Cron trigger, encryption key, and device-authentication secret are already deployed. Complete this checklist to turn on real email delivery.

## Emma's steps

1. Create a Resend account with `emmaforeststudio@gmail.com`.
2. Choose a studio domain to use for Flara Day email. Resend requires a domain you own; it cannot verify a shared Gmail address.
3. In Resend, add the domain. A sending subdomain such as `letters.yourdomain.com` is preferable because it isolates email reputation.
4. Add the SPF and DKIM records shown by Resend to the domain's DNS settings.
5. Wait until Resend shows the domain as **Verified**.
6. Create a Resend API key with sending permission.
7. Decide the sender address, for example `Flara Day <letters@letters.yourdomain.com>`.

Do not paste the API key into chat, a source file, GitHub, or a screenshot.

## Codex steps after verification

1. Open an interactive terminal prompt for `wrangler secret put RESEND_API_KEY` so Emma can enter the key privately.
2. Store the sender with `wrangler secret put RESEND_FROM_EMAIL`.
3. Redeploy `flara-day-backend`.
4. Confirm `/v1/email-health` reports `providerConfigured: true`.
5. Install the new app build on the iPhone.
6. Verify a test recipient address.
7. Schedule one letter several minutes ahead.
8. Confirm it moves from Scheduled Letters to Delivered Letters and that its full content has been scrubbed from D1 after sending.
9. Test cancellation by deleting a second scheduled letter before its delivery time.

## Free-plan monitoring

- Resend Free currently has a daily sending limit, so each verification code and each delivered letter counts toward the allowance.
- Cloudflare Workers Free allows 10 ms of CPU time per Cron invocation. The Worker handles at most three due letters per minute to keep early beta work small.
- In Cloudflare, watch **Workers & Pages > flara-day-backend > Metrics > Errors > Invocation Statuses** for `exceededCpu` or error `1102`.
- In D1, watch row reads, row writes, and storage under the `flara-day-email` database metrics.
- If CPU errors appear consistently, the straightforward fix is moving the Worker to Cloudflare Workers Paid; D1 and the app protocol do not need to be redesigned.
