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

Recommended answer for version 1.0: No.

Reason: The app does not require user accounts, cloud sync, analytics, or subscription account linking.

### Diagnostics

Recommended answer for version 1.0: No for app-collected diagnostics.

Reason: The app does not include a third-party crash reporting or analytics SDK. Cloudflare/OpenAI may process technical service logs for backend reliability, but Flara Day should not intentionally collect audio, transcripts, or journal text as diagnostics.

### Contact Info

Data type: Email Address

Collected: Yes, only when the user chooses email delivery for a future letter.

Linked to user: Yes. Disclose conservatively because the address identifies the email recipient and is associated with a device credential.

Used for tracking: No.

Purpose: App Functionality.

Notes: The address is verified before scheduling. D1 stores a one-way email hash for verification status; the full address is encrypted only with a pending letter and is removed from the stored payload after delivery or permanent failure. Canceling or deleting the letter removes its remote record.

### User Content: Future Letters

Data type: Other User Content

Collected: Yes, only when email delivery is selected.

Linked to user: Yes. Disclose conservatively because the content is scheduled to a verified email address.

Used for tracking: No.

Purpose: App Functionality.

Notes: The title and letter body are encrypted in Cloudflare D1 while awaiting delivery and sent through Resend at the selected time. Full stored content is replaced with status-only data after delivery or permanent failure; canceling or deleting a letter removes its remote record. In-app future letters remain local to the device.

### Usage Data

Recommended answer for version 1.0: No.

Reason: The app does not include custom analytics.

## Current Local Storage

The following are stored locally on device:

- journal entries
- app settings
- theme/font preferences
- lock preferences
- feature request board data
- in-app future letters

Local-only data may not need to be reported as collected if it is not transmitted off device, but review Apple's current App Privacy instructions when submitting.

## Version 1.0 Assumptions

- No subscriptions at launch.
- No user accounts at launch.
- No support request form at launch.
- No custom analytics or crash reporting SDK at launch.
- Technical backend logs may be used only for debugging, reliability, and security, and should not intentionally include raw audio, full transcripts, or journal entries.
- Email delivery is available without payment during the selected beta. The planned public paid tier and one-week no-commitment voice trial are not active in this build.
