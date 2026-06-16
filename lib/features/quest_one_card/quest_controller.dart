import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../engine/game/action.dart';
import '../../engine/game/game_view.dart';
import '../../engine/game/hand_engine.dart';
import '../../engine/game/hand_state.dart';
import '../../engine/game/rule_config.dart';
import '../../engine/players/poker_player.dart';
import '../../engine/players/simple_ai_player.dart';
import '../../engine/players/human_player.dart';
import '../../engine/game/seat.dart';

/// Drives a single one-card-poker table for Quest 1: owns the engine, steps the
/// AI opponents with a human-feeling delay, and exposes everything the UI needs.
///
/// The UI listens via [ChangeNotifier]; it never touches the engine directly.
class QuestController extends ChangeNotifier {
  QuestController({
    RuleConfig? rules,
    int opponentCount = 2,
    int? seed,
  })  : rules = rules ?? const RuleConfig(),
        _rng = seed == null ? Random() : Random(seed) {
    _setupTable(opponentCount);
    startHand();
  }

  final RuleConfig rules;
  final Random _rng;

  late final HandEngine _engine;
  late final List<Seat> seats;
  late final Map<String, PokerPlayer> _bots; // playerId → AI policy

  int humanSeat = 0;
  int _button = -1;

  late HandState state;

  /// True while AI opponents are taking their turns (UI disables input).
  bool busy = false;

  /// Short status line shown to the player (whose turn / result).
  String statusMessage = '';

  /// How long an AI "thinks" before acting — pure feel.
  static const Duration _aiThinkTime = Duration(milliseconds: 750);

  void _setupTable(int opponentCount) {
    final human = HumanPlayer();
    // Five straightforward, predictable value bots for the first level.
    const names = ['Ava', 'Ben', 'Cora', 'Dan', 'Eve'];
    final personalities = <PokerPlayer>[
      for (var i = 0; i < names.length; i++)
        SimpleAiPlayer.straightforward('ai_$i', names[i], rng: _rng),
    ];
    final chosen = personalities.take(opponentCount.clamp(1, 5)).toList();

    seats = [
      Seat(
        index: 0,
        playerId: human.id,
        name: human.name,
        isHuman: true,
        stack: rules.startingStack,
      ),
      for (var i = 0; i < chosen.length; i++)
        Seat(
          index: i + 1,
          playerId: chosen[i].id,
          name: chosen[i].name,
          isHuman: false,
          stack: rules.startingStack,
        ),
    ];

    _bots = {for (final p in chosen) p.id: p};
    _engine = HandEngine(rules, _rng);
  }

  // ---- Public state for the UI -------------------------------------------

  bool get isHumanTurn =>
      !busy &&
      state.phase == HandPhase.betting &&
      state.toAct == humanSeat;

  /// Becomes true only after the brief pre-showdown pause, so the final
  /// call/bet animation can finish before cards flip and the pot is awarded.
  bool revealShowdown = false;

  bool get handOver => revealShowdown;

  /// Pause between the last action and the reveal (lets the final chips land).
  static const Duration _revealDelay = Duration(milliseconds: 850);

  /// View for the human seat, or null if it isn't a live betting decision.
  GameView? get humanView {
    if (state.phase != HandPhase.betting) return null;
    if (seats[humanSeat].folded) return null;
    return _engine.buildView(state, humanSeat);
  }

  bool get humanBusted => seats[humanSeat].stack <= 0;

  /// Fewer than two funded players remain — the table can't continue.
  bool get tableCleared => seats.where((s) => s.stack > 0).length < 2;

  // ---- Hand lifecycle -----------------------------------------------------

  void startHand() {
    revealShowdown = false;
    _button = (_button + 1) % seats.length;
    state = _engine.start(seats, _button);
    if (state.phase == HandPhase.complete) {
      // Degenerate (e.g. table cleared) — nothing to animate, reveal at once.
      revealShowdown = true;
      _updateStatus();
      notifyListeners();
      return;
    }
    _updateStatus();
    notifyListeners();
    _runAiTurns();
  }

  void resetSession() {
    for (final s in seats) {
      s.stack = rules.startingStack;
    }
    _button = -1;
    startHand();
  }

  // ---- Human actions ------------------------------------------------------

  void fold() => _humanAct(const GameAction.fold());
  void check() => _humanAct(const GameAction.check());

  void call() {
    final view = humanView;
    if (view == null) return;
    _humanAct(GameAction.call(view.toCall));
  }

  void bet() => _humanAct(const GameAction.bet(0)); // amount derived by engine (pot-sized)

  void _humanAct(GameAction action) {
    if (!isHumanTurn) return;
    _engine.applyAction(state, action);
    _updateStatus();
    notifyListeners();
    _runAiTurns();
  }

  // ---- AI loop ------------------------------------------------------------

  Future<void> _runAiTurns() async {
    while (state.phase == HandPhase.betting &&
        state.toAct >= 0 &&
        !seats[state.toAct].isHuman) {
      busy = true;
      _updateStatus();
      notifyListeners();

      await Future<void>.delayed(_aiThinkTime);

      // State may have completed during the delay (defensive).
      if (state.phase != HandPhase.betting || state.toAct < 0) break;
      final seat = seats[state.toAct];
      if (seat.isHuman) break;

      final bot = _bots[seat.playerId]!;
      final view = _engine.buildView(state, seat.index);
      try {
        _engine.applyAction(state, bot.decide(view));
      } catch (_) {
        // Safety net: a bad/illegal bot move must never hang the table.
        // Fall back to a legal action (check if free, otherwise fold).
        _engine.applyAction(
          state,
          view.canCheck ? const GameAction.check() : const GameAction.fold(),
        );
      }
      notifyListeners();
    }

    busy = false;

    // Hand finished: hold a beat so the final chips land, then reveal.
    if (state.phase == HandPhase.complete && !revealShowdown) {
      _updateStatus();
      notifyListeners();
      await Future<void>.delayed(_revealDelay);
      revealShowdown = true;
    }

    _updateStatus();
    notifyListeners();
  }

  void _updateStatus() {
    if (state.phase == HandPhase.complete) {
      if (!revealShowdown) {
        statusMessage = state.liveSeats.length >= 2 ? 'Showdown…' : '';
        return;
      }
      final winners =
          state.winners.map((i) => seats[i].name).toList(growable: false);
      final you = state.winners.contains(humanSeat);
      if (you && winners.length == 1) {
        statusMessage = 'You win ${state.pot} chips!';
      } else if (you) {
        statusMessage = 'Split pot — you take a share.';
      } else {
        statusMessage = '${winners.join(', ')} won ${state.pot}.';
      }
      return;
    }
    if (state.toAct == humanSeat && !busy) {
      statusMessage = 'Your move.';
    } else if (state.toAct >= 0) {
      statusMessage = '${seats[state.toAct].name} is thinking…';
    } else {
      statusMessage = '';
    }
  }
}
