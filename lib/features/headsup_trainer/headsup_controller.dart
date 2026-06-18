import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../engine/cards/rank.dart';
import '../../engine/ev/immediate_ev.dart';
import '../../engine/game/action.dart';
import '../../engine/game/game_view.dart';
import '../../engine/game/hand_engine.dart';
import '../../engine/game/hand_state.dart';
import '../../engine/game/rule_config.dart';
import '../../engine/game/seat.dart';
import '../../engine/players/bot_profile.dart';
import '../../engine/players/range_bot.dart' show BotMove;

/// How a rank is coloured on the range bar. `check/fold/call/pot` are the bot's
/// *action* with that card; `win/lose/tie` are the showdown matchup vs your card
/// (used when the action you're hovering just ends in a showdown); `shown` is
/// the neutral grey "cards he can have".
enum RangeBucket { check, fold, call, pot, shown, win, lose, tie }

/// A row on the EV hint bar: the immediate (option-A) chip result of one action
/// vs the bot holding a particular card — net chips from the start of the hand,
/// for the lines that resolve the moment the bot answers.
class EvCell {
  const EvCell(this.rank, this.active, this.unknown, this.ev, this.color,
      this.label);

  final Rank rank;
  final bool active; // bot could hold this AND we have a live decision
  final bool unknown; // the ball comes back to us → shown as "?"
  final int ev; // net chips from the start of the hand (signed)
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

/// Drives the heads-up trainer: the human defends against a fully transparent
/// [BotProfile]. Play, the narration, the range bar and the EV hint all read
/// the *same* profile, so what the bar predicts is exactly what the bot does.
class HeadsUpController extends ChangeNotifier {
  HeadsUpController({BotProfile? profile, int? seed})
      : profile = profile ?? BotProfile.pro,
        _rng = seed == null ? Random() : Random(seed) {
    seats = [
      Seat(index: 0, playerId: 'human', name: 'You', isHuman: true, stack: rules.startingStack),
      Seat(index: 1, playerId: this.profile.id, name: this.profile.name, isHuman: false, stack: rules.startingStack),
    ];
    _engine = HandEngine(rules, _rng);
    _ev = ImmediateEvCalculator(_engine, this.profile,
        heroSeat: humanSeat, botSeat: botSeat);
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

  final BotProfile profile;
  final Random _rng;
  late final HandEngine _engine;
  late final ImmediateEvCalculator _ev;
  late final List<Seat> seats;
  late HandState state;

  bool busy = false;
  bool revealShowdown = false;
  bool hintOn = false;

  /// The action the player is hovering, if any — drives which action's EV the
  /// hint bar shows.
  ActionType? hoveredAction;

  // The dealer/button alternates each hand (starts on the bot).
  int _button = humanSeat;

  int get buttonSeat => state.button;

  void toggleHint(bool v) {
    hintOn = v;
    notifyListeners();
  }

  void setHoveredAction(ActionType? action) {
    if (hoveredAction == action) return;
    hoveredAction = action;
    _rebuildRange(); // the range bar lights up for the hovered action
    notifyListeners();
  }

  // ---- Range / narration state (for the UI) ------------------------------
  final Set<int> _botRange = {}; // rank values the bot could still hold
  List<RankCell> rangeCells = [];
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
    hoveredAction = null;
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
    hoveredAction = null;
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
      final node = _botNode();
      final move = profile.moveAt(node, view.myCard.rank.value);
      _narrowByMove(node, move); // the action reveals info about its range
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

  /// The betting node the bot is currently at (or would face).
  BetNode _botNode() => _nodeForSeat(botSeat);

  /// The node the bot would be at if the human bets/raises (pots) right now.
  BetNode _botNodeIfHumanPots() => _facingNode(state.raiseCount + 1);

  BetNode _nodeForSeat(int seatIndex) {
    final seat = state.seats[seatIndex];
    final toCall = state.currentBet - seat.committed;
    if (toCall > 0) return _facingNode(state.raiseCount);
    final other = state.seats[seatIndex == botSeat ? humanSeat : botSeat];
    return other.lastAction?.type == ActionType.check
        ? BetNode.checkedTo
        : BetNode.open;
  }

  BetNode _facingNode(int raiseCount) {
    if (raiseCount <= 1) return BetNode.facingBet;
    if (raiseCount == 2) return BetNode.facingRaise;
    return BetNode.facingReraise;
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

  /// Keep only the ranks for which the bot would make [move] at [node].
  void _narrowByMove(BetNode node, BotMove move) {
    _botRange.removeWhere((v) => profile.moveAt(node, v) != move);
  }

  // ---- Range view + narration --------------------------------------------
  void _rebuildRange() {
    if (state.phase == HandPhase.complete) {
      _statusComplete();
      rangeTitle = "Villain's range";
      botSpeech = revealShowdown ? _resultSpeech() : '';
      rangeCells = _cells(
        neutral: true,
        highlight: revealShowdown ? seats[botSeat].card?.rank.value : null,
      );
      return;
    }

    if (state.toAct == botSeat) {
      final node = _botNode();
      final facing = node != BetNode.open && node != BetNode.checkedTo;
      rangeTitle = facing ? 'Facing your raise I would:' : 'My range';
      botSpeech = facing ? _botFacingSpeech(node) : _botOpenSpeech(node);
      rangeCells = _cells(node: node);
      statusMessage = '${profile.name} is thinking…';
      return;
    }

    // Human to act: the range bar reflects the action you're hovering.
    statusMessage = 'Your move.';
    final action = hoveredAction;

    // Nothing hovered, or folding → just show the cards he can have, in grey.
    if (action == null || action == ActionType.fold) {
      rangeTitle = "${profile.name}'s range";
      botSpeech = 'Hover an option to see how I react.';
      rangeCells = _cells(neutral: true);
      return;
    }

    // Betting → colour by his response to the bet/raise.
    if (action == ActionType.bet) {
      final node = _botNodeIfHumanPots();
      rangeTitle = 'If you POT, ${profile.name} will:';
      botSpeech = _facingSpeech(node);
      rangeCells = _cells(node: node);
      return;
    }

    // Checking when the bot still gets to act → colour by his check/bet choice.
    if (action == ActionType.check && !seats[botSeat].hasActed) {
      rangeTitle = 'If you check, ${profile.name} will:';
      botSpeech = _botOpenSpeech(BetNode.checkedTo);
      rangeCells = _cells(node: BetNode.checkedTo);
      return;
    }

    // Call, or a check that ends the hand → it's a showdown, so colour his
    // range by how you fare against each card.
    rangeTitle = action == ActionType.call ? 'If you CALL:' : 'At showdown:';
    botSpeech = _matchupSpeech();
    rangeCells = _cellsMatchup();
  }

  /// Colour each in-range card by the showdown result against our card.
  List<RankCell> _cellsMatchup() {
    final h = seats[humanSeat].card?.rank.value ?? 0;
    return [
      for (final r in Rank.values.reversed)
        RankCell(
          r,
          _botRange.contains(r.value),
          h > r.value
              ? RangeBucket.win
              : (h < r.value ? RangeBucket.lose : RangeBucket.tie),
          false,
        ),
    ];
  }

  String _matchupSpeech() {
    final h = seats[humanSeat].card?.rank.value;
    if (h == null) return '';
    final inRange = _botRange.toList()..sort();
    final beat = <int>[], lose = <int>[], tie = <int>[];
    for (final v in inRange) {
      if (h > v) {
        beat.add(v);
      } else if (h < v) {
        lose.add(v);
      } else {
        tie.add(v);
      }
    }
    final parts = <String>[];
    if (beat.isNotEmpty) parts.add('beat ${_group(beat)}');
    if (lose.isNotEmpty) parts.add('lose to ${_group(lose)}');
    if (tie.isNotEmpty) parts.add('tie ${_group(tie)}');
    return parts.isEmpty ? '…' : 'You ${_join(parts)}.';
  }

  List<RankCell> _cells({BetNode? node, bool neutral = false, int? highlight}) {
    final ranks = Rank.values.reversed.toList(); // A (top) → 2 (bottom)
    return [
      for (final r in ranks)
        RankCell(
          r,
          _botRange.contains(r.value),
          neutral ? RangeBucket.shown : _bucketFor(r.value, node!),
          highlight != null && r.value == highlight,
        ),
    ];
  }

  RangeBucket _bucketFor(int v, BetNode node) {
    switch (profile.moveAt(node, v)) {
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

  /// The immediate-EV cells for [action] — one row per rank the bot might hold,
  /// each the option-A net result (end-of-hand chips minus our starting stack)
  /// of the lines that resolve when the bot answers. A rank is `unknown` ("?")
  /// when this action hands the decision back to us. Inactive when it isn't a
  /// live decision or the action is illegal here.
  List<EvCell> evCellsForAction(ActionType action) {
    final ranks = Rank.values.reversed.toList();
    final h = seats[humanSeat].card?.rank.value;
    final view = humanView;
    if (h == null || view == null || !isHumanTurn || !_isLegal(action, view)) {
      return [for (final r in ranks) EvCell(r, false, false, 0, 0, '')];
    }
    final belief = _botRange.toList();
    final results = _ev.evaluate(state, h, belief, action);

    // Scale the colour gradient by the biggest swing on the bar, so the brightest
    // red/green always mark this action's worst/best card.
    var maxAbs = 1;
    for (final r in results.values) {
      if (r != null && r.ev.abs() > maxAbs) maxAbs = r.ev.abs();
    }

    return [
      for (final r in ranks)
        if (!_botRange.contains(r.value))
          EvCell(r, false, false, 0, 0, '')
        else
          _toCell(r, results[r.value], maxAbs),
    ];
  }

  EvCell _toCell(Rank r, ImmediateEv? result, int maxAbs) {
    if (result == null) return EvCell(r, true, true, 0, 0, '?');
    final color = (result.ev / maxAbs).clamp(-1.0, 1.0);
    return EvCell(r, true, false, result.ev, color, result.label);
  }

  bool _isLegal(ActionType action, GameView view) {
    switch (action) {
      case ActionType.fold:
        return view.toCall > 0;
      case ActionType.check:
        return view.canCheck;
      case ActionType.call:
        return view.canCall;
      case ActionType.bet:
        return view.canBet;
    }
  }

  // ---- Speech helpers -----------------------------------------------------
  String _botOpenSpeech(BetNode node) {
    final betFrom = profile.nodes[node]?.betFrom ?? 99;
    final where = node == BetNode.checkedTo ? 'You checked — ' : "I'm first — ";
    if (betFrom > 14) return '${where}I just check this spot.';
    return '${where}I pot ${_bare(betFrom)}+ and check the rest.';
  }

  String _botFacingSpeech(BetNode node) => _facingSpeech(node);

  String _facingSpeech(BetNode node) {
    final inRange = (_botRange.toList()..sort());
    if (inRange.isEmpty) return '…';
    final folds = <int>[], calls = <int>[], pots = <int>[];
    for (final v in inRange) {
      switch (profile.moveAt(node, v)) {
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
