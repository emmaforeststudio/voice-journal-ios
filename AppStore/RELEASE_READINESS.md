# Flara Day Release Readiness

Last reviewed: July 24, 2026

## Release Goal

The next release is a selected-friends external TestFlight beta, not a public
App Store launch. The beta has no subscription or paywall and exposes all
current features for feedback.

## Product Snapshot

| Item | Current value |
| --- | --- |
| App name | Flara Day |
| Bundle ID | `com.emmaforeststudio.FlaraDay` |
| Version / build | `1.0` / `5` |
| Platform | iPhone only |
| Minimum OS | iOS 17 |
| Primary language | English (U.S.) |
| Primary category | Lifestyle |
| Support email | `emmaforeststudio@gmail.com` |
| Production API | `https://flara-day-backend.emmaforeststudio.workers.dev` |
| Support URL | `https://flara-day-backend.emmaforeststudio.workers.dev/support` |
| Privacy URL | `https://flara-day-backend.emmaforeststudio.workers.dev/privacy` |
| Enrollment | Individual |
| Legal / seller name | Yan Shen |

## Technical Status

- [x] Production HTTPS backend is deployed.
- [x] OpenAI transcription and journal processing work through the Worker.
- [x] Final and live-preview transcription use separate cost/quality models.
- [x] Preview and final transcription use OpenAI automatic voice-activity
  chunking within each existing API request. Long recordings additionally use
  overlapping app-side chunks with preceding-transcript continuity context.
- [x] Live preview defaults to off.
- [x] Recordings stop automatically at 30 minutes.
- [x] The beta enforces a 60-minute local daily transcription allowance.
- [x] Transcript Output defaults to Keep As Spoken and can optionally preserve
  the original while creating one Settings-selected translation.
- [x] Draft Future Letters can deliver either Original or the configured
  translated version; only the selected version is delivered.
- [x] Automatic limit stops show a processing banner explaining that captured
  audio is intact and being transcribed across journal and future-letter flows.
- [x] Active recordings continue through screen lock and normal backgrounding
  for the remainder of the same 30-minute total recording limit.
- [x] Audio interruptions and microphone-route changes stop and preserve the
  captured portion with a clear explanation.
- [x] Long recordings are transcribed in overlapping chunks before one final
  cleanup and title-generation request.
- [x] Cleanup protects minority-language writing-system spans, restores them
  after editing, normalizes Chinese/Japanese pause spacing, and preserves Korean
  word spacing. Missing protected content triggers a complete normalized-source
  fallback instead of an incomplete journal.
- [x] D1, Cron, Resend, recipient verification, and scheduled email delivery work.
- [x] In-app notification delivery and notification deep linking work.
- [x] No user account is required.
- [x] No analytics, advertising, tracking, or third-party crash SDK is included.
- [x] Support and privacy pages are deployed.
- [x] Privacy manifest describes the app's conservative data disclosures.
- [x] Export-compliance declaration is included for exempt OS-provided HTTPS.
- [x] Final targeted multilingual check passed using a newly recorded
  English-Chinese-Korean sample with Live Preview both off and on. Original
  preserved all three languages, translated output used only the selected
  language, and the compact language label displayed `Chinese`.
- [ ] Complete a final real-device regression pass on the release build.
- [ ] Complete VoiceOver, Dynamic Type, contrast, and Reduce Motion checks before
  claiming any App Store accessibility labels.

## Beta Source Snapshot - July 24, 2026

- [x] Unsigned device-targeted iOS Release build succeeded and passed Xcode's
  shallow App Store bundle validation.
- [x] All 24 Swift unit tests passed on an iPhone 17 Pro simulator.
- [x] All 17 backend journal, translation, and email tests passed.
- [x] Built app contains version `1.0` build `5`, bundle ID
  `com.emmaforeststudio.FlaraDay`, iOS 17 minimum, background audio, and only the
  production HTTPS backend URLs.
- [x] Built app and tracked source contain no OpenAI, Resend, encryption, or
  email-authentication credential values and no private-key blocks. The built
  app also contains no localhost or placeholder backend URLs.
- [x] Aqua mint source icon is 1024 by 1024 pixels with no alpha channel.
- [x] Cloudflare secret names are configured for OpenAI, Resend, sender address,
  letter encryption, and email authentication; secret values remain outside Git
  and the app bundle.
- [x] Production transcription and email health checks passed; support and
  privacy pages both returned HTTP 200.
- [x] Studio GitHub SSH remote access was verified before snapshot publication.

## Confirmed Enrollment Decision

### Seller Name

Enroll as an individual using the verified legal name `Yan Shen`. Apple displays
an individual developer's verified legal name publicly as the seller; Emma
Forest Studio remains the product and support brand. Enter the name exactly as
it appears on the identity document used for Apple verification.

### App Record Values

- Name: `Flara Day`
- Primary language: English (U.S.)
- Bundle ID: `com.emmaforeststudio.FlaraDay`
- SKU suggestion: `FLARADAY-IOS-001`
- User access: Full Access

The SKU is internal and cannot be changed after the app record is created.

## Owner Steps After Apple Membership Is Active

1. Register the explicit App ID `com.emmaforeststudio.FlaraDay` in Certificates,
   Identifiers & Profiles.
2. Create the Flara Day app record in App Store Connect before uploading a build.
3. In Xcode, select the paid development team and confirm automatic signing.
4. Confirm the app name, subtitle, category, age-rating questionnaire, privacy
   answers, support URL, and privacy URL using the drafts in this folder.
5. Archive the `VoiceJournal` scheme with the Release configuration and upload it.
6. Complete TestFlight beta information and export-compliance questions.
7. Create at least one internal testing group. Apple requires this before an
   external testing group can be created.
8. Create an external group named `Friends Beta`, add testers by email, and submit
   the first build for TestFlight Beta App Review.
9. After approval, invite only the selected testers. Do not enable a public link.

## Final Regression Gate

Test these on a physical iPhone using the uploaded TestFlight build:

- first-launch microphone, speech-recognition, notification, and Face ID prompts
- English plus mixed-language Chinese, Korean, Arabic, Spanish, French, German,
  and Japanese, including one- or two-word switches inside English sentences
- Chinese-dominant speech with natural thinking pauses and brief English names;
  confirm cleanup improves punctuation/spacing without removing the names
- short speech, silence, interrupted recording, retry, and network failure
- automatic stop at 30 minutes and the 60-minute beta daily allowance
- lock the screen and switch apps during journal, continuation, and future-letter
  recordings; continue speaking, then confirm the timer and transcription include
  the locked/background interval and the total recording still stops at 30 minutes
- incoming-call/Siri interruption and wired or Bluetooth microphone disconnection
- live preview off by default and live preview on
- record, review, edit, save, search, calendar, and journal deletion
- Keep As Spoken and Translate modes; Original/translated switching, separate
  edits, save/reopen behavior, and several beta target languages
- month recap with zero, one, and ten themes
- On This Day and Random Entry memory cards
- future-letter recording cleanup, generated title, topic-based paragraphs, draft,
  schedule, cancel/delete, in-app delivery, email verification, email delivery,
  delivered state, and notification deep link
- one original and one translated Future Letter through both in-app and email
  delivery, confirming that only the selected version arrives
- import only supported text/JSON files and export/share output
- app lock, password recovery behavior, appearance settings, Dynamic Type, and dark mode

## Not Part Of This Beta

- StoreKit subscription or paywall
- public App Store release
- app accounts or cloud journal sync
- custom analytics or crash-reporting SDK
- direct Word or native Apple Notes import; selectable-text PDFs are supported
- public multi-user feature-request service
- iOS 15 or 16 compatibility; minimum deployment remains iOS 17

## Later Public-Launch Work

- implement and validate the one-week no-commitment voice trial
- implement StoreKit Plus subscription status and restore purchases
- replace the beta's local 60-minute counter with backend-enforced 30 daily voice
  minutes and the future monthly allowance
- gate live preview and future-letter email behind Plus
- add subscription terms and update privacy/metadata before public review
- collect polished App Store screenshots and submit the public version for review
