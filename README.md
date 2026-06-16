# NuclearPoker

A gamified poker app (iOS / Android / web). Chips are only the betting tool at the
table — the game is the progression and the quests. Built with **Flutter**.

> **Quest 1 — One Card Poker** is implemented: each player gets one card, a single
> betting round (check / bet / call / fold), highest card wins. You play against
> simple AI personalities.

## Prerequisites

Flutter is **not yet installed** on this machine. Install it first:

```sh
# macOS (Homebrew)
brew install --cask flutter
flutter doctor          # follow any setup prompts (Xcode / Android toolchain)
```

See https://docs.flutter.dev/get-started/install for the full guide.

## Run it

From the project root:

```sh
# 1. Generate the native/web platform folders (does NOT touch lib/ or pubspec).
flutter create --platforms=ios,android,web .

# 2. Fetch dependencies.
flutter pub get

# 3. Run (web is the fastest to try; or pick a device/simulator).
flutter run -d chrome
```

## Tests

```sh
flutter test
```

## Project layout

```
lib/
  main.dart, app.dart            App entry + MaterialApp/theme.
  theme/                         Colors + ThemeData.
  home/                          Quest map / start screen.
  engine/                        PURE DART game logic (no Flutter imports):
    cards/                         Rank, Suit, PlayingCard, Deck.
    game/                          Action, Seat, RuleConfig, GameView,
                                   HandState, HandEngine (rules + state machine),
                                   Payout.
    players/                       PokerPlayer interface, SimpleAiPlayer
                                   (personality presets), HumanPlayer.
  features/quest_one_card/       The Quest 1 feature:
    quest_controller.dart          ChangeNotifier driving a table vs AI.
    one_card_table_screen.dart     The table screen.
    widgets/                       Card, chips, seat, pot, action bar.
test/
  engine_test.dart               Engine rules / determinism tests.
docs/                            Design docs (stack, framework).
```

## Design notes

- **`engine/` has zero Flutter dependencies** so it stays unit-testable and can be
  extracted into a standalone package and run headless (e.g. to solve GTO) later.
- **Every opponent is a `PokerPlayer`.** Swapping the simple heuristic AI for a GTO
  bot later is a one-class change — nothing in the UI or engine changes.
- The AI is intentionally **simple and beatable** for now (card strength +
  personality knobs), not GTO.

See `docs/` for the stack rationale and the one-card-poker framework design.
