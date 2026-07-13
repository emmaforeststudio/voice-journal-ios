# TestFlight Upload Checklist

## Before Archive

- Confirm Cloudflare Worker health endpoint works:
  `https://flara-day-backend.emmaforeststudio.workers.dev/health`
- Confirm real iPhone recording works on Wi-Fi.
- Confirm real iPhone recording works on cellular if possible.
- Confirm live preview works or fails gracefully.
- Confirm final journal generation works.
- Confirm Settings > Connection shows backend connected.
- Confirm privacy policy/support URLs are finalized.
- Increase build number if uploading another build.

## Xcode Archive

1. Open `VoiceJournal.xcodeproj`.
2. Select the `VoiceJournal` scheme.
3. Select `Any iOS Device` or a connected device.
4. Product > Archive.
5. In Organizer, select the archive.
6. Validate App.
7. Distribute App > App Store Connect > Upload.

## App Store Connect

1. Create app record.
2. Use bundle ID: `com.emmaforeststudio.FlaraDay`.
3. Add app name: `Flara Day`.
4. Add subtitle, description, keywords, support URL, privacy policy URL.
5. Complete App Privacy answers.
6. Add screenshots.
7. Add uploaded build to TestFlight.
8. Test the TestFlight build before submitting for review.

## Review Notes

Include a short note explaining that Flara Day uses cloud AI transcription and journal draft cleanup through the backend.
