# CLAUDE.md

## What this is
NuclearPoker — a gamified poker app for iOS, Android and web. Single-player vs AI,
with a Candy Crush-style progression/reward meta layer. Chips are only the betting
tool at the table, not a cash-out wallet (it's a game, not a casino). Currently a
low-cost PoC. Quest 1 is the **Heads-Up Trainer** — one-card poker vs a fully
transparent range bot, with an exact-EV hint.

## Stack
Flutter (Dart) for all platforms · Rive/flutter_animate for animation · Firebase for
backend/live-ops (auth, Firestore, Remote Config, analytics) · poker AI runs
client-side in Dart. Full rationale in `docs/stack-management.md`.

## Where things are
- `docs/` — design docs: `stack-management.md` (stack rationale),
  `one-card-poker-framework.md` (as-built engine), `heads-up-trainer.md` (Quest 1: range bot + EV),
  `expansion-plans.md` (levels + range-automation editor + particle/extraction currency — brainstorm),
  `adventure-map.md` (level map: data model, screen, trainer wiring — plan).
- `lib/engine/` — pure-Dart game logic (cards, rules engine, AI players). No Flutter imports.
- `lib/features/headsup_trainer/` — current Quest 1. `lib/features/quest_one_card/` — legacy 6-max table.
- `lib/home/`, `lib/theme/` — entry screen and theming.
- `test/` — engine tests.
- `MARKET_RESEARCH.md` — competitor/market research.

## Principles
- Don't ask the user to do tasks you can do yourself just as well.
- Don't make important decisions without the user's consent — but don't bother them
  with decisions that won't change much; pick a sensible default and mention it.
- Read only the docs relevant to the current task. Don't read all docs "for good
  measure" — it burns tokens.
- For each major feature or bug fix, commit and push the changes.
