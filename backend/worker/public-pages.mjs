const supportEmail = "emmaforeststudio@gmail.com";

const pageStyles = `
  :root {
    color-scheme: light;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    color: #24302d;
    background: #edf8f4;
  }
  body {
    margin: 0;
    padding: 40px 20px;
  }
  main {
    max-width: 760px;
    margin: 0 auto;
    background: rgba(255, 255, 255, 0.72);
    border: 1px solid rgba(84, 133, 121, 0.18);
    border-radius: 22px;
    padding: 32px;
    box-shadow: 0 20px 60px rgba(70, 102, 96, 0.12);
  }
  h1 {
    margin: 0 0 8px;
    font-size: 34px;
    line-height: 1.1;
  }
  h2 {
    margin: 28px 0 8px;
    font-size: 20px;
  }
  p, li {
    font-size: 16px;
    line-height: 1.65;
  }
  a {
    color: #397f74;
    font-weight: 650;
  }
  .muted {
    color: #69736f;
  }
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
    <p class="muted">Need help with Flara Day?</p>
    <p>Email <a href="mailto:${supportEmail}">${supportEmail}</a> for support, questions, bug reports, or feedback.</p>
    <h2>Helpful Details To Include</h2>
    <ul>
      <li>Your iPhone model and iOS version.</li>
      <li>What you were trying to do.</li>
      <li>What happened instead.</li>
      <li>Whether the issue happened on Wi-Fi, cellular, or both.</li>
    </ul>
    <h2>Privacy</h2>
    <p>For privacy information, read the <a href="/privacy">Flara Day Privacy Policy</a>.</p>
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
    <p class="muted">Effective date: July 14, 2026</p>

    <h2>Overview</h2>
    <p>Flara Day is a personal voice journal app. Your journal entries are personal, and the app is designed to avoid collecting more information than is needed to provide transcription, journal drafting, and app support.</p>

    <h2>Information Processed</h2>
    <p>When you record a journal entry, audio may be sent to the Flara Day backend and OpenAI for transcription and journal draft processing. The app may also process the resulting transcript and generated journal text so it can show your entry in the app.</p>
    <p>Your saved journal entries are stored on your device unless you choose to export or share them using features provided by the app or iOS.</p>
    <p>Future letters scheduled as in-app notifications remain on your device. If you choose email delivery, Flara Day processes a verified recipient email address, the letter title and body, and the requested delivery time.</p>

    <h2>How Information Is Used</h2>
    <p>Audio, transcripts, and journal text are used to provide the app's core features, including transcription, live preview, journal cleanup, and journal organization. We do not use your journal content for advertising.</p>

    <h2>Third-Party Processing</h2>
    <p>Flara Day uses OpenAI services to process audio and text for transcription and journal drafting. The Flara Day backend is hosted on Cloudflare Workers so the OpenAI API key does not need to be stored in the iPhone app.</p>
    <p>For future-letter email delivery, Cloudflare D1 stores the encrypted pending letter and Resend delivers verification codes and the scheduled email.</p>

    <h2>Future-Letter Retention</h2>
    <p>A one-way representation of a verified email address and delivery status may be retained to operate and secure the service. The full email address and letter content are encrypted while a letter is waiting for delivery. After delivery or permanent failure, the full stored letter is replaced with status-only data. Canceling or deleting a letter removes its remote record.</p>

    <h2>Logs</h2>
    <p>Technical logs may be used to monitor reliability, debug errors, and protect the service. Logs should not intentionally include raw audio, full transcripts, or journal entries.</p>

    <h2>Accounts, Analytics, And Advertising</h2>
    <p>Flara Day does not require a user account for version 1.0. Flara Day does not include third-party advertising SDKs. If analytics or crash reporting tools are added in the future, this policy will be updated before those changes are released.</p>

    <h2>Children</h2>
    <p>Flara Day is not directed to children under 13, and we do not knowingly collect personal information from children under 13.</p>

    <h2>Contact</h2>
    <p>For support or privacy questions, contact <a href="mailto:${supportEmail}">${supportEmail}</a>.</p>
  </main>
</body>
</html>`;
