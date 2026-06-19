# Expansion Plans

> Status: **Brainstorm / not yet built**, drafted 2026-06-19. Captures the direction for turning the
> [Heads-Up Trainer](./heads-up-trainer.md) into a progression game with a meta-layer. Nothing here is
> committed engine work yet — it's the design we're converging on, plus the open questions we still
> need to answer.

---

## 1. Big picture: levels → "automate your range"

The game becomes a ladder of **levels**. Each level is a **table seating some number of bots** that you
have to beat. Beat the level once and a new capability unlocks: **you can automate your own range** —
i.e. hand your line over to your own bot so it plays the table for you.

The fantasy: you climb by *playing* poker, then graduate each level by *teaching a bot to play it for
you*. That mirrors the whole app's teaching loop — first you read the transparent bot's range, then you
author your own. Beating the level by hand proves you understand the spot; automating it proves you can
express the strategy.

### Two ways to author your bot
1. **Capture from play ("save my line").** While playing normally, when you're confident in a decision,
   you hit **save** and that action is bound to that exact spot. Example: "I have a `2` on the BTN, I
   check and fold to his bet" → saved. "I have a `Q` in the SB, I check and call his bet" → saved. You
   build the bot by demonstration, hand by hand.
2. **Manual editor ("open bot settings").** Open your bot's config and set every spot directly, without
   waiting for the hand to come up in play.

Both edit the **same underlying strategy table** — capture-from-play is just a fast path into it. (This
is the player-facing mirror of how the transparent bots already work: a table of `NodeStrategy` keyed by
`BetNode`, see heads-up-trainer.md §3.)

### The range editor: 39 lines for 1-street heads-up

For our **single-street heads-up** game the strategy space is small and fully enumerable. There are
**39 lines** = **13 ranks × 3 situations**:

| Situation | What it is |
|---|---|
| **BTN** | You're on the button / SB, you act first |
| **SB vs pot** | You're the big blind and villain has bet/potted into you |
| **SB vs check** | You're the big blind and villain has checked to you |

**Three flip-through pages**, one per situation, titled accordingly. On each page the **13 ranks run top
to bottom** (2 → A or A → 2 — TBD), each with a **square next to it** showing the chosen action.

**Whose-turn coloring.** Squares **alternate color** down the action sequence so it's visually obvious
which decisions are *yours* and which are *his*. You read a row as a little conversation: his action,
your action, his action, your action…

**One line per card.** We only need the **single line where he raises/bets at every opportunity**,
because **if he doesn't raise, the line is over** — there's no further decision to encode. That collapses
what could be a branching tree into one row per rank per page. (Worth a sanity check against the actual
bet-node graph: with pot-sized betting and re-raises the "he always raises" path can have several of
*your* nodes on it — `facingBet`, `facingRaise`, `facingReraise`. The row needs a square for each of
*your* decision points on that path, which is exactly what the alternating-color reading gives us.)

### Open questions on the editor
- **Action vocabulary per square.** check/bet, call/fold/raise — does a single tap cycle through the
  legal actions for that node, or do we show explicit buttons?
- **All-in / multi-raise depth.** Pot-sized uncapped betting means the "he always raises" line can run
  several raises deep. Do we cap the displayed depth, or let a row scroll horizontally through the
  re-raise nodes?
- **Validation / "is this a complete strategy?"** When does the bot count as fully specified vs. having
  holes? Do unspecified spots fall back to a default (e.g. fold)?
- **Multi-bot tables.** The 39-line model is clean for *heads-up*. Levels with "some amount of bots"
  imply multiway pots — either levels stay heads-up (you vs one bot at a time) or the editor model needs
  to grow. **Decision needed: are early levels strictly heads-up, with multiway as a later quest?**

---

## 2. Currency & rewards: the nuclear/particle theme

Idea: instead of one flat chip-style currency, give **different rewards per level**, themed to our
**nuclear physics** identity. Each level drops a different **particle** — a quark, a nucleon, an
elementary particle — and you **merge** them up a real physics hierarchy:

```
2 up quarks + 1 down quark   → proton
1 up quark  + 2 down quarks  → neutron
proton + electron            → hydrogen
…protons + neutrons + electrons → heavier atoms → molecules
```

The merge ladder *is* the meta-progression: a Candy-Crush-style "combine small things into bigger things"
loop, but the combinations are chemically real, so it doubles as a tiny bit of science. This is the part
the designer is most excited about (poker + chemistry).

### The honest concern
This might be **delightful to us and boring to most poker players.** Poker players are the core audience;
a chemistry crafting tree they didn't ask for could feel like homework. So:
- **Keep the currency idea** (per-level distinct rewards, a merge/collection meta-layer) as a commitment.
- **Keep particles as *an* idea**, not *the* idea — to be validated, not assumed.
- We need to decide whether the theme is **load-bearing** (you must understand the hierarchy to progress)
  or **flavor** (rewards merge into prettier rewards; the physics is just skin and you can ignore it).
  Flavor is the safer default — it can't bore anyone who doesn't care, and it delights those who do.

---

## 3. Alternative theme: extraction / mining → building blocks

If pure particle physics is too niche, reskin the same merge mechanic around **extraction** with a more
relatable story arc:

- **Early levels = the mines.** You pull out raw materials: **gold, copper, oil, quartz**, etc. Tangible,
  everyone-gets-it rewards.
- **Later levels = building up.** You start combining those raw materials into bigger building blocks; the
  story gets a little more sophisticated as you climb.

This keeps the **collect → merge → bigger thing** loop and the science/material flavor, but anchors the
bottom of the ladder in things people already have intuitions about (you know what gold is; you may not
know what a down quark is). The particle hierarchy could even live *above* the materials as a late-game
prestige tier, so we keep both ideas instead of choosing.

### Theme options on the table
| Option | Hook | Risk |
|---|---|---|
| **Particles** (quarks → atoms → molecules) | Physically real, novel, on-brand "nuclear" | May read as homework to poker players |
| **Extraction** (ores/oil → building blocks) | Relatable, gentle on-ramp, clear story | Less distinctive; further from "nuclear" identity |
| **Hybrid** | Materials early, particles as prestige | More to build; theme has to stay coherent |

**Decision needed:** pick the *bottom-of-ladder* theme (what level 1 rewards feel like) before we model
the currency economy, since it sets the tone players meet first.

---

## 4. What's settled vs. open

**Settled (direction we're committing to):**
- Levels = tables of bots you beat to advance.
- Beating a level unlocks **automating your range** for it, via **capture-from-play** *and* a **manual
  editor**.
- The heads-up editor is **39 lines** (13 ranks × {BTN, SB vs pot, SB vs check}), three flip-pages,
  alternating-color squares, one "he always raises" line per rank.
- There **is** a meta-currency with **per-level distinct rewards** feeding a **merge/collection** layer.

**Open (needs a call before building):**
- Heads-up-only early levels, or multiway tables?
- Action-input UX for each square (cycle-tap vs. explicit buttons); re-raise depth display.
- Strategy completeness/validation + fallback for unspecified spots.
- Theme: particles vs. extraction vs. hybrid — and whether the theme is load-bearing or flavor.
- Whether merging is purely cosmetic progression or spends into something (unlocks, cosmetics, boosts).

---

## 5. Suggested next steps
1. **Lock the heads-up-only assumption** for the first level batch — it makes the 39-line editor exact
   and unblocks design.
2. **Prototype the range editor read-only first**: render the three pages from an existing `BotProfile`
   so we can eyeball the alternating-color "conversation" layout before wiring up editing.
3. **Add capture-from-play** on top once the table renders — it's just writing the current node's action
   into the same structure.
4. **Mock one level's reward** in both themes (one particle drop vs. one ore drop) and gut-check with a
   couple of poker players before committing the economy.
