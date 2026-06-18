import 'seat.dart';

enum HandPhase { betting, showdown, complete }

/// The full, authoritative state of a single hand. Mutated in place by
/// [HandEngine] (kept simple for the PoC).
class HandState {
  HandState({
    required this.seats,
    required this.button,
    required this.toAct,
    required this.pot,
    required this.currentBet,
    required this.phase,
  });

  final List<Seat> seats;
  int button;
  int toAct; // seat index whose turn it is, or -1 if none
  int pot;
  int currentBet;

  /// Number of aggressive actions (bets/raises) so far this round; capped by
  /// [RuleConfig.maxRaises].
  int raiseCount = 0;

  HandPhase phase;

  /// Seat indices of the small and big blinds for this hand (−1 if no blinds).
  int smallBlindSeat = -1;
  int bigBlindSeat = -1;

  /// Seat indices that won the most recent showdown/fold-out (for UI).
  final List<int> winners = [];

  /// Human-readable hand history (for UI / debugging).
  final List<String> log = [];

  List<Seat> get liveSeats =>
      seats.where((s) => !s.folded).toList(growable: false);

  /// A deep copy of the whole hand (seats included), so the EV evaluator can
  /// apply hypothetical actions on a throwaway state. The log is intentionally
  /// dropped — EV roll-outs don't need narration.
  HandState clone() {
    final copy = HandState(
      seats: [for (final s in seats) s.clone()],
      button: button,
      toAct: toAct,
      pot: pot,
      currentBet: currentBet,
      phase: phase,
    )
      ..raiseCount = raiseCount
      ..smallBlindSeat = smallBlindSeat
      ..bigBlindSeat = bigBlindSeat;
    copy.winners.addAll(winners);
    return copy;
  }
}
