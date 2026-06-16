import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/cards/card.dart';
import 'package:nuclear_poker/engine/cards/rank.dart';
import 'package:nuclear_poker/engine/cards/suit.dart';
import 'package:nuclear_poker/engine/game/action.dart';
import 'package:nuclear_poker/engine/game/hand_engine.dart';
import 'package:nuclear_poker/engine/game/hand_state.dart';
import 'package:nuclear_poker/engine/game/rule_config.dart';
import 'package:nuclear_poker/engine/game/seat.dart';

List<Seat> _twoSeats(RuleConfig rules) => [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: true, stack: rules.startingStack),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: rules.startingStack),
    ];

void main() {
  const rules = RuleConfig(ante: 1, startingStack: 100);

  test('start() posts antes and seeds the pot', () {
    final engine = HandEngine(rules, Random(1));
    final seats = _twoSeats(rules);
    final state = engine.start(seats, 0);

    expect(state.pot, rules.ante * seats.length);
    for (final s in seats) {
      expect(s.stack, rules.startingStack - rules.ante);
      expect(s.card, isNotNull);
    }
    expect(state.phase, HandPhase.betting);
  });

  test('check-around goes to showdown and the higher card wins', () {
    final engine = HandEngine(rules, Random(42));
    final seats = _twoSeats(rules);
    final state = engine.start(seats, 0);

    // Both players check.
    engine.applyAction(state, const GameAction.check());
    engine.applyAction(state, const GameAction.check());

    expect(state.phase, HandPhase.complete);

    final v0 = seats[0].card!.rank.value;
    final v1 = seats[1].card!.rank.value;
    if (v0 == v1) {
      expect(state.winners.toSet(), {0, 1}); // tie → split
    } else {
      final expected = v0 > v1 ? 0 : 1;
      expect(state.winners, [expected]);
    }
  });

  test('a bet that everyone folds to wins the pot uncontested', () {
    final engine = HandEngine(rules, Random(7));
    final seats = _twoSeats(rules);
    final state = engine.start(seats, 0); // button 0 → seat 1 acts first

    expect(state.toAct, 1);
    engine.applyAction(state, const GameAction.bet(0)); // seat 1 bets (pot-sized)
    engine.applyAction(state, const GameAction.fold()); // seat 0 folds

    expect(state.phase, HandPhase.complete);
    expect(state.winners, [1]);
    // pot starts at 2 (antes), currentBet 0. seat1 bets pot(2) → target 2,
    // adds 1 over its ante; seat0 folds → seat1 takes the 3-chip pot.
    // seat1: 100 - 1(ante) - 1(bet) + 3(pot) = 101
    expect(seats[1].stack, 101);
  });

  test('cannot check when facing a bet', () {
    final engine = HandEngine(rules, Random(3));
    final seats = _twoSeats(rules);
    final state = engine.start(seats, 0);

    engine.applyAction(state, const GameAction.bet(0));
    expect(
      () => engine.applyAction(state, const GameAction.check()),
      throwsStateError,
    );
  });

  test('blinds are posted and the right seat acts first', () {
    const blindRules =
        RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 30);
    final engine = HandEngine(blindRules, Random(5));
    final seats = [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: true, stack: 30),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: 30),
      Seat(index: 2, playerId: 'c', name: 'C', isHuman: false, stack: 30),
    ];
    final state = engine.start(seats, 0); // button 0 → SB=1, BB=2, UTG=0

    expect(seats[1].stack, 29, reason: 'small blind posted');
    expect(seats[2].stack, 29, reason: 'big blind posted');
    expect(state.pot, 2);
    expect(state.currentBet, 1);
    expect(state.toAct, 0);

    // UTG facing the big blind may fold, call, or raise (open) — not check.
    final acts = engine.legalActions(state);
    expect(acts, containsAll(<ActionType>[
      ActionType.fold,
      ActionType.call,
      ActionType.bet,
    ]));
    expect(acts.contains(ActionType.check), isFalse);
  });

  test('players can re-raise (3-bet) with pot-sized raises', () {
    const r = RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 30);
    final engine = HandEngine(r, Random(11));
    final seats = [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: false, stack: 30),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: 30),
      Seat(index: 2, playerId: 'c', name: 'C', isHuman: false, stack: 30),
    ];
    final state = engine.start(seats, 0); // SB=1, BB=2, pot=2, currentBet=1, toAct=0

    // UTG opens pot-sized: raise to currentBet(1) + pot(2) + call(1) = 4.
    engine.applyAction(state, const GameAction.bet(0));
    expect(state.currentBet, 4);
    expect(state.raiseCount, 1);

    // 3-bet pot-sized: currentBet(4) + pot(6) + call(3) = 13.
    engine.applyAction(state, const GameAction.bet(0));
    expect(state.currentBet, 13);
    expect(state.raiseCount, 2);
  });

  test('raising is uncapped (5-bet and beyond allowed)', () {
    const r = RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 1000);
    final engine = HandEngine(r, Random(3));
    final seats = [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: false, stack: 1000),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: 1000),
      Seat(index: 2, playerId: 'c', name: 'C', isHuman: false, stack: 1000),
    ];
    final state = engine.start(seats, 0);

    var prev = state.currentBet;
    for (var i = 0; i < 5; i++) {
      engine.applyAction(state, const GameAction.bet(0));
      expect(state.currentBet, greaterThan(prev)); // each raise climbs, no cap
      prev = state.currentBet;
    }
    expect(state.raiseCount, 5);
  });

  test('a short stack can raise all-in for less than a full pot raise', () {
    const r = RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 100);
    final engine = HandEngine(r, Random(4));
    final seats = [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: false, stack: 100),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: 6), // SB
      Seat(index: 2, playerId: 'c', name: 'C', isHuman: false, stack: 100),
    ];
    final state = engine.start(seats, 0); // SB=seat1 (stack 6→5 after blind)

    engine.applyAction(state, const GameAction.bet(0)); // seat0 opens to 4
    // seat1 has 5 left; a full pot raise would be much bigger — it shoves to 6.
    engine.applyAction(state, const GameAction.bet(0));
    expect(seats[1].stack, 0);
    expect(state.currentBet, 6);
  });

  test('K vs A: the Ace wins outright, it is not a split', () {
    // Heads-up where one player over-shoves and the other calls all-in for less.
    // The uncalled chips are refunded, so only the real winner is listed.
    const r = RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 100);
    final engine = HandEngine(r, Random(0));
    final seats = [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: false, stack: 100),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: 100),
    ];
    final state = engine.start(seats, 0);
    // Force the hole cards: seat0 = Ace, seat1 = King.
    seats[0].card = const PlayingCard(Rank.ace, Suit.spades);
    seats[1].card = const PlayingCard(Rank.king, Suit.hearts);

    // Drive both all-in regardless of position.
    var guard = 0;
    while (state.phase == HandPhase.betting && guard++ < 20) {
      final acts = engine.legalActions(state);
      if (acts.contains(ActionType.bet)) {
        engine.applyAction(state, const GameAction.bet(0));
      } else if (acts.contains(ActionType.call)) {
        engine.applyAction(state, const GameAction.call(0));
      } else {
        engine.applyAction(state, const GameAction.check());
      }
    }

    expect(state.phase, HandPhase.complete);
    expect(state.winners, [0], reason: 'Ace beats King — single winner');
  });

  test('all-in for less is handled and the hand never hangs', () {
    const r = RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 30);
    final engine = HandEngine(r, Random(2));
    final seats = [
      Seat(index: 0, playerId: 'a', name: 'A', isHuman: false, stack: 30),
      Seat(index: 1, playerId: 'b', name: 'B', isHuman: false, stack: 3), // short
      Seat(index: 2, playerId: 'c', name: 'C', isHuman: false, stack: 30),
    ];
    const totalChips = 63;
    final state = engine.start(seats, 0); // SB=seat1 (short), BB=seat2, toAct=0

    engine.applyAction(state, const GameAction.bet(0)); // seat0 opens (pot-sized)
    engine.applyAction(state, const GameAction.call(0)); // seat1 calls all-in for less
    expect(seats[1].stack, 0);
    engine.applyAction(state, const GameAction.call(0)); // seat2 calls

    // Hand must resolve, not hang on the all-in player.
    expect(state.phase, HandPhase.complete);
    // Chips are conserved across side pots.
    final total = seats.fold<int>(0, (sum, s) => sum + s.stack);
    expect(total, totalChips);
  });

  test('opponent view never exposes hole cards', () {
    final engine = HandEngine(rules, Random(9));
    final seats = _twoSeats(rules);
    final state = engine.start(seats, 0);

    final view = engine.buildView(state, 0);
    // OpponentView has no card field at all — this just asserts the shape holds.
    expect(view.opponents.length, 1);
    expect(view.myCard, seats[0].card);
  });
}
