# Before Apple Developer Enrollment

Last reviewed: July 17, 2026

## Already Prepared

- App name: `Flara Day`
- Bundle ID: `com.emmaforeststudio.FlaraDay`
- Version / build: `1.0` / `5`
- GitHub: `https://github.com/emmaforeststudio/voice-journal-ios`
- Backend: `https://flara-day-backend.emmaforeststudio.workers.dev`
- Support and privacy URLs: deployed
- Support email: `emmaforeststudio@gmail.com`
- Privacy effective date: July 16, 2026
- Resend, D1, Cron, email verification, and scheduled delivery: configured
- Enrollment type: Individual
- Legal / seller name: `Yan Shen`

## Useful Work Before Paying

- Run the real-device regression list in `RELEASE_READINESS.md`.
- Test mixed-language speech, including short Chinese and Korean phrases inside
  English sentences.
- Test Wi-Fi, cellular, airplane mode, and interrupted requests.
- Test live preview off and on.
- Test in-app and email future letters, cancellation, deletion, and deep linking.
- Test export and only the import formats currently supported.
- Test app lock, appearance settings, dark mode, VoiceOver, and Dynamic Type.
- Watch OpenAI, Cloudflare, and Resend usage.
- Confirm the Apple Account's legal name matches `Yan Shen` exactly as shown on
  the identity document used for enrollment.

## Keep Out Of The Selected-Friends Beta

- subscriptions and StoreKit paywalls
- user accounts and cloud journal sync
- third-party analytics or crash reporting
- direct Word and native Apple Notes import claims; selectable-text PDFs are
  supported

## What Payment Unlocks

Apple Developer Program membership is required to create the distribution App ID,
create the App Store Connect app record, sign an App Store archive, upload it,
and distribute it through TestFlight.

After activation, follow `TESTFLIGHT_UPLOAD_CHECKLIST.md`.
