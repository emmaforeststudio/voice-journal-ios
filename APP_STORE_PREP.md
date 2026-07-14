# Flara Day App Store Prep

## Done in the project

- App display name is set to `Flara Day`.
- The active app icon is the Aqua mint icon.
- Version is `1.0` and build number is `1`.
- Microphone, speech recognition, Face ID, and local network permission strings are present.
- `PrivacyInfo.xcprivacy` is included for app-owned `UserDefaults` usage.
- Debug and Release now use separate `VOICE_JOURNAL_BACKEND_URL` build settings.

## Must finish before App Store upload

- Monitor the Cloudflare Worker after real-device testing to confirm Free plan limits are enough.
- Create App Store Connect app record with bundle ID `com.emmaforeststudio.FlaraDay`.
- Capture final App Store screenshots.
- Create an archive in Xcode and upload it to App Store Connect.
- Test the uploaded build through TestFlight before submitting for review.

## Draft submission materials

Review the files in `AppStore/`, starting with `AppStore/REVIEW_TOMORROW.md`.

## Ready before Apple Developer payment

- App bundle ID is already set to `com.emmaforeststudio.FlaraDay`.
- App Store metadata draft is ready.
- App privacy answer draft is ready for a no-account, no-subscription, no-analytics version 1.0.
- Support and privacy pages are deployed.
- Backend is deployed on the studio Cloudflare account.
- D1, Cron delivery, encrypted future-letter storage, and the iOS email flow are implemented.
- Resend remains disabled until a studio Resend account, verified sender domain, and API key are configured.
- Source code is pushed to the studio GitHub repository.

## Beta product decision

- The selected friends beta has no subscriptions or paywall.
- Voice transcription and future-letter email are unlocked for beta feedback after the email provider is configured.
- The later public version will use one Plus tier.
- The preferred public voice trial is a one-week no-commitment trial, with no advance subscription authorization. Trial enforcement and StoreKit access will be designed after the beta limit is chosen.

## Blocked until Apple Developer payment

- Register the bundle ID with Apple.
- Create the App Store Connect app record.
- Generate signing/provisioning for real App Store distribution.
- Upload an archive to TestFlight.
