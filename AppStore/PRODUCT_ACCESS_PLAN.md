# Flara Day Product Access Plan

Last reviewed: July 17, 2026

This document records product decisions only. Do not add StoreKit paywalls or subscription enforcement to the selected-friends beta build.

## Selected-Friends Beta

- No subscription, payment, or paywall.
- All features are available free so testers can evaluate the complete experience.
- Voice recording, cloud transcription, live preview, in-app future letters, and future-letter email are unlocked.
- Optional translated transcript output is unlocked for beta feedback. Its
  eventual free/Plus placement remains a post-beta pricing decision.
- A single recording can be up to 30 minutes.
- Up to 60 voice-transcription minutes per user per calendar day are available
  during beta as cost protection. This is a beta limit, not a paid tier.
- Collect feedback and observe actual OpenAI, Cloudflare, and Resend usage before setting the eventual monthly Plus allowance.

## Intended Public Free Access

- Typing and saving journals remains free.
- Reading, editing, calendar, insights, memories, export/import, and in-app future-letter notifications remain free unless a later product decision changes them.
- In-app future-letter delivery remains free because it is local to the user's iPhone.
- Voice recording and cloud transcription receive a one-week no-commitment trial. The trial does not require advance subscription authorization.

## Intended Plus Access

- Cloud voice transcription after the one-week trial.
- Maximum of 30 transcribed voice minutes per user per calendar day.
- Live Preview While Recording.
- Future-letter delivery by email.
- The monthly voice allowance and subscription price remain undecided and should be based on beta usage.

## Later Possibilities

- Launch with one paid Plus tier only.
- A Pro tier may be considered later for a higher monthly voice allowance, longer recordings, or priority processing.

## Implementation Notes For Later

- Do not rely only on an on-device counter for paid usage; production enforcement needs a trustworthy backend usage record.
- StoreKit subscription status must be validated before the backend permits paid-only processing.
- Live preview should remain off by default even for eligible users, because it increases transcription usage.
- The app should explain the remaining daily and monthly voice allowance before recording begins.
- The current 60-minute beta daily counter is stored on-device and is suitable
  only for a small trusted beta. Public paid limits must be enforced by the
  backend so reinstalling the app or changing device settings cannot reset them.
