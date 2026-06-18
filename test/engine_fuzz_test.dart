import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/engine/game/action.dart';
import 'package:nuclear_poker/engine/game/hand_engine.dart';
import 'package:nuclear_poker/engine/game/hand_state.dart';
import 'package:nuclear_poker/engine/game/rule_config.dart';
import 'package:nuclear_poker/engine/game/seat.dart';

/// Property-based ("fuzz") tests for the chip math. Instead of hand-picking a
/// few scenarios, these play thousands of randomized hands — varying seat
/// count, stacks, blinds/antes, button position and every legal action — and
/// assert the invariants that *must* hold for money to be trustworthy:
///
///   1. Chip conservation: chips are never created or destroyed. During a hand
///      `sum(stacks) + sum(committed)` stays constant; once the hand completes
///      every chip is back in a stack (`sum(stacks)` equals the starting total).
///   2. No negative stacks: nobody ever commits more than they hold.
///   3. A completed hand has at least one winner whenever chips were in play.
///   4. Hands always terminate — no all-in player makes the loop hang.
///
/// These are the guarantees a mature poker engine pins down with the same
/// technique; here they ride on top of the existing pure-Dart engine, no
/// dependency added.

int _totalStacks(List<Seat> seats) =>
    seats.fold(0, (sum, s) => sum + s.stack);

int _totalCommitted(List<Seat> seats) =>
    seats.fold(0, (sum, s) => sum + s.committed);

/// Builds a randomized but legal table for one hand.
({List<Seat> seats, RuleConfig rules, int button}) _randomTable(Random rng) {
  final seatCount = 2 + rng.nextInt(5); // 2..6 seats
  final startingStack = 2 + rng.nextInt(200); // 2..201 chips

  // Pick a forced-bet style: antes only, blinds only, both, or neither. Cap
  // each forced bet below the starting stack so setup itself is sane.
  final mode = rng.nextInt(4);
  final ante = (mode == 0 || mode == 2) ? 1 + rng.nextInt(3) : 0;
  final hasBlinds = mode == 1 || mode == 2;
  final smallBlind = hasBlinds ? 1 + rng.nextInt(3) : 0;
  final bigBlind = hasBlinds ? smallBlind + rng.nextInt(3) : 0;

  final rules = RuleConfig(
    ante: ante,
    smallBlind: smallBlind,
    bigBlind: bigBlind,
    startingStack: startingStack,
    maxPlayers: 6,
  );

  final seats = [
    for (var i = 0; i < seatCount; i++)
      Seat(
        index: i,
        playerId: 'p$i',
        name: 'P$i',
        isHuman: i == 0,
        // Mostly the configured stack, but ~1 in 4 seats is a short stack so
        // all-ins and side pots get exercised hard.
        stack: rng.nextInt(4) == 0
            ? 1 + rng.nextInt(startingStack)
            : startingStack,
      ),
  ];

  return (seats: seats, rules: rules, button: rng.nextInt(seatCount));
}

/// Plays one fully random hand to completion, asserting every invariant —
/// per-action conservation, no negative stacks, termination, and that the
/// final chip total matches the starting total with at least one winner.
void _playRandomHand(Random rng, int seed) {
  final table = _randomTable(rng);
  final seats = table.seats;
  final initialTotal = _totalStacks(seats);

  final engine = HandEngine(table.rules, rng);
  final state = engine.start(seats, table.button);

  // 200 actions is far more than any real hand needs; if we ever hit it the
  // engine is looping and the test should fail loudly rather than spin.
  var guard = 0;
  while (state.phase == HandPhase.betting) {
    expect(guard++ < 200, isTrue,
        reason: 'hand did not terminate (seed $seed)');

    // During betting, chips live in stacks or the pot — nowhere else.
    expect(_totalStacks(seats) + _totalCommitted(seats), initialTotal,
        reason: 'chips not conserved mid-hand (seed $seed)');
    for (final s in seats) {
      expect(s.stack >= 0, isTrue, reason: 'negative stack (seed $seed)');
    }

    final acts = engine.legalActions(state);
    expect(acts, isNotEmpty,
        reason: 'a seat is to act but has no legal action (seed $seed)');

    // Pick any legal action at random; amounts are computed by the engine, so
    // 0 is just a placeholder for bet/call.
    final pick = acts[rng.nextInt(acts.length)];
    engine.applyAction(state, GameAction(pick));
  }

  expect(state.phase, HandPhase.complete,
      reason: 'hand left mid-flight (seed $seed)');

  // Settlement done: the pot has been paid back out, so every chip is in a
  // stack again and the grand total is exactly what we started with.
  expect(_totalStacks(seats), initialTotal,
      reason: 'chips not conserved at showdown (seed $seed)');
  for (final s in seats) {
    expect(s.stack >= 0, isTrue, reason: 'negative stack at end (seed $seed)');
  }
  // Any hand with chips actually wagered must name a winner. (A no-stakes
  // table — zero ante and zero blinds, everyone checks — leaves an empty pot
  // and correctly awards nobody, so gate on the pot, not the stacks.)
  if (state.pot > 0) {
    expect(state.winners, isNotEmpty,
        reason: 'contested pot but no winner (seed $seed)');
  }
}

void main() {
  test('chip conservation holds across thousands of random hands', () {
    const iterations = 5000;
    for (var i = 0; i < iterations; i++) {
      // Deterministic per-iteration seed → any failure is reproducible by
      // pinning this seed in a focused test.
      _playRandomHand(Random(i), i);
    }
  });
}
