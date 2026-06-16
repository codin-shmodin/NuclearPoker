# NuclearPoker — Market Research Report

**Date:** 2026-06-14
**Subject:** Market landscape for a gamified single-player vs-AI poker app (iOS/Android/web), chips-as-table-tool-only (no cash-out), with a Candy Crush-style progression/reward meta layer. Solo dev, low-cost PoC.

> All figures below survived 3-vote adversarial verification. Confidence is noted per section. Self-reported vendor/marketing figures and dated benchmarks are flagged in Caveats.

---

## Executive Summary

The poker software market splits into distinct verticals: real-money rooms (rake-based: GGPoker takes a flat ~5% cash rake), play-money/social poker (declining — the social-poker market fell from ~$203M in 2013 to a projected ~$156M by 2017), high-priced GTO study tools (GTO Wizard, $0–$279/mo), and quiz/trainer apps (POKER Q'z at ~$35/mo). The strongest retention and monetization playbook for NuclearPoker comes **not from poker products but from the match-3 / learning-game genre**: Royal Match and Duolingo demonstrate that battle passes, near-miss-driven IAP, live-ops event calendars, and streaks are the proven levers, with match/puzzle games posting the best retention of any genre (~32.6% Day 1, ~7.1% Day 30). F2P/IAP is the dominant model to target (~$111B mobile F2P revenue in 2023). A solo dev can build a working vs-AI Texas Hold'em PoC on a Unity + Firebase free-tier stack, so the differentiation and risk live in the **meta-layer design**, not the core game.

---

## Part 1 — Poker Products

### Real-money online poker (rake model)

| Product | Model | Key facts |
|---|---|---|
| **GGPoker** | Rake / tournament fees | Flat **5%** cash-game rake (incl. preflop charges on 3-bet pots — unusual; most rooms use No Flop No Drop), **7%** on Spin games, **9–5%** on tournaments by buy-in. |
| **PokerStars** | Rake / fees | Largest competitor; precise rake figures were **refuted** in verification (see Caveats) — do not cite specific PokerStars rake numbers from this report. |

**Retention hooks:** real cash withdrawal, rakeback/loyalty tiers, large player liquidity. *Not directly applicable to NuclearPoker (no cash-out), but the rake economics explain why social/play-money poker exists as a separate, ad/IAP-funded category.*

### Play-money / social poker

| Product | Model | Key facts |
|---|---|---|
| **Zynga Poker** | Free-to-play, chip IAP | Largest historical social-poker brand; revenue from voluntary chip/bonus purchases (play money at tables). |
| **Social poker market (genre)** | F2P | **Declining**: ~$203M (2013) → ~$179M (2015 proj.) → ~$156M (2017 proj.), per SuperData. Zynga held ~61% share. |

**Takeaway:** social poker is a shrinking, mature category — a warning that "another play-money poker table" is not enough. The meta-layer is the differentiator.

### GTO solvers / study tools

| Product | Model | Pricing | Core product |
|---|---|---|---|
| **GTO Wizard** | Subscription SaaS | 5 tiers: **Free $0**, Starter **$49**, Premium **$99**, Elite **$169**, Ultra **$279**/mo (annual: $39/$79/$139/$229). | **10M+ pre-solved GTO solutions** + **GTO Trainer with real-time feedback**. (March 2026 pricing.) |
| **PioSolver / Solver+** | One-time / license | Desktop solver class; not separately verified here. | Custom solve engine (the "compute it yourself" tier). |

**Retention hooks:** recurring subscription, ever-growing solution library, real-time correctness/EV feedback loop. The "real-time feedback after every action" mechanic is **directly transferable** to NuclearPoker's learn-while-you-play loop.

### Poker quiz / trainer apps (the closest analog to NuclearPoker)

| Product | Model | Pricing | Core product |
|---|---|---|---|
| **POKER Q'z (AI GTO Trainer)** | Freemium (free download + IAP/subs) | **$34.99/mo or $209.99/yr** per track (Ring *or* Tournament); point IAPs **$0.49–$1.99**; **$2.99** 1-day ticket. | Quiz-based GTO training: **100,000+ real hand scenarios**, built-in poker **AI Q&A**, **300+ lessons** (beginner→MTT), **AI personalized quiz** targeting weak areas, embedded **mini-games** (Blackjack, Video Poker). |

**Why this matters most:** POKER Q'z already fuses poker + GTO + gamification + progression + mini-games + AI under a freemium/sub model. It is the single most direct competitor/template for NuclearPoker's positioning, and validates the price points and feature mix.

### Other poker categories (for completeness)

- **Tracking/HUD software** (PokerTracker, Hold'em Manager): one-time/subscription desktop tools overlaying stats on real-money tables. Not applicable to a closed single-player app.
- **Home-game / private-table apps** (Pokerrrr 2, PokerNow): host private games; social/multiplayer focus.
- **Odds/equity calculators**: utility apps, often free/ad-supported.
- **Online courses/coaching** (Upswing Poker, Run It Once, Raise Your Edge): video course + subscription/one-time-purchase model; community + structured curricula are the retention hook.

---

## Part 2 — Progression & Learning-Based Games (the design playbook)

This genre — not poker — holds the proven retention and monetization mechanics for NuclearPoker's meta-layer.

### Royal Match (match-3 / live-ops exemplar)

| Lever | Detail |
|---|---|
| **Escalating end-of-round IAP** | Extra moves priced **$2 → $4.35 → $6.65 → $8.95** (coin-equivalent) — **highest in the genre**; engineered around **near-miss / loss-aversion** psychology ("banks on players getting triggered"). |
| **Premium battle pass (Royal Pass)** | **>$10/mo** (vs Homescapes $4.99, Candy Crush $6.99). Rewards: **temporary +60% lives**, **golden profile frame** (cosmetic prestige). |
| **Live-ops event calendar** | Measured launch lifts: **Royal Pass +31% revenue**, **Endless Treasure +20%**, **Sky Race +12%**, **Lightning Rush +9%**, **King's Nightmare +3% D14 retention**. |

**Takeaway:** rotating events + a premium pass + near-miss-driven micro-IAP are the revenue engine. The "lives/energy" cap creates the pressure that makes the IAP and pass valuable.

### Duolingo (learn-while-you-play / streak exemplar)

| Lever | Detail |
|---|---|
| **Streaks** | Duolingo calls streaks **"the single most effective retention lever in the product."** |
| **Social streaks** | Users with ≥1 **Friend Streak** are **22% more likely** to complete their daily lesson. |

**Takeaway:** a daily streak + social streak layer is the cheapest, highest-leverage retention mechanic and maps perfectly onto a "play a poker hand/quiz daily" loop.

### Genre retention & monetization benchmarks

| Metric | Value | Source vintage |
|---|---|---|
| Avg mobile game retention | D1 **29.46%**, D7 **8.7%**, D30 **3.21%** (target D1 ≈ **30%**) | AppsFlyer Q3 2022 |
| **Match/puzzle genre** (best of all genres) | D1 **32.6%**, D7 **~14%**, D30 **7.1%** | AppsFlyer 2022 / Business of Apps 2026 |
| iOS vs Android retention | iOS **35.7%** D1 / **5%** D30 vs Android **27.5%** / **2.6%** | Business of Apps 2026 |
| F2P mobile revenue (2023) | **~$111.37B** worldwide; F2P/IAP is the dominant model | Statista via Plarium (see caveat) |

---

## Part 3 — Newcomer Primer: Types & Terminology

**Game / monetization types**
- **F2P (free-to-play):** free download; revenue from IAP and/or ads.
- **Freemium:** free core + paid upgrades/subscriptions.
- **Social casino:** casino-style games (poker, slots) using **play money**, no cash-out; monetized via chip IAP. (NuclearPoker sits here.)
- **Gacha:** randomized reward pulls for currency (loot-box mechanic).
- **Battle pass:** time-limited tiered reward track, free + premium lane (e.g. Royal Pass).
- **Live-ops:** ongoing operation of rotating events/sales/content to drive engagement & revenue.

**Currencies & mechanics**
- **Soft currency:** earned in-game (chips/coins), freely granted.
- **Hard currency:** bought with real money (gems), gates premium content.
- **Energy / lives mechanic:** capped resource that regenerates over time or via purchase; creates session pacing and IAP pressure.
- **Meta-game:** the progression/reward layer *around* the core game (the Candy Crush map, the poker meta-layer NuclearPoker is built on).
- **Near-miss / loss aversion:** designing almost-wins to trigger "one more try" / extra-move purchases.

**Metrics**
- **DAU / MAU:** daily / monthly active users.
- **ARPU / ARPPU:** average revenue per user / per *paying* user.
- **Retention (D1/D7/D30):** % of installs still active after N days.

**Poker-specific**
- **GTO (Game Theory Optimal):** mathematically unexploitable strategy; the basis of solvers/trainers.
- **Rake:** the house's cut of real-money pots/tournaments (GGPoker ~5%). N/A to play-money apps — explains why social poker monetizes via IAP instead.

---

## Part 4 — Actionable Takeaways for NuclearPoker

1. **Build cheap, differentiate on meta.** A Unity (C#) + Firebase (free-tier auth/leaderboards/analytics) stack lets a solo dev ship an offline vs-AI Texas Hold'em PoC; verified open-source builds exist. Spend the effort on the progression layer.
2. **Steal from match-3, not from poker.** Royal Match's near-miss IAP + premium battle pass + rotating live-ops calendar are the proven revenue levers; social poker revenue is *declining*.
3. **Streaks first.** Duolingo's streak (and social/friend streak, +22% daily completion) is the cheapest retention win and fits a daily-hand/daily-quiz loop.
4. **Adopt the quiz-trainer template.** POKER Q'z proves the poker+GTO+gamification+AI+mini-games freemium bundle works at ~$35/mo subs + micro-IAP — directly validates pricing and feature mix.
5. **Aim for match-3-class retention (~30% D1).** Use lives/energy + meta-progression to pace sessions; prioritize iOS (higher retention).
6. **Monetize via F2P/IAP** (chips as soft currency, gems as hard currency, optional battle pass), the dominant ~$111B model — with an optional study/coaching subscription tier modeled on GTO Wizard's real-time-feedback trainer.

---

## Caveats & Time-Sensitivity

- **Self-reported figures:** POKER Q'z scenario counts, Royal Match event-lift %, and Duolingo streak stats are vendor/analyst self-reported (correlational, not audited). Directionally reliable; treat exact numbers as indicative.
- **F2P revenue number:** the **$111.37B** Statista figure is internally inconsistent with stronger trackers (Sensor Tower $76.7B, Newzoo ~$92.6B for 2023) — likely a broader definition. The *dominance of F2P/IAP* is robust; the precise dollar figure is not.
- **Dated benchmarks:** core retention benchmarks derive from **AppsFlyer Q3 2022** data (~3.5 yrs old) but remain broadly valid per 2025–2026 sources.
- **PokerStars rake:** specific PokerStars rake claims were **refuted** in verification — excluded.
- **GTO Wizard pricing** reflects the **March 2026** restructuring; Ultra's $279 may be a promotional "Early Bird" rate. Subscription prices change frequently.
- **GGPoker effective rake** drops below 5% at high stakes once the 3BB cap is hit; the 5% is the nominal flat rate.
- **Refuted/uncertain (excluded):** WSOP "3.25M players / overtaking Zynga" claim; "Zynga monetizes purely via IAP, no rake" framing; "Duolingo 32M 7-day-streak DAU"; "only 26.1% of F2P players spend."

---

## Open Questions

1. **Legal/regulatory:** Where does a "play-money poker, no cash-out" app fall under social-casino and gambling regulations across iOS/Android app stores and key jurisdictions?
2. **AI opponent quality vs cost:** Can a solo dev ship an AI bot that is *fun and beatable-but-challenging* (not just hand-strength heuristics) without expensive GTO compute?
3. **Sub vs IAP mix for poker-trainer apps:** What is the actual revenue split / conversion rate for POKER Q'z-style apps (subscription vs micro-IAP)? Not found.
4. **Meta-layer fit:** Does a match-3-style energy/lives + map progression actually retain *poker* players, or does poker's own variance/session structure conflict with an energy gate? Needs prototyping/playtesting.
