import '../cards/card.dart';
import '../cards/rank.dart';
import '../cards/suit.dart';
import '../game/action.dart';
import '../game/hand_engine.dart';
import '../game/hand_state.dart';
import '../players/bot_profile.dart';
import '../players/range_bot.dart' show BotMove;

/// The exact EV of one hero action, in chips, measured as profit from the start
/// of the hand (so an uncalled bet that comes back is *not* counted as won —
/// fold equity equals exactly the chips the villain had committed).
class ActionEv {
  const ActionEv(this.ev, this.perCard, this.perCardDirect, this.villainResponse);

  /// Expected chips for the action, averaged over the villain's range.
  final double ev;

  /// Per villain rank value: hero's chips if the villain holds that card and
  /// both sides play out optimally (villain by its profile, hero by the
  /// range-based best response). This is [perCardDirect] + the later-betting
  /// premium.
  final Map<int, double> perCard;

  /// Per villain rank value: hero's chips if there is *no further raising* after
  /// this action — fold equity when the villain folds, or a straight call-down
  /// to showdown otherwise. This is the "easy to understand" part of the EV; the
  /// difference [perCard] − [perCardDirect] is the value that only materialises
  /// through later betting decisions (the "hard to wrap your head around" part).
  final Map<int, double> perCardDirect;

  /// The villain's immediate reply to this action, per rank value (for labels).
  final Map<int, BotMove> villainResponse;
}

/// Computes exact best-response EV against a fully transparent [BotProfile] in
/// the heads-up, single-round, pot-limit one-card game.
///
/// The villain is a known (deterministic-per-card) strategy, so the two-player
/// game collapses to a decision tree that we solve by backward induction. At
/// villain nodes we split the belief (the still-possible villain ranks) by the
/// move each card makes; at hero nodes we take the action that maximises EV
/// *over the whole belief* — never per-card, so the result is a real best
/// response, not a clairvoyant one. The tree is shallow (pot-limit raises reach
/// all-in in a few steps), so this is exact and cheap.
///
/// All chip arithmetic is delegated to the real [HandEngine] on cloned states,
/// so EV can never drift from how a hand actually plays.
class EvCalculator {
  EvCalculator(this.engine, this.profile,
      {required this.heroSeat, required this.botSeat});

  final HandEngine engine;
  final BotProfile profile;
  final int heroSeat;
  final int botSeat;

  // Hero's chosen action at each reachable hero node, keyed by the action path
  // from the evaluated state. Filled while solving, replayed for the per-card
  // breakdown so every card sees one coherent hero strategy.
  final Map<String, ActionType> _heroChoice = {};
  late int _heroCard;

  /// EV of [heroAction] taken now in [state], given hero holds [heroCard] and
  /// the villain's range is [belief] (rank values, weighted uniformly).
  ActionEv evaluate(
    HandState state,
    int heroCard,
    List<int> belief,
    ActionType heroAction,
  ) {
    _heroCard = heroCard;
    _heroChoice.clear();

    final post = state.clone();
    // The engine's showdown settlement reads each seat's card; the EV roll-out
    // ignores that result (profit is derived per-belief in _terminal), but the
    // cards must be non-null so settlement doesn't trip. Their values are
    // irrelevant to the outcome we read back.
    _ensureCards(post);
    engine.applyAction(post, GameAction(heroAction));

    final response = <int, BotMove>{};
    if (post.phase == HandPhase.betting && post.toAct == botSeat) {
      final node = _nodeFor(post, botSeat);
      for (final b in belief) {
        response[b] = profile.moveAt(node, b);
      }
    }

    final ev = _value(post, belief, '');
    final perCard = {for (final b in belief) b: _cardProfit(post, b)};
    final perCardDirect = {for (final b in belief) b: _passiveProfit(post, b)};
    return ActionEv(ev, perCard, perCardDirect, response);
  }

  // ---- Backward induction -------------------------------------------------

  double _value(HandState s, List<int> belief, String path) {
    if (s.phase != HandPhase.betting || s.toAct < 0) {
      return _terminal(s, belief);
    }
    if (s.toAct == botSeat) {
      final node = _nodeFor(s, botSeat);
      final groups = <BotMove, List<int>>{};
      for (final b in belief) {
        (groups[profile.moveAt(node, b)] ??= []).add(b);
      }
      var ev = 0.0;
      groups.forEach((move, cards) {
        final next = s.clone();
        engine.applyAction(next, _villainAction(next, botSeat, move));
        ev += cards.length / belief.length *
            _value(next, cards, '$path|${move.index}');
      });
      return ev;
    }
    // Hero node: pick the single action that maximises EV over the belief.
    var best = double.negativeInfinity;
    var bestAction = ActionType.fold;
    for (final type in engine.legalActions(s)) {
      final next = s.clone();
      engine.applyAction(next, GameAction(type));
      final v = _value(next, belief, '$path|H${type.index}');
      if (v > best) {
        best = v;
        bestAction = type;
      }
    }
    _heroChoice[path] = bestAction;
    return best;
  }

  /// Replays a single villain card through the solved strategy: villain follows
  /// its profile, hero follows the choices recorded in [_heroChoice].
  double _cardProfit(HandState post, int card) {
    final s = post.clone();
    var path = '';
    while (s.phase == HandPhase.betting && s.toAct >= 0) {
      if (s.toAct == botSeat) {
        final move = profile.moveAt(_nodeFor(s, botSeat), card);
        engine.applyAction(s, _villainAction(s, botSeat, move));
        path = '$path|${move.index}';
      } else {
        final type = _heroChoice[path] ?? ActionType.fold;
        engine.applyAction(s, GameAction(type));
        path = '$path|H${type.index}';
      }
    }
    return _terminal(s, [card]);
  }

  /// Like [_cardProfit] but with a passive hero who never folds or raises again
  /// — they just call/check down. This isolates the value that doesn't depend on
  /// any further betting decision (fold equity, or realising equity at showdown).
  double _passiveProfit(HandState post, int card) {
    final s = post.clone();
    while (s.phase == HandPhase.betting && s.toAct >= 0) {
      if (s.toAct == botSeat) {
        final move = profile.moveAt(_nodeFor(s, botSeat), card);
        engine.applyAction(s, _villainAction(s, botSeat, move));
      } else {
        final hero = s.seats[heroSeat];
        final type = s.currentBet - hero.committed > 0
            ? ActionType.call
            : ActionType.check;
        engine.applyAction(s, GameAction(type));
      }
    }
    return _terminal(s, [card]);
  }

  /// Hero's chips at a resolved node, as profit from the start of the hand.
  double _terminal(HandState s, List<int> belief) {
    final hero = s.seats[heroSeat];
    final villain = s.seats[botSeat];
    // A fold returns the folder's own chips; the winner's profit is exactly the
    // loser's committed chips (your own committed chips were never "won").
    if (hero.folded) return -hero.committed.toDouble();
    if (villain.folded) return villain.committed.toDouble();
    // Showdown: uncalled chips return, so the stake is the matched amount.
    final matched =
        hero.committed < villain.committed ? hero.committed : villain.committed;
    var sum = 0.0;
    for (final b in belief) {
      if (_heroCard > b) {
        sum += matched;
      } else if (_heroCard < b) {
        sum -= matched;
      }
    }
    return sum / belief.length;
  }

  // ---- Node identification + villain action mapping -----------------------

  void _ensureCards(HandState s) {
    for (final seat in s.seats) {
      seat.card ??= const PlayingCard(Rank.two, Suit.spades);
    }
  }

  BetNode _nodeFor(HandState s, int seatIndex) {
    final seat = s.seats[seatIndex];
    final toCall = s.currentBet - seat.committed;
    if (toCall > 0) {
      if (s.raiseCount <= 1) return BetNode.facingBet;
      if (s.raiseCount == 2) return BetNode.facingRaise;
      return BetNode.facingReraise;
    }
    final other = s.seats[seatIndex == botSeat ? heroSeat : botSeat];
    return other.lastAction?.type == ActionType.check
        ? BetNode.checkedTo
        : BetNode.open;
  }

  /// Turns an intended [BotMove] into a legal [GameAction] for [seatIndex],
  /// degrading gracefully when a raise isn't possible (already all-in for less).
  GameAction _villainAction(HandState s, int seatIndex, BotMove move) {
    final seat = s.seats[seatIndex];
    final toCall = s.currentBet - seat.committed;
    final canBet = seat.stack > toCall;
    switch (move) {
      case BotMove.pot:
        if (canBet) return const GameAction.bet(0);
        return toCall > 0 ? const GameAction.call(0) : const GameAction.check();
      case BotMove.call:
        return toCall > 0 ? const GameAction.call(0) : const GameAction.check();
      case BotMove.check:
        return const GameAction.check();
      case BotMove.fold:
        return toCall > 0 ? const GameAction.fold() : const GameAction.check();
    }
  }
}
