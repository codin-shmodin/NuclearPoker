import 'dart:math';

import '../cards/deck.dart';
import 'action.dart';
import 'game_view.dart';
import 'hand_state.dart';
import 'payout.dart';
import 'rule_config.dart';
import 'seat.dart';

/// Pure-Dart rules engine for simple one-card poker:
/// deal 1 card each → a single betting round (check / call / fold + bet/raise
/// in fixed increments, uncapped — raise until all-in) → showdown high card,
/// ties split, with side pots for all-ins.
///
/// No Flutter dependencies: unit-testable and runnable headless.
class HandEngine {
  HandEngine(this.rules, this.rng);

  final RuleConfig rules;
  final Random rng;

  /// Deals a fresh hand. [seats] keep their stacks; everything else is reset.
  /// Seats with no chips sit the hand out: no card, no blinds, never to act.
  HandState start(List<Seat> seats, int button) {
    final deck = Deck(rng);
    var pot = 0;
    for (final seat in seats) {
      seat.resetForHand();
      if (seat.stack <= 0) {
        seat.folded = true; // sitting out
        seat.card = null;
        continue;
      }
      seat.card = deck.draw();
      pot += _post(seat, rules.ante);
    }

    final state = HandState(
      seats: seats,
      button: button,
      toAct: 0,
      pot: pot,
      currentBet: 0,
      phase: HandPhase.betting,
    );

    // Not enough funded players for a hand — nothing to do.
    if (state.liveSeats.length < 2) {
      state.toAct = -1;
      state.phase = HandPhase.complete;
      if (state.liveSeats.isNotEmpty) state.winners.add(state.liveSeats.first.index);
      return state;
    }

    if (rules.bigBlind > 0) {
      final headsUp = state.liveSeats.length == 2;
      // Heads-up: the button is the small blind and acts first preflop.
      final sb = headsUp
          ? _nextActive(seats, button)
          : _nextActive(seats, button + 1);
      final bb = _nextActive(seats, sb + 1);
      state.pot += _post(seats[sb], rules.smallBlind);
      state.pot += _post(seats[bb], rules.bigBlind);
      state.currentBet = rules.bigBlind;
      state.smallBlindSeat = sb;
      state.bigBlindSeat = bb;
      state.toAct = headsUp ? sb : _nextActive(seats, bb + 1);
    } else {
      state.toAct = _nextActive(seats, button + 1);
    }

    state.log.add('New hand dealt, pot ${state.pot}.');
    return state;
  }

  /// First non-folded (in-hand) seat at or after [from], cyclically.
  int _nextActive(List<Seat> seats, int from) {
    final n = seats.length;
    for (var s = 0; s < n; s++) {
      final idx = (from + s) % n;
      if (!seats[idx].folded) return idx;
    }
    return from % n;
  }

  /// Moves up to [amount] chips from [seat] into the pot (respecting its stack)
  /// and records it as committed this round. Returns the amount posted.
  int _post(Seat seat, int amount) {
    final posted = min(amount, seat.stack);
    seat.stack -= posted;
    seat.committed += posted;
    return posted;
  }

  /// Whether [seat] may currently open a bet or raise. No raise cap: as long as
  /// the seat has even one chip beyond a call, it can raise (going all-in for
  /// less than a full increment if that's all it has).
  bool _canBet(HandState state, Seat seat) {
    if (seat.stack <= 0) return false;
    final toCall = state.currentBet - seat.committed;
    return seat.stack > toCall;
  }

  /// Returns the legal actions for whoever is currently to act.
  List<ActionType> legalActions(HandState state) {
    if (state.phase != HandPhase.betting || state.toAct < 0) return const [];
    final seat = state.seats[state.toAct];
    final toCall = state.currentBet - seat.committed;
    final actions = <ActionType>[];
    if (toCall > 0) {
      actions.add(ActionType.fold);
      if (seat.stack > 0) actions.add(ActionType.call);
    } else {
      actions.add(ActionType.check);
    }
    if (_canBet(state, seat)) actions.add(ActionType.bet);
    return actions;
  }

  /// Applies [action] for the seat currently to act, then advances the hand.
  /// Illegal actions throw [StateError].
  HandState applyAction(HandState state, GameAction action) {
    if (state.phase != HandPhase.betting || state.toAct < 0) {
      throw StateError('No action expected: phase=${state.phase}');
    }
    final seat = state.seats[state.toAct];
    final toCall = state.currentBet - seat.committed;

    switch (action.type) {
      case ActionType.check:
        if (toCall > 0) {
          throw StateError('Cannot check facing a bet of $toCall.');
        }
        seat.hasActed = true;
        seat.lastAction = const GameAction.check();
        state.log.add('${seat.name} checks.');
        break;

      case ActionType.bet:
        if (!_canBet(state, seat)) {
          throw StateError('Cannot bet/raise now.');
        }
        final verb = state.currentBet > 0 ? 'raises to' : 'bets';
        // True pot-sized bet/raise: raise TO (current bet + pot + your call).
        // Opening (call 0) → currentBet + pot. Facing a bet → adds the pot you'd
        // make by calling first, then bets that — the standard pot-limit raise.
        final toCall = state.currentBet - seat.committed;
        final callAmount = toCall > 0 ? toCall : 0;
        final raiseBy = state.pot + callAmount;
        final target = state.currentBet + (raiseBy > 0 ? raiseBy : 1);
        final add = min(target - seat.committed, seat.stack);
        seat.stack -= add;
        seat.committed += add;
        state.pot += add;
        state.currentBet = max(state.currentBet, seat.committed);
        state.raiseCount += 1;
        seat.hasActed = true;
        seat.lastAction = GameAction.bet(seat.committed);
        state.log.add('${seat.name} $verb ${seat.committed}.');
        break;

      case ActionType.call:
        if (toCall <= 0) throw StateError('Nothing to call.');
        final amount = min(toCall, seat.stack);
        seat.stack -= amount;
        seat.committed += amount;
        state.pot += amount;
        seat.hasActed = true;
        seat.lastAction = GameAction.call(amount);
        state.log.add('${seat.name} calls $amount.');
        break;

      case ActionType.fold:
        seat.folded = true;
        seat.hasActed = true;
        seat.lastAction = const GameAction.fold();
        state.log.add('${seat.name} folds.');
        break;
    }

    _advance(state);
    return state;
  }

  void _advance(HandState state) {
    final live = state.liveSeats;
    // Everyone folded but one → that seat wins the whole pot without a showdown.
    if (live.length == 1) {
      _settleUncontested(state, live.first.index);
      return;
    }

    final n = state.seats.length;
    for (var step = 1; step <= n; step++) {
      final idx = (state.toAct + step) % n;
      final seat = state.seats[idx];
      if (_needsToAct(seat, state)) {
        state.toAct = idx;
        return;
      }
    }

    // No one left to act → showdown.
    state.toAct = -1;
    _showdown(state);
  }

  /// A seat must act if it isn't folded, isn't all-in, and either hasn't acted
  /// yet or still owes chips to match the current bet. The stack check is what
  /// prevents an all-in player from being asked to act forever.
  bool _needsToAct(Seat seat, HandState state) {
    if (seat.folded || seat.stack <= 0) return false;
    return !seat.hasActed || seat.committed < state.currentBet;
  }

  void _showdown(HandState state) {
    state.phase = HandPhase.showdown;
    _settleSidePots(state, reveal: true);
  }

  /// Fold-out: the last remaining player takes the entire pot (this naturally
  /// returns any uncalled portion of their own bet).
  void _settleUncontested(HandState state, int winnerIndex) {
    final winner = state.seats[winnerIndex];
    winner.stack += state.pot;
    winner.lastWin = state.pot;
    state.winners
      ..clear()
      ..add(winnerIndex);
    state.phase = HandPhase.complete;
    state.log.add('${winner.name} wins ${state.pot} uncontested.');
  }

  /// Showdown with ≥2 live players: build side pots by contribution layers and
  /// award each to the best card among players eligible for that layer.
  void _settleSidePots(HandState state, {required bool reveal}) {
    // Return uncalled chips first: the lone biggest bettor can't win more than
    // the next-highest contribution actually matched it. The excess (e.g. a
    // pot-sized all-in nobody fully called) is refunded, NOT won — otherwise it
    // would look like that player split the pot.
    final contributors = [
      for (final s in state.seats)
        if (s.committed > 0) s.index,
    ];
    if (contributors.length >= 2) {
      contributors.sort((a, b) =>
          state.seats[b].committed.compareTo(state.seats[a].committed));
      final top = state.seats[contributors[0]];
      final secondAmount = state.seats[contributors[1]].committed;
      if (top.committed > secondAmount) {
        final refund = top.committed - secondAmount;
        top.stack += refund;
        top.committed -= refund;
        state.pot -= refund;
      }
    }

    final remaining = {
      for (final s in state.seats)
        if (s.committed > 0) s.index: s.committed,
    };

    final winnings = <int, int>{};
    while (remaining.values.any((v) => v > 0)) {
      final level = remaining.values.where((v) => v > 0).reduce(min);
      final contributors = remaining.keys.toList();
      final amount = level * contributors.length;
      for (final i in contributors) {
        remaining[i] = remaining[i]! - level;
      }
      remaining.removeWhere((_, v) => v <= 0);

      final eligible = contributors.where((i) => !state.seats[i].folded).toList();
      if (eligible.isEmpty) continue; // dead chips (shouldn't happen at showdown)

      var best = -1;
      for (final i in eligible) {
        best = max(best, state.seats[i].card!.rank.value);
      }
      final potWinners =
          eligible.where((i) => state.seats[i].card!.rank.value == best).toList();
      final share = amount ~/ potWinners.length;
      var odd = amount - share * potWinners.length;
      for (final i in potWinners) {
        var amt = share;
        if (odd > 0) {
          amt += 1;
          odd -= 1;
        }
        winnings[i] = (winnings[i] ?? 0) + amt;
      }
    }

    final payouts = <Payout>[];
    winnings.forEach((i, amt) {
      state.seats[i].stack += amt;
      state.seats[i].lastWin = amt;
      payouts.add(Payout(i, amt));
    });

    state.winners
      ..clear()
      ..addAll(winnings.keys);
    state.phase = HandPhase.complete;

    final names = state.winners.map((i) => state.seats[i].name).join(', ');
    state.log.add(reveal
        ? 'Showdown: $names win${state.winners.length > 1 ? '' : 's'} the pot.'
        : '$names wins the pot.');
  }

  /// Builds the redacted view for [seatIndex] — the only thing a player sees.
  GameView buildView(HandState state, int seatIndex) {
    final me = state.seats[seatIndex];
    final toCall = (state.currentBet - me.committed).clamp(0, me.stack);
    final canBet = _canBet(state, me);
    final callForRaise = state.currentBet - me.committed;
    final raiseBy = state.pot + (callForRaise > 0 ? callForRaise : 0);
    final raiseTarget = min(
      state.currentBet + (raiseBy > 0 ? raiseBy : 1),
      me.committed + me.stack,
    );
    return GameView(
      myCard: me.card!,
      mySeatIndex: seatIndex,
      myStack: me.stack,
      pot: state.pot,
      toCall: toCall,
      currentBet: state.currentBet,
      canCheck: toCall == 0,
      canCall: toCall > 0,
      canBet: canBet,
      raiseTarget: raiseTarget,
      isOpen: state.raiseCount == 0,
      raiseCount: state.raiseCount,
      activePlayers: state.liveSeats.length,
      opponents: [
        for (final s in state.seats)
          if (s.index != seatIndex)
            OpponentView(
              seatIndex: s.index,
              name: s.name,
              stack: s.stack,
              folded: s.folded,
              committed: s.committed,
              lastAction: s.lastAction,
            ),
      ],
    );
  }
}
