import 'dart:math';

import 'card.dart';
import 'rank.dart';
import 'suit.dart';

/// A standard 52-card deck. Shuffling uses an injected [Random] so hands are
/// reproducible in tests (seed the Random).
class Deck {
  Deck(this._rng) {
    reset();
  }

  final Random _rng;
  final List<PlayingCard> _cards = [];

  void reset() {
    _cards
      ..clear()
      ..addAll([
        for (final suit in Suit.values)
          for (final rank in Rank.values) PlayingCard(rank, suit),
      ]);
    _cards.shuffle(_rng);
  }

  PlayingCard draw() => _cards.removeLast();

  int get remaining => _cards.length;
}
