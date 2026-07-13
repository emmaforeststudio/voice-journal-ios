# Waiting To Pay Checklist

Use this while delaying Apple Developer Program payment.

## Already Prepared

- App name: `Flara Day`
- Bundle ID in Xcode: `com.emmaforeststudio.FlaraDay`
- GitHub repo: `https://github.com/emmaforeststudio/voice-journal-ios`
- Backend: `https://flara-day-backend.emmaforeststudio.workers.dev`
- Support URL: `https://flara-day-backend.emmaforeststudio.workers.dev/support`
- Privacy Policy URL: `https://flara-day-backend.emmaforeststudio.workers.dev/privacy`
- Support email: `emmaforeststudio@gmail.com`
- Privacy effective date: `July 13, 2026`

## Keep Testing Before Paying

- Record short English and Chinese entries on iPhone.
- Test live preview on Wi-Fi.
- Test live preview on cellular.
- Test final journal generation.
- Test export/import.
- Test Face ID/password lock.
- Check Settings > Connection.
- Watch Cloudflare usage for request failures or quota concerns.

## Do Not Add Before First TestFlight Unless Needed

- User accounts
- Subscriptions
- Third-party analytics
- Crash reporting SDKs
- Support request forms
- Cloud sync

These can be added later, but each one makes App Store privacy answers, testing, and review more complex.

## After Paying Apple Developer

1. Register bundle ID: `com.emmaforeststudio.FlaraDay`.
2. Create App Store Connect app record for `Flara Day`.
3. Confirm Xcode signing with the paid Apple Developer team.
4. Run the app on your iPhone from Xcode.
5. Archive and upload build `1`.
6. Add yourself to TestFlight first.
7. Invite a small Friends Beta group.
8. Capture final screenshots from the stable build.
