# Future-Letter Email Operations

Last reviewed: July 16, 2026

The original Resend setup is complete. This document is now an operating and
release checklist rather than an installation checklist.

## Current Configuration

- Resend account: studio account
- Verified sending domain: `letters.emmaforeststudio.com`
- Cloudflare Worker: `flara-day-backend`
- D1 database: configured
- Cron delivery: configured
- Pending letter encryption: configured
- Recipient verification: configured
- `/v1/email-health`: database and provider configured
- Real scheduled email delivery: tested

Never place Resend, OpenAI, encryption, or device-authentication secrets in the
repository, app binary, screenshots, support email, or chat.

## Before Each Beta Build

- [ ] Open `/v1/email-health` and confirm both configuration values are true.
- [ ] Request a verification code to a test address.
- [ ] Verify the address in the app.
- [ ] Schedule one email several minutes in the future.
- [ ] Confirm the email includes title, body, and the date the letter was written.
- [ ] Confirm the app moves the letter from Scheduled to Delivered.
- [ ] Delete a second pending letter and confirm it is not delivered.

## Monitoring

- Watch Resend sent, delivered, bounced, and failed events.
- Watch Resend's current daily and monthly plan allowances.
- Watch Cloudflare Worker error and CPU-limit metrics.
- Watch D1 reads, writes, and storage.
- Check Cron invocations when a scheduled letter is late.
- Treat repeated `exceededCpu` / error `1102` as a signal to optimize the batch or
  move the Worker to a paid CPU allocation.

## Secret Rotation

When rotating a secret, update it with `wrangler secret put`, redeploy the
Worker, run the health check, and complete one verification and delivery test.
Rotating the pending-letter encryption key requires a migration plan for letters
already encrypted with the old key.

## Beta Access

Email delivery is free to selected beta testers. It is intended to become a Plus
feature for the public version, but no entitlement enforcement exists yet.
