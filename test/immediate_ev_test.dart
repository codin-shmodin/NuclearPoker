import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/ev/immediate_ev.dart';
import 'package:nuclear_poker/engine/game/action.dart';
import 'package:nuclear_poker/engine/game/hand_engine.dart';
import 'package:nuclear_poker/engine/game/hand_state.dart';
import 'package:nuclear_poker/engine/game/rule_config.dart';
import 'package:nuclear_poker/engine/game/seat.dart';
import 'package:nuclear_poker/engine/players/bot_profile.dart';

/// Immediate EV is **option A**: net chips from the start of the hand, for every
/// line that resolves the moment the villain answers. When our action hands the
/// decision back to us (we aggress and the villain re-raises, or we check and the
/// villain bets), the value is `null` — shown as "?".

const _rules = RuleConfig(smallBlind: 1, bigBlind: 1, startingStack: 50);

HandState _state({
  required int heroCommitted,
  required int heroStack,
  required int botCommitted,
  required int botStack,
  required int currentBet,
  required int raiseCount,
  required int toAct,
  bool botActed = false,
  GameAction? botLast,
}) {
  final hero = Seat(
      index: 0, playerId: 'h', name: 'You', isHuman: true, stack: heroStack)
    ..committed = heroCommitted;
  final bot = Seat(
      index: 1, playerId: 'b', name: 'Bot', isHuman: false, stack: botStack)
    ..committed = botCommitted
    ..hasActed = botActed
    ..lastAction = botLast;
  return HandState(
    seats: [hero, bot],
    button: 1,
    toAct: toAct,
    pot: heroCommitted + botCommitted,
    currentBet: currentBet,
    phase: HandPhase.betting,
  )..raiseCount = raiseCount;
}

const _callsKingPlus = BotProfile(
  id: 't',
  name: 't',
  blurb: 't',
  nodes: {BetNode.facingBet: NodeStrategy(callFrom: 13, raiseFrom: 99)},
);

const _raisesAce = BotProfile(
  id: 't',
  name: 't',
  blurb: 't',
  nodes: {
    BetNode.facingBet: NodeStrategy(callFrom: 99, raiseFrom: 14),
    BetNode.facingRaise: NodeStrategy(callFrom: 14, raiseFrom: 99),
  },
);

void main() {
  final engine = HandEngine(_rules, Random(0));
  ImmediateEvCalculator calc(BotProfile p) =>
      ImmediateEvCalculator(engine, p, heroSeat: 0, botSeat: 1);

  // Unraised pot, hero to act (both posted 1).
  HandState unraised() => _state(
        heroCommitted: 1,
        heroStack: 49,
        botCommitted: 1,
        botStack: 49,
        currentBet: 1,
        raiseCount: 0,
        toAct: 0,
      );

  test('bet, villain folds a worse hand → "No Value" (we win his chips)', () {
    final r =
        calc(_callsKingPlus).evaluate(unraised(), 14, [12], ActionType.bet);
    expect(r[12]!.ev, 1); // queen folds: his single chip comes to us
    expect(r[12]!.label, 'No Value');
  });

  test('bet, villain calls → "Value" ahead / "Called by Better" behind', () {
    final r =
        calc(_callsKingPlus).evaluate(unraised(), 14, [13], ActionType.bet);
    expect(r[13]!.ev, 3); // king calls the pot-to-3; ace wins matched 3
    expect(r[13]!.label, 'Value');

    final behind =
        calc(_callsKingPlus).evaluate(unraised(), 9, [13], ActionType.bet);
    expect(behind[13]!.ev, -3); // a nine gets called and loses the matched 3
    expect(behind[13]!.label, 'Called by Better');
  });

  test('bet, villain RAISES → unknown ("?"), we do not model our next move',
      () {
    final r = calc(_raisesAce).evaluate(unraised(), 3, [14], ActionType.bet);
    expect(r[14], isNull);
  });

  test('call → ± the matched amount, per card', () {
    // Villain opened to 3; hero (a queen) calls. Matched 3.
    final facingBet = _state(
      heroCommitted: 1,
      heroStack: 49,
      botCommitted: 3,
      botStack: 47,
      currentBet: 3,
      raiseCount: 1,
      toAct: 0,
      botActed: true,
      botLast: const GameAction.bet(3),
    );
    final r =
        calc(_callsKingPlus).evaluate(facingBet, 12, [14, 11], ActionType.call);
    expect(r[14]!.ev, -3); // queen loses to ace — we paid him off
    expect(r[14]!.label, 'Paid Off');
    expect(r[11]!.ev, 3); // queen beats jack — our call had showdown value
    expect(r[11]!.label, 'Showdown Value');
  });

  test('fold → we lose exactly what we already put in', () {
    final facingBet = _state(
      heroCommitted: 1,
      heroStack: 49,
      botCommitted: 3,
      botStack: 47,
      currentBet: 3,
      raiseCount: 1,
      toAct: 0,
      botActed: true,
      botLast: const GameAction.bet(3),
    );
    final r =
        calc(_callsKingPlus).evaluate(facingBet, 12, [14], ActionType.fold);
    expect(r[14]!.ev, -1);
    expect(r[14]!.label, ''); // folding gets no teaching label
  });

  test('check: showdown when villain checks back, "?" when villain bets', () {
    // Hero checks first; villain decides at the checked-to node. The pro checks
    // mid cards (showdown) and pots its strong/bluff cards (ball back to us).
    const potsAce = BotProfile(
      id: 't',
      name: 't',
      blurb: 't',
      nodes: {BetNode.checkedTo: NodeStrategy(betFrom: 14)},
    );
    final r =
        calc(potsAce).evaluate(unraised(), 13, [12, 14], ActionType.check);
    expect(r[12]!.ev, 1); // villain checks the queen → king wins the matched 1
    expect(r[12]!.label, ''); // checked to showdown — no teaching label
    expect(r[14], isNull); // villain bets the ace → our decision again, "?"
  });
}
