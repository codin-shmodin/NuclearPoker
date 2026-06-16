# Quest 1 — "One Card Poker" Framework Design

> Status: **Design (draft)**, 2026-06-14. First quest. Goal: build the reusable poker
> framework + AI player system, using the simplest solvable poker variant as the testbed.
> Stack per [`stack-management.md`](./stack-management.md): Flutter + Dart, on-device.

---

## 1. Why this quest first
"One card poker" is the smallest real poker game. It lets us build and **validate the entire
framework** — game engine, player interface, GTO bot, UI/animation, quest wrapper — before any
postflop complexity exists. Heads-up, it's essentially **Kuhn poker** (the classic game-theory
teaching game), which has a known exact GTO solution. That makes it the ideal place to prove the
"perfect static GTO player" you asked for.

## 2. Rules spec (agreed)
- **Variant:** Standard — each player gets **1 private card they can see**. High card wins.
- **Players:** up to **6** at a table (engine is player-count-agnostic; see §6 on GTO).
- **Betting:** **check / bet / call / fold**, single fixed bet size, **one betting round**, **no raises** (simple mode).
- **Deck:** standard 52, ranks 2→A. Suits don't rank; **ties split the pot**.

### Level 1 settings (implemented)
- **Table:** hero + **5 straightforward bots** (6-handed). Starting stack **30 chips**.
- **Forced bets:** **no ante, 1/1 blinds** (small + big blind = 1 each). The engine supports
  antes too (`RuleConfig.ante`), but Level 1 uses blinds.
- **Betting:** check/call/fold plus a single **bet/raise to `betSize` (4)** — one raise, no re-raises.
- **Action order:** dealer button rotates each hand; first to act = seat left of button.
- **Bet flow:** in turn each player checks or bets `B`. Once a bet is out, later players call/fold.
  If a bet lands *after* players have checked, action reopens to them (call/fold only — no raise).
  All-check → straight to showdown.
- **Showdown:** remaining players reveal; highest rank wins; equal ranks split the pot.

*(These are the only knobs that change the engine; flag any you'd change.)*

## 3. Architecture principles
1. **Pure-Dart engine, zero Flutter dependencies.** The rules + state machine + players live in a
   standalone package so they're unit-testable, runnable *headless* (needed to compute GTO), and
   reusable across all future quests. UI never contains game rules.
2. **Players are policies behind one interface** (strategy pattern). Bots are content, not new code.
3. **Information hiding:** a player only ever receives a `GameView` — exactly what a real player at
   that seat could see (own card, public actions, pot, stacks). No peeking at others' cards. This
   also keeps bots honest and makes the same interface work for the human UI.
4. **Deterministic & seedable:** shuffles and mixed-strategy dice rolls take an injectable RNG, so
   hands are reproducible for tests and replays.

## 4. Core domain model (engine package)

```dart
// cards/
enum Rank { two, three, ..., ace }          // suits tracked but don't rank
class Card { final Rank rank; final Suit suit; }
class Deck { Deck(Random rng); Card draw(); }

// game/
enum ActionType { check, bet, call, fold }
class Action { final ActionType type; final int amount; }      // amount used for bet/call

class Seat { final int index; int stack; Card? card; bool folded; int committed; }

class GameView {            // what ONE player sees when asked to act
  final Card myCard;
  final int myStack, pot, toCall;
  final List<PublicAction> history;
  final int seatsInHand;
  final int myPosition;     // relative to button
}

class HandState { /* seats, pot, button, toAct, betting status */ }

enum HandPhase { deal, betting, showdown, payout, done }

// The state machine: pure functions advancing a hand.
class HandEngine {
  HandState start(List<PokerPlayer> players, int button, RuleConfig rules, Random rng);
  HandState applyAction(HandState s, Action a);   // validates + advances
  List<Payout> settle(HandState s);               // showdown → chip movement
}

class RuleConfig { final int ante, betSize, maxPlayers; }   // tunable via Remote Config later
```

### Player interface
```dart
abstract class PokerPlayer {
  String get id;                         // "gto", "the-nit", "the-maniac", "human"...
  Action decide(GameView view);          // returns a legal action
}
```

## 5. AI player roster (three tiers, one interface)

| Tier | Implementation | Role |
|---|---|---|
| **1 — GTO (static)** | `GtoPlayer`: looks up the precomputed strategy for `(card, position, history)` and **mixes** per the GTO frequencies using the injected RNG. No runtime computation. | Your **perfect static GTO** opponent / trainer. |
| **2 — Personalities** | `PersonalityPlayer(params)`: rule engine driven by `{aggression, tightness, bluffFreq, callThreshold}`. Presets = characters: **Nit, Rock, TAG, LAG, Maniac, Calling Station**. | Unlimited distinct beatable opponents for the gamified ladder. |
| **3 — Solver/ML (future)** | Same interface, postflop engine plugged in later. | Out of scope for quest 1. |

`HumanPlayer` is also just a `PokerPlayer` whose `decide()` resolves from UI input — so the engine
treats humans and bots identically.

## 6. The GTO solution (offline → lookup table)
- **Approach:** solve **offline** with **CFR** (counterfactual regret minimization), export the
  resulting average strategy to a compact table bundled in the app. Runtime cost = a map lookup +
  one RNG draw.
- **Heads-up (2p):** zero-sum → CFR converges to the **unique exact GTO**. We compute and ship this
  as the genuinely-perfect bot, and use it to validate the whole engine (known Kuhn-poker results
  are a built-in correctness check).
- **6-max (multiway):** equilibria are **not unique** and 2p guarantees don't hold. CFR still
  produces a **strong approximate** strategy — good enough for a tough opponent, but we will label it
  internally as *approximate*, not *provably optimal*. **Plan: validate heads-up first, then
  generalize.**
- The solver is a headless script using the pure-Dart engine — no UI, no extra infra.

## 7. Proposed project structure
```
nuclear_poker/
  packages/
    poker_engine/            # pure Dart, no Flutter
      lib/{cards,game,players,gto}/
      test/                  # heavy unit tests (rules, payouts, GTO correctness)
      tool/solve_gto.dart    # headless CFR solver → exports strategy table
  lib/                       # Flutter app
    features/quest_one_card/ # this quest's screens, controllers, animations (Rive)
    core/                    # shared UI, theming, routing
    services/                # Firebase, analytics, remote config
  assets/gto/                # exported GTO strategy tables
  docs/
```
**Why a separate engine package:** testability, headless GTO solving, and reuse across every future
quest without dragging UI along.

## 8. Hooks into the gamified meta (deferred, but designed-for)
- A `Quest` wraps a configured table (rules + opponent roster + win condition) and emits results the
  reward/progression system consumes. Quest 1 = "beat the table over N hands" or "reach X chips".
- `RuleConfig` and opponent params are designed to be driven by **Firebase Remote Config** so we can
  tune difficulty/rewards without shipping updates.
- Detailed reward-loop / progression design is a **separate doc** (TBD after market research lands).

## 9. Testing strategy
- Engine: exhaustive unit tests on legal-action validation, betting flow, multiway showdown/ties,
  payouts, button rotation.
- GTO: assert heads-up output matches known Kuhn-poker equilibrium values.
- Determinism: same seed → same hand, enabling golden-file replay tests.

## 10. Open decisions
1. Ante vs blinds, and exact `ante`/`betSize` values (§2).
2. Single fixed bet only, or allow one raise later (changes tree size).
3. Heads-up-only for quest 1 to keep GTO "perfect", or ship 6-max with approximate GTO from the start.
4. Win condition / framing of the quest itself (depends on reward-loop design).
```
