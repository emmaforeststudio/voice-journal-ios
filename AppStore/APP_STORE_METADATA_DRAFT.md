# Flara Day App Store Metadata Draft

Last reviewed: July 20, 2026

## App Information

- Name: `Flara Day`
- Subtitle: `Voice journal for reflection`
- Primary language: English (U.S.)
- Primary category: Lifestyle
- Secondary category: Productivity (optional)
- Bundle ID: `com.emmaforeststudio.FlaraDay`
- SKU suggestion: `FLARADAY-IOS-001`

The selected subtitle is 28 characters, within Apple's 30-character limit.

## Promotional Text

Speak, write, and revisit your days through multilingual transcription, gentle
insights, memories, and letters to your future self.

## Description

Flara Day is a calm place to speak or type what you want to remember.

Record a reflection in the languages you naturally use, review the cleaned
journal draft, and save it to your calendar. Revisit meaningful entries through
On This Day or a random memory, notice recurring themes in Month Recap, and write
a letter for your future self.

Features:

- Voice recording with cloud transcription
- Multilingual transcription designed to preserve the language you spoke
- Optional live preview while recording, off by default
- AI-assisted cleanup and title generation
- Typed journals with no recording required
- Calendar, search, editing, import, and export
- Current streak, monthly entry count, and Month Recap themes
- On This Day and Random Entry memories
- Future letters delivered by an in-app notification or verified email
- Face ID and password lock options
- Theme, font, font-size, light-mode, and dark-mode customization

Journal entries are stored on your iPhone unless you export them. Cloud services
are used only for features that require transcription, AI text processing, or
scheduled email delivery.

Flara Day is designed for quiet reflection: a gentle place to capture what
happened, how it felt, and what you want to carry forward.

## Keywords

`diary,reflection,transcription,mood,memories,wellness,thoughts,calendar,self care,mindfulness`

This string is within Apple's 100-byte limit and avoids repeating the app name,
company name, and the subtitle's strongest terms.

## URLs

- Support URL: `https://flara-day-backend.emmaforeststudio.workers.dev/support`
- Privacy Policy URL: `https://flara-day-backend.emmaforeststudio.workers.dev/privacy`
- Marketing URL: leave blank for beta; optional for public release

## Age Rating Working Notes

Complete Apple's current age-rating questionnaire truthfully. Flara Day has no
public user-generated content, chat, ads, gambling, unrestricted web access, or
built-in mature material. A low rating is expected, but Apple calculates the
final rating from the questionnaire and may show different regional equivalents.

The privacy statement that Flara Day is not directed to children under 13 is an
audience policy; it is not the same thing as Apple's content-based age rating.

## App Review Notes

Flara Day does not require an account or demo credentials.

Voice flow: open Create, tap Record, speak, stop recording, and review the cloud-
generated draft. Final transcription uses the production backend and requires an
internet connection. Optional Live Preview can be enabled in Settings and is off
by default.

Future Letter flow: open Insights, tap Letter to Future Me, create a letter, pick
In-App or Email, and schedule it. Email delivery asks the reviewer to verify an
email address with a code sent to that address. In-app delivery uses a local iOS
notification. For review, choose a delivery time several minutes in the future.

Journal entries and in-app future letters are stored locally. Cloudflare Workers
forwards transcription and text-processing requests to OpenAI. Scheduled email
letters are encrypted in Cloudflare D1 until Resend delivers them.

No subscription or paywall is active in this selected-friends beta build. No
analytics, advertising, tracking, or third-party crash SDK is included.

Contact: `emmaforeststudio@gmail.com`

## TestFlight Beta Information

### Beta Description

Flara Day is a multilingual voice and typed journal with calendar history,
monthly insights, memory resurfacing, and future letters.

### What To Test

Please test voice recording in one or several languages, including continuing
to speak after locking the screen or switching apps. Confirm the timer and final
transcription include that interval. Review and edit the generated journal,
save and find entries, explore Insights, and schedule both an in-app and email
future letter. Report transcription omissions, incorrect language conversion,
notification or email delays, layout issues, and crashes.

### Feedback Email

`emmaforeststudio@gmail.com`
