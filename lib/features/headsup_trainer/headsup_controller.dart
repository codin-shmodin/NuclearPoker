import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../engine/cards/rank.dart';
import '../../engine/game/action.dart';
import '../../engine/game/game_view.dart';
import '../../engine/game/hand_engine.dart';
import '../../engine/game/hand_state.dart';
import '../../engine/game/rule_config.dart';
import '../../engine/game/seat.dart';
import '../../engine/players/range_bot.dart';

/// How a rank is coloured on the range bar.
enum RangeBucket { check, fold, call, pot, shown }

/// A row on the EV hint bar: the exact chip EV of potting vs this holding.
class EvCell {
  const EvCell(this.rank, this.active, this.chips, this.color, this.label);

  final Rank rank;
  final bool active; // bot could hold this AND we have a live pot decision
  final int chips; // exact EV of potting (vs checking down), in chips
  final double color; // -1 (lose a lot) .. +1 (win a lot) for the gradient
  final String label;
}

/// One rank row on the range bar.
class RankCell {
  const RankCell(this.rank, this.inRange, this.bucket, this.isBotCard);

  final Rank rank;
  final bool inRange; // still possible for the bot
  final RangeBucket bucket; // colour for the current decision
  final bool isBotCard; // revealed at showdown
}

/// Drives the heads-up trainer: the human (big blind) defends against a fully
/// transparent [RangeBot] (button). The bot narrates its range and the bar shows
/// exactly what it will do, so the player learns to respond.
class HeadsUpController extends ChangeNotifier {
  HeadsUpController({int? seed}) : _rng = seed == null ? Random() : Random(seed) {
    seats = [
      Seat(index: 0, playerId: 'human', name: 'You', isHuman: true, stack: rules.startingStack),
      Seat(index: 1, playerId: _bot.id, name: _bot.name, isHuman: false, stack: rules.startingStack),
    ];
    _engine = HandEngine(rules, _rng);
    startHand();
  }

  static const RuleConfig rules = RuleConfig(
    startingStack: 50,
    smallBlind: 1,
    bigBlind: 1,
    maxPlayers: 2,
  );

  static const int humanSeat = 0;
  static const int botSeat = 1;
  static const Duration _botThink = Duration(milliseconds: 850);
  static const Duration _revealDelay = Duration(milliseconds: 850);

  final Random _rng;
  final RangeBot _bot = RangeBot();
  late final HandEngine _engine;
  late final List<Seat> seats;
  late HandState state;

  bool busy = false;
  bool revealShowdown = false;
  bool hintOn = false;

  // The dealer/button alternates each hand (starts on the bot).
  int _button = humanSeat;

  int get buttonSeat => state.button;

  void toggleHint(bool v) {
    hintOn = v;
    notifyListeners();
  }

  // ---- Range / narration state (for the UI) ------------------------------
  final Set<int> _botRange = {}; // rank values the bot could still hold
  List<RankCell> rangeCells = [];
  List<EvCell> evCells = [];
  String rangeTitle = '';
  String botSpeech = '';
  String statusMessage = '';

  // ---- Getters for the UI -------------------------------------------------
  bool get handOver => revealShowdown;
  bool get isHumanTurn =>
      !busy && state.phase == HandPhase.betting && state.toAct == humanSeat;

  GameView? get humanView {
    if (state.phase != HandPhase.betting) return null;
    if (seats[humanSeat].folded) return null;
    return _engine.buildView(state, humanSeat);
  }

  bool get humanBusted => seats[humanSeat].stack <= 0;
  bool get botBusted => seats[botSeat].stack <= 0;
  bool get sessionOver => humanBusted || botBusted;

  // ---- Hand lifecycle -----------------------------------------------------
  void startHand() {
    revealShowdown = false;
    _button = (_button + 1) % 2; // switch positions each hand
    _botRange
      ..clear()
      ..addAll(Rank.values.map((r) => r.value));
    state = _engine.start(seats, _button);
    _rebuildRange();
    notifyListeners();
    _run();
  }

  void resetSession() {
    for (final s in seats) {
      s.stack = rules.startingStack;
    }
    startHand();
  }

  // ---- Human actions ------------------------------------------------------
  void fold() => _humanAct(const GameAction.fold());
  void check() => _humanAct(const GameAction.check());
  void call() {
    final v = humanView;
    if (v == null) return;
    _humanAct(GameAction.call(v.toCall));
  }

  void pot() => _humanAct(const GameAction.bet(0));

  void _humanAct(GameAction action) {
    if (!isHumanTurn) return;
    _engine.applyAction(state, action);
    _rebuildRange();
    notifyListeners();
    _run();
  }

  // ---- Bot loop -----------------------------------------------------------
  Future<void> _run() async {
    while (state.phase == HandPhase.betting && state.toAct == botSeat) {
      busy = true;
      _rebuildRange(); // shows the bot's strategy for the node it's about to play
      notifyListeners();
      await Future<void>.delayed(_botThink);
      if (state.phase != HandPhase.betting || state.toAct != botSeat) break;

      final view = _engine.buildView(state, botSeat);
      final facing = view.toCall > 0;
      final move = _botMove(view.myCard.rank.value, facing: facing);
      _narrowByMove(facing, move); // the action reveals info about its range
      _engine.applyAction(state, _moveAction(move, view));
      _rebuildRange();
      notifyListeners();
    }

    busy = false;
    if (state.phase == HandPhase.complete && !revealShowdown) {
      _rebuildRange();
      notifyListeners();
      await Future<void>.delayed(_revealDelay);
      revealShowdown = true;
    }
    _rebuildRange();
    notifyListeners();
  }

  /// The bot's move for [rankValue], range-aware. First in: pot a nine+, else
  /// check. Facing a raise: the usual fold/call/pot by absolute strength, BUT it
  /// always defends (at least calls) the top of its *current* range so it can't
  /// be exploited for a 100% fold (e.g. after it checks a weak range).
  BotMove _botMove(int rankValue, {required bool facing}) {
    if (!facing) {
      return rankValue >= RangeBot.openPotFrom ? BotMove.pot : BotMove.check;
    }
    BotMove move;
    if (rankValue >= RangeBot.facingPotFrom) {
      move = BotMove.pot;
    } else if (rankValue >= RangeBot.facingCallFrom) {
      move = BotMove.call;
    } else {
      move = BotMove.fold;
    }
    // Floor: never fold 100% — always defend (call) the single top of the
    // current range, even if it's below the normal calling threshold.
    if (move == BotMove.fold && _botRange.isNotEmpty) {
      if (rankValue == _botRange.reduce(max)) move = BotMove.call;
    }
    return move;
  }

  GameAction _moveAction(BotMove move, GameView view) {
    switch (move) {
      case BotMove.pot:
        if (view.canBet) return const GameAction.bet(0);
        return view.toCall > 0 ? GameAction.call(view.toCall) : const GameAction.check();
      case BotMove.call:
        return view.toCall > 0 ? GameAction.call(view.toCall) : const GameAction.check();
      case BotMove.check:
        return const GameAction.check();
      case BotMove.fold:
        return view.toCall > 0 ? const GameAction.fold() : const GameAction.check();
    }
  }

  /// Keep only the ranks for which the bot would make [move] at this node.
  /// Classify first (against the current range) so narrowing is consistent.
  void _narrowByMove(bool facing, BotMove move) {
    final classified = {
      for (final v in _botRange) v: _botMove(v, facing: facing),
    };
    _botRange.removeWhere((v) => classified[v] != move);
  }

  // ---- Range view + narration --------------------------------------------
  void _rebuildRange() {
    evCells = _buildEvCells();

    if (state.phase == HandPhase.complete) {
      _statusComplete();
      // Hand over: show the bot's FINAL range neutrally (no action recolouring)
      // and highlight its actual card. Re-colouring here caused a stale-floor bug.
      rangeTitle = "Villain's range";
      botSpeech = revealShowdown ? _resultSpeech() : '';
      rangeCells = _cells(
        neutral: true,
        highlight: revealShowdown ? seats[botSeat].card?.rank.value : null,
      );
      return;
    }

    if (state.toAct == botSeat) {
      final view = _engine.buildView(state, botSeat);
      final facing = view.toCall > 0;
      final botIsButton = state.button == botSeat;
      rangeTitle = facing ? 'Facing your raise I would:' : 'My range';
      if (facing) {
        botSpeech = 'You raised — let me see…';
      } else if (botIsButton) {
        botSpeech = "I'm on the button. I pot a nine or better, otherwise I check.";
      } else {
        botSpeech = "You checked to me — I pot a nine or better, else check back.";
      }
      rangeCells = _cells(facing: facing);
      statusMessage = '${_bot.name} is thinking…';
      return;
    }

    // Human to act: show what the bot will do if we pot.
    rangeTitle = 'If you POT, ${_bot.name} will:';
    botSpeech = _facingSpeech();
    rangeCells = _cells(facing: true);
    statusMessage = 'Your move.';
  }

  List<RankCell> _cells({bool facing = false, bool neutral = false, int? highlight}) {
    final ranks = Rank.values.reversed.toList(); // A (top) → 2 (bottom)
    return [
      for (final r in ranks)
        RankCell(
          r,
          _botRange.contains(r.value),
          neutral ? RangeBucket.shown : _bucketFor(r.value, facing),
          highlight != null && r.value == highlight,
        ),
    ];
  }

  RangeBucket _bucketFor(int v, bool facing) {
    switch (_botMove(v, facing: facing)) {
      case BotMove.pot:
        return RangeBucket.pot;
      case BotMove.call:
        return RangeBucket.call;
      case BotMove.fold:
        return RangeBucket.fold;
      case BotMove.check:
        return RangeBucket.check;
    }
  }

  // ---- EV hint ------------------------------------------------------------
  List<EvCell> _buildEvCells() {
    final h = seats[humanSeat].card?.rank.value;
    final view = humanView;
    final active = h != null && view != null && view.canBet && isHumanTurn;
    final ranks = Rank.values.reversed.toList();
    if (!active) {
      return [for (final r in ranks) EvCell(r, false, 0, 0, '')];
    }
    return [for (final r in ranks) _evFor(r, h)];
  }

  /// Exact EV (in chips) of potting vs the bot holding [r], compared to checking
  /// it down — given our card [h].
  EvCell _evFor(Rank r, int h) {
    final b = r.value;
    if (!_botRange.contains(b)) return EvCell(r, false, 0, 0, '');

    final chips = _potNet(h, b) - _checkdownNet(h, b);
    final color = (chips / (state.pot > 0 ? state.pot : 1)).clamp(-1.0, 1.0);

    final resp = _botMove(b, facing: true);
    final String label;
    if (resp == BotMove.fold) {
      // He folds. Folding a worse hand = no value; folding a hand that ties or
      // beats us = fold equity (we win instead of splitting/losing).
      label = h > b ? 'NO VAL' : 'FOLD EQ';
    } else if (h == b) {
      label = 'SPLIT';
    } else {
      label = h > b ? 'VALUE' : 'BEAT';
    }
    return EvCell(r, true, chips, color, label);
  }

  /// Net chips (from start of hand) if we POT and the line resolves: bot folds →
  /// we take the pot; bot calls → showdown; bot shoves → we take our better of
  /// fold/call. Uses the real pot-sized math.
  int _potNet(int h, int b) {
    final me = seats[humanSeat];
    final bot = seats[botSeat];
    final p = state.pot;
    final cb = state.currentBet;
    final myCall = cb - me.committed > 0 ? cb - me.committed : 0;
    final ourTarget = _min(cb + p + myCall, me.committed + me.stack);
    final ourAdd = ourTarget - me.committed;

    final resp = _botMove(b, facing: true);
    if (resp == BotMove.fold) {
      return p - me.committed; // win the existing pot; our raise comes back
    }
    if (resp == BotMove.call) {
      final botCall = _min(ourTarget - bot.committed, bot.stack);
      return _showdownNet(h, b, me.committed + ourAdd, bot.committed + botCall);
    }
    // Bot shoves (pot-raise). We pick the better of folding or calling.
    final pot1 = p + ourAdd;
    final botCall = ourTarget - bot.committed > 0 ? ourTarget - bot.committed : 0;
    final botTarget = _min(ourTarget + pot1 + botCall, bot.committed + bot.stack);
    final foldNet = -(me.committed + ourAdd);
    final ourFinal = _min(botTarget, me.committed + me.stack);
    final callNet = _showdownNet(h, b, ourFinal, botTarget);
    return foldNet > callNet ? foldNet : callNet;
  }

  /// Net chips if instead we just check/call down to showdown right now.
  int _checkdownNet(int h, int b) =>
      _showdownNet(h, b, state.currentBet, seats[botSeat].committed);

  /// Net chips at showdown given each side's total invested (uncalled returns).
  int _showdownNet(int h, int b, int myInv, int botInv) {
    final matched = myInv < botInv ? myInv : botInv;
    if (h > b) return matched;
    if (h < b) return -matched;
    return 0;
  }

  int _min(int a, int b) => a < b ? a : b;

  // ---- Speech helpers -----------------------------------------------------
  String _facingSpeech() {
    final inRange = (_botRange.toList()..sort());
    if (inRange.isEmpty) return '…';
    final folds = <int>[], calls = <int>[], pots = <int>[];
    for (final v in inRange) {
      switch (_botMove(v, facing: true)) {
        case BotMove.pot:
          pots.add(v);
        case BotMove.call:
          calls.add(v);
        case BotMove.fold:
          folds.add(v);
        case BotMove.check:
          break;
      }
    }
    final parts = <String>[];
    if (pots.isNotEmpty) parts.add('shove ${_group(pots)}');
    if (calls.isNotEmpty) parts.add('call ${_group(calls)}');
    if (folds.isNotEmpty) parts.add('fold ${_group(folds)}');
    if (parts.isEmpty) return '…';
    return 'If you pot, I ${_join(parts)}.';
  }

  String _resultSpeech() {
    final you = state.winners.contains(humanSeat);
    final botCard = seats[botSeat].card;
    final mine = botCard == null ? 'my hand' : 'my ${_bare(botCard.rank.value)}';
    if (state.winners.length > 1) return 'Split pot — we tie.';
    return you ? 'You got me — I had $mine.' : 'I win it with $mine.';
  }

  void _statusComplete() {
    final you = state.winners.contains(humanSeat);
    if (state.winners.length > 1) {
      statusMessage = 'Split pot.';
    } else if (you) {
      statusMessage = 'You win ${state.pot} chips!';
    } else {
      statusMessage = '${seats[botSeat].name} wins ${state.pot}.';
    }
  }

  // contiguous group → "a nine" / "ten through king" / "the ace"
  String _group(List<int> values) {
    if (values.length == 1) {
      final v = values.first;
      return v == 14 ? 'the ace' : '${_article(v)} ${_bare(v)}';
    }
    return '${_bare(values.first)} through ${_bare(values.last)}';
  }

  String _join(List<String> parts) {
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  String _article(int v) => v == 8 || v == 14 ? 'an' : 'a';

  String _bare(int v) {
    switch (v) {
      case 11:
        return 'jack';
      case 12:
        return 'queen';
      case 13:
        return 'king';
      case 14:
        return 'ace';
      case 10:
        return 'ten';
      case 9:
        return 'nine';
      case 8:
        return 'eight';
      case 7:
        return 'seven';
      case 6:
        return 'six';
      case 5:
        return 'five';
      case 4:
        return 'four';
      case 3:
        return 'three';
      default:
        return 'two';
    }
  }
}
