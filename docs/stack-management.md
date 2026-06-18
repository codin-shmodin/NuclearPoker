re# Stack Management — NuclearPoker

> Status: **Approved** (2026-06-14). The agreed technical stack for the PoC.

## Product context (why this stack)
- Gamified single-player **vs-AI** poker (no live multiplayer at PoC) → no real-time authoritative game server needed; the game + AI run **on-device**.
- Chips are only the **betting tool at the table**, not a cash-out wallet → **no gambling license / KYC**. We are a *game*, not a casino.
- Targets: **iOS + Android + web** from one codebase.
- Constraints: **solo dev**, **low-cost PoC**, and **polish/feel is the priority** (Candy Crush–style: fast, juicy, well-animated, never choppy).

## The stack

| Layer | Choice | Why |
|---|---|---|
| **Client / engine** | **Flutter** (Dart) | One codebase → iOS + Android + **web** (only option treating web as first-class). Impeller renderer = buttery 60–120fps. Free, hot-reload, solo-friendly. |
| **Animation / "juice"** | **Rive** (+ **Flame** if needed) | Designer-driven vector animations with state machines for card flips, chip movement, win bursts. Flame adds sprites/particles if required. |
| **Backend / live-ops** | **Firebase** | Auth, Firestore (progress/save), Cloud Functions, **Remote Config** (tune rewards/difficulty without redeploy), A/B Testing, Cloud Messaging (push). Generous free tier, first-class Flutter support. |
| **Dev analytics** | **Firebase** Crashlytics + Performance Monitoring + Analytics | Crash/perf/usage out of the box, free. |
| **Product analytics** (add later) | **PostHog** or **Amplitude** (free tier) | Retention / funnel / cohort analysis — critical for a gamified app. |
| **Poker AI** | **Client-side Dart** | Bots ship in the app. No server cost. See AI player architecture below. |

## Alternatives considered (and why not)
- **Unity** — best game-feel tooling, but heavy/slow web (WebGL) export, overkill for a 2D card game. Reconsider only if we go 3D or drop web.
- **React Native** — weakest animation polish of the three; animation is our top priority, so ruled out.
- **Supabase** vs Firebase — both solid; Firebase wins for built-in live-ops (Remote Config + A/B + Analytics + Crashlytics), which is the whole point of a gamified app.

## Cost at PoC
- ~**$0** until traction (Firebase free tier + free dev tools).
- Store fees only when publishing: **Apple $99/yr**, **Google Play $25 one-time**.

## Caveats / things to watch
- Flutter **web** has a chunky initial load + text-rendering quirks — acceptable for a game (no SEO need), but keep web bundle lean.
- Revisit backend choice if we ever add **live multiplayer** (would need a real-time authoritative server, e.g. Cloud Functions + WebSockets, or a dedicated game-server host).
