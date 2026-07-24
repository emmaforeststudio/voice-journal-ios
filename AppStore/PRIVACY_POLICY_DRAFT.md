# Flara Day Privacy Policy

Effective date: July 16, 2026

Flara Day is a voice and typed journal that helps you record, transcribe, and
reflect on journal entries. This policy explains what information is processed,
why it is processed, and the choices you have.

## Information Flara Day Processes

### Journals And Local App Data

Flara Day stores saved journal text, titles, dates, mood indicators, insights,
future letters for in-app delivery, feature-board data, and app preferences on
your iPhone. This information stays on the device unless you use a cloud feature
or choose to export it.

### Audio And Journal Text

When you record, the app creates a temporary audio file. For cloud transcription
and journal drafting, audio and resulting text are sent to Flara Day's backend
and OpenAI. Optional live-preview chunks are sent only when Live Preview is
enabled. Flara Day does not intentionally retain uploaded audio on its backend
after processing finishes.

When you explicitly start recording, microphone capture can continue while the
iPhone is locked or Flara Day is in the background. It ends when you stop, when
the 30-minute recording limit is reached, or when the session is interrupted.

Journal text may be sent for cleanup, paragraph organization, language
preservation, and title or mood generation. Generated results are returned to
the app for your review before saving.

If you choose translated transcript output, a journal or draft-letter title and
text are sent through Flara Day's backend to OpenAI to create one version in the
language selected in Settings. The original version is preserved in the app.

### Future Letters And Email Addresses

Future letters scheduled for in-app notification remain on your iPhone. If you
choose Email, Flara Day processes the recipient email address, verification
code, letter title and body, delivery time, time zone, and an app-generated
random device identifier used to manage the letter without an account.

### Settings And Device Security

Theme, font, font size, lock, memory-card, and live-preview preferences are
stored on your device. Face ID is handled by Apple; Flara Day does not receive or
store your biometric data. An app-generated credential used for future-letter
email management is stored in the iOS Keychain.

### Imports And Exports

Flara Day processes only files you explicitly select. The current importer
supports compatible text, UTF-8 text, JSON, RTF, HTML, and PDFs containing
selectable text. Scanned image PDFs require OCR first. Word files are not
imported directly, and Apple Notes must first be exported or shared as a
supported file. Exported files are created only when you choose Export Journals.

## How Information Is Used

Flara Day uses information to:

- record and transcribe voice journals
- create and organize journal drafts and titles
- display search, calendar, memory, and Month Recap features
- provide optional live transcription preview
- provide optional journal and Future Letter translation
- maintain app preferences and local security settings
- import, export, edit, and delete data at your direction
- verify an email recipient and deliver a scheduled future letter

Flara Day does not sell journal content or use it for advertising.

## Service Providers

Cloud features may use:

- Cloudflare Workers for the Flara Day backend
- Cloudflare D1 for encrypted pending email letters and delivery state
- OpenAI for transcription and text processing
- Resend for verification codes and future-letter email delivery

These providers process information as needed to deliver their services and
under their own terms and privacy commitments.

## Data Retention

Saved journals and local settings remain on your iPhone until you delete them,
delete all app data, or remove the app and its data.

Temporary audio is used to create transcription and drafts. Flara Day does not
intentionally store uploaded audio on its backend after a processing request.
Cloud providers may retain request information under their own service terms.

For email delivery, the full recipient address and letter are encrypted while
waiting in Cloudflare D1. After successful delivery or permanent failure, full
content is replaced with status-only data. Canceling or deleting a pending
letter removes its remote record. Verification requests expire; limited hashed
verification and delivery records may be retained for security, rate limiting,
and reliability.

Technical service logs may contain request timing, status, and error metadata.
The service is designed not to log raw audio, full journal or letter content,
verification codes, or device secrets.

## Your Choices And Deletion

You can:

- edit or delete individual journal entries
- cancel or delete pending future letters
- turn Live Preview off in Settings
- use typed journaling without cloud transcription
- export journals
- use Delete All App Data in Settings

Deleting all app data clears Flara Day's local journals, settings, and device
credential and requests deletion of associated pending email-letter data. It
cannot recall an email already delivered or require a provider to erase data it
must retain under its own legal obligations.

## Sharing, Tracking, And Analytics

Flara Day shares information only with the service providers needed for the
feature you choose. Flara Day does not track you across other companies' apps or
websites and does not include advertising or custom analytics SDKs.

## Children

Flara Day is not directed to children under 13. Apple's App Store age rating is
a separate content rating generated from Apple's questionnaire.

## Security

Flara Day uses HTTPS, encrypted pending-letter storage, iOS Keychain credentials,
and optional local Face ID or password protection. No transmission or storage
method is completely secure.

## Changes

This policy may be updated as Flara Day changes. The current version will be
posted with its effective date.

## Contact

For privacy questions, deletion help, or support, email
`emmaforeststudio@gmail.com`.
