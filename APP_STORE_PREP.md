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
- Decide the App Store privacy answers for audio recordings, journal content, diagnostics, account data, and whether any data is linked to the user.
- Create App Store Connect app record with bundle ID `com.emmaforeststudio.FlaraDay`.
- Prepare screenshots for required iPhone sizes, subtitle, description, keywords, support URL, and privacy policy URL.
- Create an archive in Xcode and upload it to App Store Connect.
- Test the uploaded build through TestFlight before submitting for review.

## Draft submission materials

Review the files in `AppStore/`, starting with `AppStore/REVIEW_TOMORROW.md`.
