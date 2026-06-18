# Heads-Up Trainer (Quest 1)

> Status: **Implemented**, updated 2026-06-16. The current Quest 1 and the core "learn poker"
> mechanic. Built on the engine in [`one-card-poker-framework.md`](./one-card-poker-framework.md).
> Code: `lib/features/headsup_trainer/` + `lib/engine/players/range_bot.dart`.

---

## 1. The idea
You play **heads-up** one-card poker against a bot that is **fully transparent**: it shows its range
and narrates exactly what it will do. You learn to read the range and respond — and a toggleable
**EV hint** shows the exact chip value of betting against each holding. This is the teaching loop the
whole app is built around.

## 2. Setup
- Picking the trainer opens a **bot-picker submenu** (`BotPickerScreen`) — choose one of three
  transparent personalities to face.
- Heads-up (you + the chosen bot), **50** starting chips, **1/1 blinds**, **pot-sized** bets/raises.
- The **button alternates each hand** so you practise both attacking (as the button/SB, acting first)
  and defending (as the big blind).
- Bust the bot → "you cleared the table"; go broke → reset. **Enter** advances to the next hand.

## 3. The transparent bots (`BotProfile`)
A bot is a **table of `NodeStrategy` keyed by `BetNode`** — one entry per decision spot: `open`,
`checkedTo`, `facingBet`, `facingRaise`, `facingReraise`. Each entry is rank thresholds
(`betFrom` / `callFrom` / `raiseFrom`) plus an optional `bluffs` set that promotes bottom cards to the
aggressive action — that's what makes a range **polarised** (value + bluffs) instead of one linear
threshold. Three personalities ship in `bot_profile.dart`:
- **Rocky** — tight-passive: premiums only, never bluffs, folds to pressure (exploitable on purpose).
- **Vex** — loose-aggressive: bets wide, bluffs the bottom, defends too much.
- **Sage** — balanced: polarised value + bluffs, defends about the right amount.

**One source of truth:** `HeadsUpController` *plays* the selected `BotProfile`, narrows the range, and
narrates from it — and the **EV calculator reads the same profile** — so what the bar predicts is
exactly what the bot does. (The old `RangeBot` ad-hoc "always defend the top card" floor is gone;
anti-exploitability now lives in each profile's explicit bottom `bluffs`.)

## 4. Range narrowing + the range bar
- The bot's possible holdings start as the whole deck (2→A) and **narrow with each action** (e.g. it
  pots → range becomes 9→A; it checks → 2→8).
- **Range bar** (vertical, A top → 2 bottom): in-range ranks are coloured by the bot's action for
  that rank — **CHECK / FOLD / CALL / POT** (POT is purple). When it's your turn it colours by "what
  the bot does **if you pot**". Out-of-range ranks are dimmed.
- At hand end the bar shows the bot's **final range neutrally** (title "Villain's range") and outlines
  its **actual card**. (Coloring is *not* recomputed here — doing so re-applied the defense floor to a
  narrowed fold-range and invented a fake call region; fixed.)
- The bot **speaks** its range each decision (e.g. "If you pot, I shove the ace, call ten through
  king, and fold a nine.").

## 5. The EV hint (free toggle, hover-driven)
With the **Hint** switch on, **hovering an action button** (Fold / Check / Call / Pot) reveals the
**Immediate EV** bar for *that* action: for each card the bot might hold, the **option-A** value —
*the chips you end the hand with minus your stack at the start of the hand* — for the lines that
**resolve the moment the bot answers**. Color-graded bright-red → grey → bright-green, scaled to the
action's biggest swing. (`engine/ev/immediate_ev.dart`, validated in `test/immediate_ev_test.dart`.)

The whole point is the "compared to what?" baseline: every number is *net chips this hand*, so a fold
is −(what you'd already put in), a check that goes to showdown is ±the blind, and a bet the bot folds
to wins exactly the bot's committed chips (the uncalled part comes back).

Each card's cell is labelled by **what kind of spot it is** — your action × his transparent
reply × who's ahead — not just the raw outcome:

| Your action | His reply | His card vs yours | Label | Value (net chips) |
|---|---|---|---|---|
| Bet / raise | folds | worse | **No Value** | + his committed chips |
| Bet / raise | folds | same | **Split Fold Eq** | + his committed chips |
| Bet / raise | folds | better | **Fold Equity** | + his committed chips |
| Bet / raise | calls | worse | **Value** | + the matched amount |
| Bet / raise | calls | same | **Split** | 0 |
| Bet / raise | calls | better | **Called by Better** | − the matched amount |
| Call | showdown | better (yours) | **Showdown Value** | + the matched amount |
| Call | showdown | worse (yours) | **Paid Off** | − the matched amount |
| Call | showdown | same | **Split** | 0 |
| Check / fold | — | — | *(no label)* | the chips, uncommented |
| (any) | ball comes back | — | **?** | *unknown — see below* |

Long labels fade in the narrow cell but show in full on hover (tooltip). Check and fold lines
show only the chip number — there's nothing strategic to teach about checking through or folding.

**The "?" — the deliberate gap.** We give a number only for lines that finish on the bot's next
action. The one case that *doesn't* is **you aggress and the bot re-raises** (or **you check and the
bot bets**): the ball is back in your court, the result depends on a move you haven't made, and we
refuse to model your future for you — that's the next decision to think through. Those cards show a
**"?"**, not a guess. (No "perfect GTO" line is shown anywhere; the player reasons it out.)

**Avg.** Below the bar an **Avg** figure is the mean of the known cells — every card **except** the
"?"s — i.e. the average net chips this action books across the part of the bot's range that resolves
right now. **When most of the bot's range answers aggressively** (it re-raises your bet, or bets into
your check) most cells are "?", so the Avg would be the mean of a tiny leftover sample — misleading.
In that spot we hide it: there's no honest average to show.

> `engine/ev/ev_calculator.dart` (exact best-response EV by backward induction; `test/ev_test.dart`)
> still exists as a solver but is **not** shown to the player — deliberately, so the trainer makes you
> think rather than handing you the answer.

## 6. UI specifics
- **Action buttons:** Fold / Check / Call N / **Pot N** (only the legal ones each spot; Pot shows the
  raise-to amount, in purple).
- **Dealer button:** a chip that **animates between the two seats** each hand (`AnimatedAlign`);
  seats also show SB/BB badges.
- **Last action** is shown as a bold colour-coded tag by each player (POT N / CALL N / CHECK / FOLD).
- A pre-showdown pause lets the final chips land before the reveal; chip animations on every
  blind/bet/call.

## 7. Files
```
lib/engine/players/bot_profile.dart          three transparent personalities as node→strategy tables
lib/engine/players/range_bot.dart            BotMove enum (legacy thresholds bot, no longer played here)
lib/engine/ev/immediate_ev.dart              per-card option-A EV (resolved lines) + "?" when the ball comes back
lib/engine/ev/ev_calculator.dart             exact best-response EV (backward induction over clones; NOT shown to the player)
lib/features/headsup_trainer/
  bot_picker_screen.dart                     submenu to choose Rocky / Vex / Sage
  headsup_controller.dart                    plays a BotProfile; range narrowing, narration, per-action EV
  headsup_screen.dart                        table, action bar (hover→EV), dealer button, hint switch
  widgets/range_bar.dart                     vertical 2→A range bar
  widgets/ev_bar.dart                         Immediate-EV bar (per-card option-A chips or "?", + Avg footer, gradient)
```

## 8. Possible next steps
Deeper betting streets; an exploit **score/feedback** ("you left EV here"); a true **GTO mode**;
charging for hints later (currently free); rotating opponents/personalities into the trainer.
