import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/ev/ev_calculator.dart';
import 'package:nuclear_poker/engine/game/action.dart';
import 'package:nuclear_poker/engine/game/hand_engine.dart';
import 'package:nuclear_poker/engine/game/hand_state.dart';
import 'package:nuclear_poker/engine/game/rule_config.dart';
import 'package:nuclear_poker/engine/game/seat.dart';
import 'package:nuclear_poker/engine/players/bot_profile.dart';
import 'package:nuclear_poker/engine/players/range_bot.dart' show BotMove;

/// These numbers are worked out by hand (see comments) — the point is to check
/// the EV logic against an *independent* derivation, not against the engine
/// re-running itself.

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
  final hero = Seat(index: 0, playerId: 'h', name: 'You', isHuman: true, stack: heroStack)
    ..committed = heroCommitted;
  final bot = Seat(index: 1, playerId: 'b', name: 'Bot', isHuman: false, stack: botStack)
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

/// A bot that simply folds everything it faces — lets us isolate fold equity.
const _alwaysFolds = BotProfile(
  id: 'folds',
  name: 'Folds',
  blurb: 'test',
  nodes: {
    BetNode.facingBet: NodeStrategy(callFrom: 99, raiseFrom: 99),
    BetNode.facingRaise: NodeStrategy(callFrom: 99, raiseFrom: 99),
  },
);

void main() {
  final engine = HandEngine(_rules, Random(0));
  EvCalculator calc(BotProfile p) =>
      EvCalculator(engine, p, heroSeat: 0, botSeat: 1);

  test('fold equity = the chips the villain put in, NOT the whole pot', () {
    // Unraised pot: each posted 1 (pot 2). Hero pots (opens), villain folds.
    // Hero wins the villain's single chip — the bet comes back. So +1, not +2.
    final state = _state(
      heroCommitted: 1, heroStack: 49,
      botCommitted: 1, botStack: 49,
      currentBet: 1, raiseCount: 0, toAct: 0,
    );
    final r = calc(_alwaysFolds).evaluate(state, 14, [13, 12], ActionType.bet);

    expect(r.villainResponse, {13: BotMove.fold, 12: BotMove.fold});
    expect(r.perCard[13], 1.0);
    expect(r.perCard[12], 1.0);
    expect(r.ev, 1.0);
  });

  test('fold equity after a bet = half the pre-bet pot + the bet', () {
    // Villain opened to 3 (its 1 ante + a 2 bet). Hero raises, villain folds.
    // Hero wins the villain's committed 3 = (½ of the pre-bet pot of 2) + 2.
    final state = _state(
      heroCommitted: 1, heroStack: 49,
      botCommitted: 3, botStack: 47,
      currentBet: 3, raiseCount: 1, toAct: 0,
      botActed: true, botLast: const GameAction.bet(3),
    );
    final r = calc(_alwaysFolds).evaluate(state, 14, [13], ActionType.bet);
    expect(r.perCard[13], 3.0);
    expect(r.ev, 3.0);
  });

  test('calling to showdown = ±the matched amount, per card', () {
    // Villain opened to 3; hero (a queen) calls. Both end with 3 in → matched 3.
    // Beats a jack (+3), loses to an ace (−3); over {A,J} the EV is 0.
    final state = _state(
      heroCommitted: 1, heroStack: 49,
      botCommitted: 3, botStack: 47,
      currentBet: 3, raiseCount: 1, toAct: 0,
      botActed: true, botLast: const GameAction.bet(3),
    );
    final r = calc(_alwaysFolds).evaluate(state, 12, [14, 11], ActionType.call);
    expect(r.perCard[14], -3.0); // queen loses to ace
    expect(r.perCard[11], 3.0); // queen beats jack
    expect(r.ev, 0.0);
  });

  test('mixed range: pot value = fold equity + paid-off value, averaged', () {
    // Hero has an ace, pots an unraised pot. Villain calls the king (paying
    // off), folds the queen. Call with K → showdown matched 3, ace wins → +3;
    // fold the Q → fold equity +1. EV = (3 + 1)/2 = 2.
    const callsKingPlus = BotProfile(
      id: 't', name: 't', blurb: 't',
      nodes: {BetNode.facingBet: NodeStrategy(callFrom: 13, raiseFrom: 99)},
    );
    final state = _state(
      heroCommitted: 1, heroStack: 49,
      botCommitted: 1, botStack: 49,
      currentBet: 1, raiseCount: 0, toAct: 0,
    );
    final r = calc(callsKingPlus).evaluate(state, 14, [13, 12], ActionType.bet);
    expect(r.villainResponse, {13: BotMove.call, 12: BotMove.fold});
    expect(r.perCard[13], 3.0); // king calls → ace wins matched 3
    expect(r.perCard[12], 1.0); // queen folds → fold equity
    expect(r.ev, 2.0);
  });

  test('later-betting value = best response minus the passive call-down', () {
    // Hero (a 3) pots an unraised pot to 3. The villain's ace re-raises to 9.
    // Passive line: hero calls to 9, loses at showdown → direct = −9.
    // Best response: hero folds → total = −3 (only the 3 already in).
    // The +6 difference is the "later betting" value: folding saves 6 chips.
    const raisesAce = BotProfile(
      id: 't', name: 't', blurb: 't',
      nodes: {
        BetNode.facingBet: NodeStrategy(callFrom: 99, raiseFrom: 13),
        // The ace never lays down — so hero can't profitably 4-bet-bluff it,
        // and folding really is the best response.
        BetNode.facingRaise: NodeStrategy(callFrom: 14, raiseFrom: 99),
        BetNode.facingReraise: NodeStrategy(callFrom: 14, raiseFrom: 99),
      },
    );
    final state = _state(
      heroCommitted: 1, heroStack: 49,
      botCommitted: 1, botStack: 49,
      currentBet: 1, raiseCount: 0, toAct: 0,
    );
    final r = calc(raisesAce).evaluate(state, 3, [14], ActionType.bet);
    expect(r.perCardDirect[14], -9.0); // call the shove and lose
    expect(r.perCard[14], -3.0); // fold instead — only the 3 already in
    expect(r.perCard[14]! - r.perCardDirect[14]!, 6.0); // later-betting value
  });

  test('the three personalities are actually different', () {
    // Facing a bet with a ten: rock folds, the pro calls, the maniac calls too;
    // facing a bet with a deuce: only the maniac defends (a bluff-raise).
    expect(BotProfile.rock.moveAt(BetNode.facingBet, 10), BotMove.fold);
    expect(BotProfile.pro.moveAt(BetNode.facingBet, 10), BotMove.call);
    expect(BotProfile.maniac.moveAt(BetNode.facingBet, 2), BotMove.pot);
    expect(BotProfile.rock.moveAt(BetNode.facingBet, 2), BotMove.fold);
  });
}
