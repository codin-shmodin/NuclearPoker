import 'rank.dart';
import 'suit.dart';

/// A single playing card. Named `PlayingCard` to avoid clashing with Flutter's
/// `Card` widget.
class PlayingCard {
  const PlayingCard(this.rank, this.suit);

  final Rank rank;
  final Suit suit;

  @override
  String toString() => '${rank.label}${suit.symbol}';

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);
}
