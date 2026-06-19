# Adventure Map (Level Progression)

> Status: **Plan / not yet built**, drafted 2026-06-19. The Candy-Crush-style level map that becomes the
> app's home screen. Scope is deliberately **heads-up only** (see [expansion-plans.md](./expansion-plans.md) §4).
> This doc is the data model + screen structure + wiring; **art is placeholder for now** and swaps in later
> with zero code change. Review before code.

---

## 1. What a "level" is (heads-up)

A level is **one heads-up match against one bot that you have to bust.** That's it. We already have the
whole mechanic — `HeadsUpController` exposes `botBusted` / `humanBusted` / `sessionOver`
(`headsup_controller.dart:188`), and busting the bot is already narrated as "you cleared the table." So:

> **Beat a level = bust that level's bot.** That event flips the level to *completed* and unlocks the next.

A level is therefore just **a named pairing of (a `BotProfile`, some table config)** plus map metadata
(position on the path, title, reward). The three existing profiles — Rocky / Vex / Sage
(`bot_profile.dart`) — are the first three levels' opponents, roughly in difficulty order. Later levels
add new profiles (tighter thresholds, better bluff frequencies, bigger starting stacks).

This keeps the engine untouched: the map is a **shell around the trainer we already have.**

---

## 2. Data model

Three small pieces: the **static level catalog**, the **player's progress**, and a **persistence layer**.

### 2.1 Level definition (static, compiled in)
```dart
class LevelDef {
  final int id;              // 1..N, also draw order along the path
  final String title;        // "The Rookie", "The Shark"...
  final String botProfileId; // -> resolves to a BotProfile (rocky/vex/sage/...)
  final int startingStack;   // table config; default 50
  final Offset mapPosition;  // normalized 0..1 position on the background (see §3)
  final String rewardId;     // particle/material dropped on first clear (themed later)
}
```
A const `List<LevelDef> kLevels` is the single source of truth for the ladder. Adding a level = adding
one entry (and, later, one bot profile + one art asset).

### 2.2 Progress (per player, mutable, persisted)
```dart
class LevelProgress {
  final Set<int> completedLevelIds; // which levels are beaten
  // derived: a level is UNLOCKED if id==1 or (id-1) is completed.
  //          LOCKED otherwise. COMPLETED if in the set.
}
```
We don't store "locked/unlocked" — it's **derived** from `completedLevelIds`, so there's one fact to
persist and no way for the two to disagree. (When levels branch instead of being a straight line, this
becomes a prerequisite map; linear is fine for now.)

### 2.3 Persistence — **new dependency needed**
There is **no persistence in the project today** (no `shared_preferences`, no Firebase wired —
confirmed in `pubspec.yaml`). For a PoC the cheapest correct choice is:

- **`shared_preferences`** — store `completedLevelIds` as a small JSON/string list on-device. One added
  dependency, no backend, works on all three platforms (iOS/Android/web).
- A thin `ProgressStore` interface (`Future<LevelProgress> load()` / `Future<void> markComplete(int id)`)
  so we can **swap the backing store for Firebase/Firestore later** (per the stack doc's live-ops plan)
  without touching the map UI.

**Decision to confirm:** start with `shared_preferences` now, Firebase later behind the same interface.
(Recommended — keeps the PoC offline-cheap and unblocks the map immediately.)

---

## 3. Screen structure

`AdventureMapScreen` **replaces `HomeScreen`** as the app's entry (the existing quest-card list is the
proto-version of exactly this). Layout, outermost → in:

1. **Scrollable container** — vertical `SingleChildScrollView` (the path is taller than one screen so it
   feels like a journey). Map scrolls; the title/HUD can stay pinned on top.
2. **Background art layer** — a full-width image sized to the path height. *Placeholder now*: a tiled
   gradient + simple drawn path. The image is a single asset reference, so swapping real art later is a
   one-line change.
3. **The path** — a curved line/dotted trail connecting node positions (drawn with `CustomPaint`, or just
   baked into the background art once we have real art).
4. **Level nodes** — one tappable widget per `LevelDef`, positioned via `mapPosition` × the map size.
   Each node renders one of three **states**:
   - **Locked** — dimmed, padlock icon, not tappable (we already do this exact treatment in
     `_QuestCard`, `home_screen.dart:118-124,193-196` — reuse the look).
   - **Unlocked** — gold glow, "play" affordance, tappable → launches the level.
   - **Completed** — checkmark/stars, shows the reward earned; replayable.
5. **HUD (pinned)** — title bar + a **reward tray** (the particle/material collection from
   expansion-plans §2). Placeholder counter for now.

### Unlock animation
When you return from a win, the newly-unlocked node animates from locked→unlocked (scale-pop + glow).
We already use `flutter_animate` (in `pubspec.yaml`, used throughout `home_screen.dart`), so this is a
`.animate().scale().shimmer()` on the target node — no new dependency.

---

## 4. Wiring: map ⇄ trainer

The loop, end to end:

```
AdventureMapScreen
  └─ tap an UNLOCKED node (LevelDef)
       └─ push HeadsUpScreen, configured with that level's BotProfile + startingStack
            (today the trainer is reached via BotPickerScreen → HeadsUpScreen;
             a level skips the picker and injects the chosen profile directly)
            └─ play the match...
                 └─ controller.botBusted == true  ──► result = WIN
                      └─ pop back to map with the level id
                           └─ ProgressStore.markComplete(id)
                                └─ next level derives as UNLOCKED, node animates open,
                                   reward drops into the tray
```

Two concrete touch-points in existing code:
- **`HeadsUpScreen` needs a "which bot + config" parameter.** Today `BotPickerScreen` chooses the profile;
  a level passes it in directly. Small constructor change, no engine change.
- **The win signal already exists** (`botBusted`). The map just needs the screen to *return a result*
  (win/quit) when it pops — a `Navigator.pop(context, LevelResult.win)` style hand-back.

`BotPickerScreen` can stay as a "free play / pick any opponent" entry alongside the map, or be retired —
**decision to confirm** (I'd keep it as a practice mode).

---

## 5. Placeholder-now, art-later

Everything above renders with **zero real art**:
- Background = gradient + `CustomPaint` path.
- Nodes = the existing gold-bordered circle/badge style from `_QuestCard`.
- Rewards = emoji/icon stand-ins (⚛️ ⚪ 🔶).

When you generate real assets in ChatGPT, the swap is: drop PNGs into `assets/map/`, register them in
`pubspec.yaml`, and point the background/node/reward widgets at them. **No structural code changes** —
the layout already positions everything by normalized coordinates, so art slots into the same frame.
(When we get there I'll hand you exact prompts, pixel sizes, and filenames.)

---

## 6. Decisions to confirm before I code
1. **Persistence:** `shared_preferences` now, Firebase behind the same interface later? *(recommended)*
2. **Entry screen:** map fully replaces the quest-card `HomeScreen`? *(yes — it's the same idea grown up)*
3. **BotPickerScreen:** keep as a separate free-play mode, or fold into the map? *(I'd keep it)*
4. **How many levels for the first cut?** Suggest **3** (Rocky → Vex → Sage) so we ship the full
   lock→play→win→unlock loop end to end before authoring more opponents.
5. **Replaying a completed level:** allowed and rewardless on repeat, or grind-able? *(suggest replayable,
   reward only on first clear)*

---

## 7. Build order (once confirmed)
1. Add `shared_preferences`; build `ProgressStore` + `LevelProgress` (pure Dart, unit-testable).
2. Define `LevelDef` + `kLevels` (3 levels mapped to the 3 existing profiles).
3. Parameterize `HeadsUpScreen` to accept a `BotProfile` + config; return a win/quit result on pop.
4. Build `AdventureMapScreen` with placeholder art: scroll, path, nodes (locked/unlocked/completed),
   pinned HUD + reward tray.
5. Wire map → level → win → `markComplete` → unlock animation + reward drop.
6. Swap `HomeScreen` for the map as app entry; keep `BotPickerScreen` as free-play.
7. *(later)* Real art swap; *(later)* the 39-line range editor unlock from expansion-plans §1.
