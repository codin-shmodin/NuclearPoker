import '../game/action.dart';
import '../game/game_view.dart';
import 'poker_player.dart';

/// Marker for the human seat. The UI drives the human's actions, so [decide] is
/// never called by the engine loop — but implementing the same interface keeps
/// humans and bots interchangeable.
class HumanPlayer implements PokerPlayer {
  HumanPlayer({this.id = 'human', this.name = 'You'});

  @override
  final String id;
  @override
  final String name;

  @override
  GameAction decide(GameView view) =>
      throw UnsupportedError('Human actions come from the UI, not decide().');
}
