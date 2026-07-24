# Flara Day App Store Preparation

Last reviewed: July 24, 2026

This is the short project-level status. The operational checklist is in
`AppStore/RELEASE_READINESS.md`.

## Current Build

- Product name: `Flara Day`
- Bundle ID: `com.emmaforeststudio.FlaraDay`
- Version: `1.0`
- Build: `5`
- Platform: iPhone only
- Minimum iOS version: iOS 17
- iOS 15 and 16 compatibility is deferred; the beta keeps SwiftData and the
  current iOS 17 navigation and UI architecture.
- Active icon: Aqua mint
- Production backend: `https://flara-day-backend.emmaforeststudio.workers.dev`
- Support URL: `https://flara-day-backend.emmaforeststudio.workers.dev/support`
- Privacy URL: `https://flara-day-backend.emmaforeststudio.workers.dev/privacy`

## Ready In The Project

- Cloudflare Worker transcription and journal processing are deployed.
- Final transcription uses `gpt-4o-transcribe`; optional live preview uses
  `gpt-4o-mini-transcribe`; cleanup and title generation use `gpt-4o-mini`.
- Preview and final transcription requests use OpenAI automatic voice-activity
  chunking. This VAD behavior runs inside each existing transcription request;
  it does not create an additional request. For long recordings, Flara Day also
  uses overlapping app-side audio chunks and continuity context between chunks.
- Journal cleanup protects short language switches before AI editing, restores
  them afterward, and falls back to the complete locally normalized transcript
  if protected content is ever omitted. Chinese and Japanese pause spacing is
  normalized while meaningful Korean and Latin word spacing is preserved.
- Live preview is off by default.
- A single voice recording can run for up to 30 minutes. The selected-friends
  beta permits up to 60 transcribed voice minutes per calendar day on-device.
- When either automatic voice limit stops a recording, the app explains why it
  stopped and reassures the user that captured audio is being transcribed.
- Active recordings continue when the iPhone locks or Flara Day moves to the
  background, for the remainder of the same 30-minute per-recording limit.
  Screen lock does not create a shorter limit. Background microphone use ends
  as soon as recording stops or the limit is reached.
- Longer recordings are uploaded in smaller overlapping transcription chunks,
  then cleaned and titled as one journal.
- Cloudflare D1, Cron, Resend, email verification, and scheduled future-letter
  delivery are configured and have been tested.
- In-app future letters use local notifications and open the delivered letter.
- App-owned privacy manifest and permission descriptions are included.
- Debug and Release both use the production Cloudflare Worker so Xcode-installed
  iPhone builds do not depend on a local Mac server.
- Draft metadata, privacy answers, support copy, screenshot plan, and TestFlight
  checklist are in `AppStore/`.
- The final multilingual beta check passed with a new English-Chinese-Korean
  recording: Original preserved all three languages, translated output stayed
  in the selected language, the compact tab displayed `Chinese` without
  truncation, and both Live Preview off and on paths worked.

## Selected-Friends Beta Decision

- No subscription, payment, or paywall is active in the beta.
- All current features are available to testers.
- The beta allows up to 30 minutes per recording and 60 transcribed voice
  minutes per user per calendar day.
- Typed journals and in-app future letters are intended to remain free later.
- The intended public version uses a one-week no-commitment voice trial,
  followed by one Plus tier.
- The intended voice limit is 30 transcribed minutes per user per calendar day.
- Live preview and future-letter email are intended Plus features after beta.
- Price and monthly Plus allowance remain undecided.
- See `AppStore/PRODUCT_ACCESS_PLAN.md`.

## Apple Enrollment Decision

- Enrollment type: Individual
- Legal name and public seller name: `Yan Shen`
- Explicit App ID to register: `com.emmaforeststudio.FlaraDay`

Apple will display the individual account holder's verified legal name as the
seller. The Emma Forest Studio name can still be used in the app's branding,
support email, domain, and marketing.

## Blocking Owner Actions

Distribution cannot begin until the Apple Developer Program membership is
active. After enrollment, register the bundle ID, create the App Store Connect
record, confirm signing, upload an archive, and invite the selected external
testers through TestFlight.

Do not submit the app for public App Review yet. The first release goal is an
email-invitation-only external TestFlight beta.
