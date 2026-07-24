# Flara Day TestFlight Checklist

Last reviewed: July 24, 2026

## 1. Apple Account And App Record - Owner

- [ ] Activate Apple Developer Program membership.
- [x] Enrollment decision: Individual, using legal seller name `Yan Shen`.
- [ ] Register explicit App ID `com.emmaforeststudio.FlaraDay`.
- [ ] Create the App Store Connect record before uploading.
- [ ] Use app name `Flara Day`, primary language English (U.S.), and suggested SKU
  `FLARADAY-IOS-001`.
- [ ] Select Lifestyle as the primary category.

## 2. Release Build Gate

- [x] Confirm Worker `/health` and `/v1/email-health` both report healthy.
- [x] Confirm support and privacy URLs load without authentication.
- [ ] Run the regression list in `RELEASE_READINESS.md` on a physical iPhone.
- [x] Confirm Release points to the production Worker, not localhost.
- [x] Confirm no API keys or service secrets are present in the app bundle.
- [ ] Confirm one recording stops at 30 minutes and the beta daily allowance is
  60 transcribed minutes.
- [ ] Confirm recording continues after screen lock and app switching for the
  remainder of the same 30-minute total limit. Confirm locked/background speech
  is transcribed and interruptions or microphone-route changes stop cleanly.
- [x] Confirm a new English-Chinese-Korean recording preserves all three
  languages in Original, produces selected-language-only translated output,
  displays `Chinese` without tab truncation, and works with Live Preview off and
  on.
- [ ] Confirm Arabic and other beta languages preserve short switches in their
  original scripts instead of translating them to English.
- [ ] Confirm a Chinese-dominant recording with thinking pauses is punctuated
  and spaced naturally while brief English names and Korean word spacing remain
  intact.
- [ ] Confirm a recorded future letter receives a generated title and separates
  distinct life topics into readable paragraphs while preserving the original meaning.
- [x] Confirm Aqua mint icon is 1024 by 1024 pixels with no transparency.
- [x] Run an unsigned device-targeted Release build and Xcode bundle validation.
- [x] Pass all 24 Swift tests and all 17 backend tests.
- [ ] Keep version `1.0`; use build `5` if it has never been uploaded. Increase the
  build number before every replacement upload.

## 3. Archive And Upload - Codex Can Assist

1. Open `VoiceJournal.xcodeproj`.
2. Select the paid Apple development team and enable automatic signing.
3. Select the `VoiceJournal` scheme and `Any iOS Device (arm64)`.
4. Choose Product > Archive.
5. In Organizer, choose Validate App.
6. Choose Distribute App > App Store Connect > Upload.
7. Wait for Apple to process the build before opening TestFlight.

## 4. TestFlight Information - Owner

- [ ] Beta App Description: use `APP_STORE_METADATA_DRAFT.md`.
- [ ] What to Test: use the draft in the same file.
- [ ] Feedback email: `emmaforeststudio@gmail.com`.
- [ ] Export compliance: confirm the app uses only exempt encryption supplied by
  Apple's operating system, such as HTTPS through URLSession. The project declares
  `ITSAppUsesNonExemptEncryption = NO`; answer consistently after legal review.
- [ ] App Review contact: provide the owner's reachable name, phone, and email.
- [ ] Demo account: not required because Flara Day has no login.
- [ ] Beta App Review note: background audio is used only while a tester has
  explicitly started a journal or future-letter recording. It allows recording
  to continue through screen lock for up to 30 total minutes; the audio session
  ends immediately on stop or when the limit is reached.

## 5. Internal Then External Beta - Owner

- [ ] Create at least one internal TestFlight group first.
- [ ] Install and test the uploaded build yourself.
- [ ] Create an external group named `Friends Beta`.
- [ ] Add selected testers by email; do not enable a public invitation link.
- [ ] Add the build and submit it for TestFlight Beta App Review.
- [ ] After approval, send invitations and monitor feedback.

Apple permits up to 100 internal testers and up to 10,000 external testers. A
TestFlight build is testable for up to 90 days. The first external build normally
requires Beta App Review.

## 6. During The Beta

- [ ] Watch OpenAI usage and cost.
- [ ] Watch Cloudflare Worker errors, CPU-limit events, and D1 usage.
- [ ] Watch Resend delivery, bounce, and daily allowance metrics.
- [ ] Record tester device/iOS version and reproduction steps for each problem.
- [ ] Do not collect or request private journal content unless a tester knowingly
  chooses to share it.
- [ ] Update the build number for every new beta upload.

## 7. Public App Store Submission - Later

Do not complete public submission until beta findings, subscription decisions,
screenshots, accessibility checks, privacy answers, and public pricing are final.
