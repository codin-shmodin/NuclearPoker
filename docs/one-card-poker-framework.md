# Poker Engine & One-Card Poker (as built)

> Status: **Implemented**, updated 2026-06-16. The reusable poker engine + the one-card-poker
> rules that Quest 1 runs on. Stack per [`stack-management.md`](./stack-management.md): Flutter +
> Dart, on-device. The current Quest 1 experience is the
> [Heads-Up Trainer](./heads-up-trainer.md).

---

## 1. What this is
One-card poker is the smallest real poker game: each player gets **one** private card, there's a
single betting round, high card wins. It's the testbed for the whole framework (engine, player
interface, UI/animation) and the basis of the learning game.

## 2. Rules (as implemented)
- **Card:** each player gets 1 private card. Standard 52-card deck, ranks 2→A (Ace high). Suits do
  **not** rank — **ties split the pot**.
- **One betting round:** actions are **fold / check / call / bet**. "Bet" is a **pot-sized** raise
  (see §4). Raising is **uncapped** — you can keep re-raising until someone is all-in.
- **Forced bets:** blinds (small/big) and/or antes, configurable. Showdown: highest card wins; equal
  ranks split; all-ins resolved with **side pots**.
- **Player count:** engine is player-count-agnostic (heads-up to 6). Heads-up is special-cased so the
  button is the small blind and acts first (standard heads-up rules).

## 3. Architecture principles
1. **Pure-Dart engine, zero Flutter imports** (`lib/engine/`). Rules + state machine + players are
   unit-testable and could run headless. The UI never contains game rules.
2. **Players are policies behind one interface** (`PokerPlayer`). Bots — and the human — are
   interchangeable; new opponents are content, not engine changes.
3. **Information hiding:** a player only ever receives a `GameView` (its own card, the pot, what it
   must call, public opponent info). It can't see other hole cards.
4. **Deterministic & seedable:** the deck shuffle takes an injected `Random`, so hands are
   reproducible in tests.

## 4. Betting model — pot-sized, uncapped, with side pots
- **A bet/raise is "pot-sized":** you raise **to** `currentBet + pot + yourCall` (the standard
  pot-limit raise — you call first, then bet the resulting pot). Opening with nothing to call →
  `currentBet + pot`. Example: heads-up 1/1 blinds, the button (call 0) pots → raises to **3**.
- **Uncapped:** keep raising (3-bet, 4-bet, …) until a player is all-in; you may shove for less than
  a full pot if that's all you have.
- **All-ins → side pots:** at showdown the pot is split into contribution layers; each layer goes to
  the best card among players eligible for it. **Uncalled chips are refunded before settling** (a lone
  top bettor can't win more than was matched) — this is the standard rule and avoids a "split pot"
  mislabel.
- **Fold-out:** if everyone folds to one player, they take the whole pot (their uncalled bet returns).
- **Sit-out:** a player with 0 chips sits the hand out — no card, no blind, never to act.

## 5. Core domain model (`lib/engine/`)
```
cards/   Rank (label + value 2..14), Suit (symbol, isRed; no rank), PlayingCard, Deck(Random)
game/    ActionType{fold,check,call,bet}, GameAction(type, amount)
         RuleConfig{ante, smallBlind, bigBlind, startingStack, maxPlayers}
         Seat{index, playerId, name, isHuman, stack, card?, folded, hasActed, committed, lastWin, lastAction}
         GameView (redacted per-seat view: myCard, pot, toCall, currentBet, canCheck/canCall/canBet,
                   raiseTarget, isOpen, raiseCount, opponents[])
         HandState{seats, button, toAct, pot, currentBet, raiseCount, phase,
                   smallBlindSeat, bigBlindSeat, winners[], log[]}
         HandPhase{betting, showdown, complete}
         HandEngine: start(seats, button) → deals/posts blinds; legalActions(state);
                     applyAction(state, action) (validates + advances); buildView(state, seat).
players/ PokerPlayer (interface: decide(GameView)→GameAction)
         HumanPlayer (UI-driven; decide() unused), SimpleAiPlayer (heuristic), RangeBot (trainer)
```
`HandState` is mutated in place by the engine (kept simple for the PoC).

## 6. AI players (`PokerPlayer` implementations)
- **`SimpleAiPlayer`** — heuristic bot with personality knobs (`tightness`, `aggression`, `bluffFreq`,
  `callStation`) and presets (Nit / TAG / LAG / Maniac / Calling Station / Straightforward). Used by
  the legacy 6-max table screen.
- **`RangeBot`** — the **fully transparent** trainer bot whose strategy is simple rank thresholds, so
  the UI can show and narrate its exact range. See [`heads-up-trainer.md`](./heads-up-trainer.md).
- **GTO is deferred.** The original plan (offline CFR → lookup table) is on hold; the transparent
  hand-authored `RangeBot` serves the learning goal for now. CFR remains a future option (heads-up
  one-card poker is small enough to solve exactly).

## 7. Project structure (actual)
```
lib/
  main.dart, app.dart            entry + MaterialApp/theme
  theme/                         AppColors, AppTheme
  home/                          quest map / start screen
  engine/{cards,game,players}/   pure-Dart engine (above)
  features/
    quest_one_card/              legacy 6-max table (QuestController + screen + widgets)
    headsup_trainer/             CURRENT Quest 1 (see heads-up-trainer.md)
test/
  engine_test.dart               engine rules / pot-sizing / all-in / side-pot tests
  widget_test.dart               home-screen smoke test
```
The engine lives in a folder (not a separate package) but stays Flutter-free, so it can be extracted
later.

## 8. Testing
`flutter test` (12 tests). Engine coverage: blinds posting + first-to-act, check-around showdown,
fold-out, illegal check, pot-sized 3-bet sizing, uncapped raising, all-in for less / no-hang, side-pot
chip conservation, "K vs A → Ace wins outright (no false split)", redacted view. Determinism via
seeded `Random`.

## 9. Hooks into the gamified meta (future)
- A quest wraps a configured table (rules + opponents + win condition) and emits results the
  reward/progression layer will consume.
- `RuleConfig` is designed to be driven by **Firebase Remote Config** so difficulty/economy can be
  tuned without an app update.
- Reward-loop / progression design is still TBD (informed by `../MARKET_RESEARCH.md`).

## 10. Run
`flutter run -d chrome` (also iOS/Android). Flutter ≥ 3.27 (uses `Color.withValues`).
