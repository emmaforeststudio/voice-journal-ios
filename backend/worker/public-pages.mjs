const supportEmail = "emmaforeststudio@gmail.com";

const pageStyles = `
  :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #24302d; background: #edf8f4; }
  body { margin: 0; padding: 40px 20px; }
  main { max-width: 760px; margin: 0 auto; background: rgba(255, 255, 255, 0.76); border: 1px solid rgba(84, 133, 121, 0.18); border-radius: 8px; padding: 32px; box-shadow: 0 20px 60px rgba(70, 102, 96, 0.12); }
  h1 { margin: 0 0 8px; font-size: 34px; line-height: 1.1; }
  h2 { margin: 28px 0 8px; font-size: 20px; }
  p, li { font-size: 16px; line-height: 1.65; }
  a { color: #397f74; font-weight: 650; }
  .muted { color: #69736f; }
`;

export const supportHtml = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Flara Day Support</title>
  <style>${pageStyles}</style>
</head>
<body>
  <main>
    <h1>Flara Day Support</h1>
    <p>For help, bug reports, or feedback, email <a href="mailto:${supportEmail}">${supportEmail}</a>.</p>
    <h2>Recording And Transcription</h2>
    <p>Cloud transcription needs an internet connection. Confirm microphone access in iPhone Settings and check Settings &gt; Connection in Flara Day. Live Preview is optional and off by default; final transcription can still work when preview is off.</p>
    <p>During the selected-friends beta, one recording can be up to 30 minutes and the app allows up to 60 transcribed voice minutes per calendar day. Typed journals and letters remain available after the daily voice allowance is reached.</p>
    <p>An active recording can continue while the iPhone is locked or Flara Day is in the background for the remainder of the same 30-minute recording limit. For example, locking the iPhone after 8 minutes leaves up to 22 minutes. Screen lock alone does not shorten the limit. A phone call, Siri, alarm, disconnected microphone, force-quit, or iOS termination may stop the recording earlier; Flara Day keeps and processes everything captured before a handled interruption.</p>
    <h2>Future Letters</h2>
    <p>Allow Flara Day notifications for in-app delivery. For Email, verify the recipient address with the code sent to it, and check spam/junk if a code or letter is missing. Tapping an in-app notification should open the delivered letter.</p>
    <h2>Journal Storage</h2>
    <p>Saved journals and in-app future letters are stored on this iPhone. Cloud services are used only for transcription, AI journal processing, and scheduled email delivery.</p>
    <h2>Import, Export, And Deletion</h2>
    <p>Import supports compatible text, UTF-8 text, JSON, RTF, HTML, and PDFs containing selectable text. Scanned image PDFs need OCR first. Word is not imported directly; Apple Notes can be imported after export or sharing as PDF or text. Delete entries from their detail screen or use Settings &gt; Privacy to delete journals or all app data.</p>
    <h2>Helpful Details For A Bug Report</h2>
    <ul>
      <li>iPhone model and iOS version.</li>
      <li>What you were trying to do and what happened instead.</li>
      <li>Whether the issue occurred on Wi-Fi, cellular, or both.</li>
      <li>Languages used and approximate recording length, when relevant.</li>
    </ul>
    <p>Please do not send private journal text unless you knowingly choose to share it.</p>
    <p><a href="/privacy">Privacy Policy</a></p>
  </main>
</body>
</html>`;

export const privacyPolicyHtml = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Flara Day Privacy Policy</title>
  <style>${pageStyles}</style>
</head>
<body>
  <main>
    <h1>Flara Day Privacy Policy</h1>
    <p class="muted">Effective date: July 16, 2026</p>
    <p>Flara Day is a voice and typed journal that helps you record, transcribe, and reflect on journal entries. This policy explains what information is processed, why it is processed, and the choices you have.</p>

    <h2>Information Flara Day Processes</h2>
    <p><strong>Journals and local app data.</strong> Saved journal text, titles, dates, mood indicators, insights, in-app future letters, feature-board data, and app preferences are stored on your iPhone unless you use a cloud feature or export them.</p>
    <p><strong>Audio and journal text.</strong> Recorded audio and resulting text are sent to the Flara Day backend and OpenAI for cloud transcription and journal drafting. Optional live-preview chunks are sent only when Live Preview is enabled. Journal text may be processed for cleanup, organization, language preservation, and title or mood generation. If you choose translated transcript output, a journal or draft-letter title and text are processed to create one version in your selected language; the original remains preserved in the app. When you explicitly start recording, microphone capture can continue while the iPhone is locked or Flara Day is in the background. It ends when you stop, when the 30-minute recording limit is reached, or when the session is interrupted.</p>
    <p><strong>Future letters and email.</strong> In-app future letters stay on your iPhone. Email delivery processes the verified recipient address, verification code, title, body, delivery time, time zone, and an app-generated random device identifier used to manage letters without an account.</p>
    <p><strong>Security and preferences.</strong> Theme, font, lock, memory-card, and live-preview settings remain on device. Face ID is handled by Apple; Flara Day does not receive biometric data. The future-letter device credential is stored in the iOS Keychain.</p>

    <h2>How Information Is Used</h2>
    <ul>
      <li>transcribe recordings and create journal drafts and titles</li>
      <li>provide search, calendar, memories, and Month Recap</li>
      <li>provide optional live transcription preview</li>
      <li>provide optional journal and Future Letter translation</li>
      <li>maintain preferences and local security settings</li>
      <li>import, export, edit, and delete data at your direction</li>
      <li>verify an email recipient and deliver a scheduled future letter</li>
    </ul>
    <p>Flara Day does not sell journal content or use it for advertising.</p>

    <h2>Service Providers</h2>
    <p>Cloud features may use Cloudflare Workers for the backend, Cloudflare D1 for encrypted pending email letters, OpenAI for transcription and text processing, and Resend for verification codes and scheduled email delivery. These providers process information under their own terms and privacy commitments.</p>

    <h2>Data Retention</h2>
    <p>Local journals and settings remain on your iPhone until you delete them, delete all app data, or remove the app and its data. Flara Day does not intentionally retain uploaded audio on its backend after processing; cloud providers may retain request information under their own terms.</p>
    <p>Pending email addresses and letters are encrypted in Cloudflare D1. After delivery or permanent failure, full content is replaced with status-only data. Canceling or deleting a pending letter removes its remote record. Limited hashed verification and delivery records may be retained for security, rate limiting, and reliability.</p>
    <p>Technical logs may contain timing, status, and error metadata. The service is designed not to log raw audio, complete journal or letter content, verification codes, or device secrets.</p>

    <h2>Your Choices And Deletion</h2>
    <p>You can edit or delete journals, cancel pending future letters, turn Live Preview off, use typed journaling without cloud transcription, export journals, or use Delete All App Data in Settings. Deletion cannot recall email already delivered.</p>

    <h2>Imports And Exports</h2>
    <p>The importer supports compatible text, UTF-8 text, JSON, RTF, HTML, and PDFs containing selectable text. Scanned image PDFs require OCR first. Word files are not imported directly, and Apple Notes must first be exported or shared as PDF or text.</p>

    <h2>Tracking, Analytics, And Children</h2>
    <p>Flara Day does not track you across other companies' apps or websites and does not include advertising or custom analytics SDKs. Flara Day is not directed to children under 13. Apple's App Store age rating is a separate content rating.</p>

    <h2>Security</h2>
    <p>Flara Day uses HTTPS, encrypted pending-letter storage, iOS Keychain credentials, and optional Face ID or password protection. No transmission or storage method is completely secure.</p>

    <h2>Contact</h2>
    <p>For privacy questions, deletion help, or support, email <a href="mailto:${supportEmail}">${supportEmail}</a>.</p>
  </main>
</body>
</html>`;
