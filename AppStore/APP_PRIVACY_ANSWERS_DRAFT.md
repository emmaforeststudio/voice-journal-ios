# App Store Privacy Answers Draft

This is a draft for App Store Connect's App Privacy section. Review before submission.

## Tracking

Does Flara Day use data to track users across apps or websites owned by other companies?

Recommended answer: No.

## Data Collection

Important distinction: Apple asks what data is collected by the app and/or third parties. Because audio and journal text are sent to the backend/OpenAI for processing, we should disclose this conservatively.

## Likely Data Types To Disclose

### User Content

Data type: Audio Data

Collected: Yes, when the user records a journal and cloud transcription is used.

Linked to user: No, unless you later add accounts or identifiers.

Used for tracking: No.

Purpose: App Functionality.

Notes: Audio is processed to create transcription and journal drafts.

### User Content

Data type: Other User Content

Collected: Yes, journal text/transcript may be sent for AI cleanup and draft generation.

Linked to user: No, unless you later add accounts or identifiers.

Used for tracking: No.

Purpose: App Functionality.

Notes: Journal text is processed to generate the final journal draft.

### Identifiers

Data type: User ID

Collected: No for current app, unless you add accounts, cloud sync, analytics, or subscription account linking.

### Diagnostics

Collected: No for current custom app code, unless you add crash reporting, analytics, or Cloudflare/OpenAI logs that you treat as diagnostics.

### Contact Info

Collected: No in the app, unless you add support email collection or accounts.

### Usage Data

Collected: No in the app, unless analytics are added.

## Current Local Storage

The following are stored locally on device:

- journal entries
- app settings
- theme/font preferences
- lock preferences
- feature request board data

Local-only data may not need to be reported as collected if it is not transmitted off device, but review Apple's current App Privacy instructions when submitting.

## Open Questions For Emma

- Will there be subscriptions at launch?
- Will there be user accounts at launch?
- Will support requests collect email addresses through a form?
- Will Cloudflare logs be retained or reviewed?
- Will any analytics/crash reporting SDK be added?

