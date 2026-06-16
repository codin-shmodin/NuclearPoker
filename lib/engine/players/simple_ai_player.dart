import 'dart:math';

import '../game/action.dart';
import '../game/game_view.dart';
import 'poker_player.dart';

/// A simple, beatable heuristic bot — NOT GTO. It decides purely from its card
/// strength plus a few personality knobs, with a little randomness so it isn't
/// predictable. Presets below give distinct, recognisable opponents.
///
/// Card strength is normalised 0..1 (deuce..ace). Personality knobs:
///  - [tightness]    how strong a card it needs before it likes its hand.
///  - [aggression]   how often a liked hand bets rather than checks.
///  - [bluffFreq]    chance to bet/call a weak hand anyway.
///  - [callStation]  extra willingness to call bets with marginal hands.
class SimpleAiPlayer implements PokerPlayer {
  SimpleAiPlayer({
    required this.id,
    required this.name,
    required this.tightness,
    required this.aggression,
    required this.bluffFreq,
    required this.callStation,
    Random? rng,
  }) : _rng = rng ?? Random();

  @override
  final String id;
  @override
  final String name;

  final double tightness; // 0..1
  final double aggression; // 0..1
  final double bluffFreq; // 0..1
  final double callStation; // 0..1
  final Random _rng;

  @override
  GameAction decide(GameView view) {
    // 2 → 0.0, A → 1.0
    final strength = (view.myCard.rank.value - 2) / 12.0;
    final roll = _rng.nextDouble();
    final premium = strength >= 0.85; // roughly A / K
    final facing = view.toCall > 0;

    if (facing) {
      // Re-raise with monsters while raising is still allowed.
      if (view.canBet && premium && roll < 0.85) {
        return GameAction.bet(view.raiseTarget);
      }
      // Sometimes raise a merely-strong hand.
      if (view.canBet && strength >= tightness + 0.25 && roll < aggression * 0.5) {
        return GameAction.bet(view.raiseTarget);
      }
      // Call: the more raises have gone in, the stronger we need to be.
      final pressure = 0.06 * view.raiseCount;
      final callThreshold = tightness - 0.15 * callStation + pressure;
      if (strength >= callThreshold || roll < bluffFreq * 0.4) {
        return GameAction.call(view.toCall);
      }
      return const GameAction.fold();
    }

    // First in / checked to us: open good hands — premiums almost always raise
    // (so they never just limp), and occasionally bluff.
    if (view.canBet) {
      if (premium && roll < 0.92) return GameAction.bet(view.raiseTarget);
      if (strength >= tightness && roll < aggression) {
        return GameAction.bet(view.raiseTarget);
      }
      if (roll < bluffFreq) return GameAction.bet(view.raiseTarget);
    }
    return const GameAction.check();
  }

  // ---- Personality presets ------------------------------------------------

  /// Straightforward, honest value player: bets/raises good cards, calls
  /// reasonable ones, folds junk, almost never bluffs. Predictable on purpose.
  factory SimpleAiPlayer.straightforward(String id, String name, {Random? rng}) =>
      SimpleAiPlayer(
        id: id,
        name: name,
        tightness: 0.5,
        aggression: 0.7,
        bluffFreq: 0.04,
        callStation: 0.3,
        rng: rng,
      );

  /// Plays few hands, rarely bluffs — folds a lot.
  factory SimpleAiPlayer.nit(String id, String name, {Random? rng}) =>
      SimpleAiPlayer(
        id: id,
        name: name,
        tightness: 0.72,
        aggression: 0.55,
        bluffFreq: 0.04,
        callStation: 0.1,
        rng: rng,
      );

  /// Tight-aggressive: solid, bets its good hands hard.
  factory SimpleAiPlayer.tag(String id, String name, {Random? rng}) =>
      SimpleAiPlayer(
        id: id,
        name: name,
        tightness: 0.55,
        aggression: 0.8,
        bluffFreq: 0.12,
        callStation: 0.2,
        rng: rng,
      );

  /// Loose-aggressive: plays many hands, bluffs often.
  factory SimpleAiPlayer.lag(String id, String name, {Random? rng}) =>
      SimpleAiPlayer(
        id: id,
        name: name,
        tightness: 0.4,
        aggression: 0.85,
        bluffFreq: 0.28,
        callStation: 0.3,
        rng: rng,
      );

  /// Maniac: bets and bluffs relentlessly.
  factory SimpleAiPlayer.maniac(String id, String name, {Random? rng}) =>
      SimpleAiPlayer(
        id: id,
        name: name,
        tightness: 0.3,
        aggression: 0.95,
        bluffFreq: 0.45,
        callStation: 0.5,
        rng: rng,
      );

  /// Calling station: rarely folds, rarely bets.
  factory SimpleAiPlayer.callingStation(String id, String name, {Random? rng}) =>
      SimpleAiPlayer(
        id: id,
        name: name,
        tightness: 0.5,
        aggression: 0.3,
        bluffFreq: 0.08,
        callStation: 0.9,
        rng: rng,
      );
}
