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

/// How a rank is coloured on the range bar. `check/fold/call/pot/allIn` are the
/// bot's *action* with that card (`allIn` is a pot bet/raise that commits its
/// whole stack — a deeper purple than `pot`); `shown` is the neutral grey "cards
/// he can have". The bar only ever shows the range and the bot's action — never
/// a win/lose/split matchup.
enum RangeBucket { check, fold, call, pot, allIn, shown }

/// A row on the EV hint bar: the immediate (option-A) chip result of one action
/// vs the bot holding a particular card — net chips from the start of the hand,
/// for the lines that resolve the moment the bot answers.
class EvCell {
  const EvCell(
      this.rank, this.active, this.unknown, this.ev, this.color, this.label);

  final Rank rank;
  final bool active; // bot could hold this AND we have a live decision
  final bool unknown; // the ball comes back to us → shown as "?"
  final int ev; // net chips from the start of the hand (signed)
  final double color; // -1 (lose a lot) .. +1 (win a lot) for the gradient
  final String label;
}

/// One rank row on the range bar.
class RankCell {
  const RankCell(this.rank, this.inRange, this.bucket, this.isBotCard,
      {this.splitRight});

  final Rank rank;
  final bool inRange; // still possible for the bot
  final RangeBucket bucket; // colour for the current decision
  final bool isBotCard; // revealed at showdown

  /// When set, the cell is split: left half = [bucket] (our raise = purple),
  /// right half = [splitRight] (his reply to that raise), divided by a line.
  /// Only used on raise-raise / check-raise hovers, for cards that reach our
  /// second raise.
  final RangeBucket? splitRight;
}

/// A two-step "advanced" plan: a [first] action (check or bet/"pot") plus the
/// planned [second] reply taken if the bot puts the ball back to us. The six
/// buttons are check/raise × {raise, call, fold}.
class CompoundPlan {
  const CompoundPlan(this.first, this.second);

  final ActionType first; // check or bet
  final PlanReply second; // raise / call / fold

  @override
  bool operator ==(Object other) =>
      other is CompoundPlan && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

/// Drives the heads-up trainer: the human defends against a fully transparent
/// [BotProfile]. Play, the narration, the range bar and the EV hint all read
/// the *same* profile, so what the bar predicts is exactly what the bot does.
class HeadsUpController extends ChangeNotifier {
  HeadsUpController({BotProfile? profile, int? seed, int startingStack = 50})
      : profile = profile ?? BotProfile.pro,
        rules = RuleConfig(
          startingStack: startingStack,
          smallBlind: 1,
          bigBlind: 1,
          maxPlayers: 2,
        ),
        _rng = seed == null ? Random() : Random(seed) {
    seats = [
      Seat(
          index: 0,
          playerId: 'human',
          name: 'You',
          isHuman: true,
          stack: rules.startingStack),
      Seat(
          index: 1,
          playerId: this.profile.id,
          name: this.profile.name,
          isHuman: false,
          stack: rules.startingStack),
    ];
    _engine = HandEngine(rules, _rng);
    _ev = ImmediateEvCalculator(_engine, this.profile,
        heroSeat: humanSeat, botSeat: botSeat);
    startHand();
  }

  /// Table config, derived from the per-level starting stack (default 50).
  final RuleConfig rules;

  static const int humanSeat = 0;
  static const int botSeat = 1;
  static const Duration _botThink = Duration(milliseconds: 850);
  static const Duration _revealDelay = Duration(milliseconds: 850);
  // Pause between our own moves in a played-out advanced sequence.
  static const Duration _stepDelay = Duration(milliseconds: 650);

  final BotProfile profile;
  final Random _rng;
  late final HandEngine _engine;
  late final ImmediateEvCalculator _ev;
  late final List<Seat> seats;
  late HandState state;

  bool busy = false;
  bool revealShowdown = false;
  bool evOn = false; // the "EV" toggle (was "Hint")
  bool rangeOn = true; // show the range bar
  bool advancedOn = false; // two-step "advanced" action plans

  /// The action the player is hovering, if any — drives which action's EV the
  /// hint bar shows. Exactly one of [hoveredAction] / [hoveredPlan] is non-null.
  ActionType? hoveredAction;
  CompoundPlan? hoveredPlan;

  // The dealer/button alternates each hand (starts on the bot).
  int _button = humanSeat;

  int get buttonSeat => state.button;

  void toggleEv(bool v) {
    evOn = v;
    notifyListeners();
  }

  void toggleRange(bool v) {
    rangeOn = v;
    notifyListeners();
  }

  void toggleAdvanced(bool v) {
    advancedOn = v;
    hoveredAction = null;
    hoveredPlan = null;
    _rebuildRange();
    notifyListeners();
  }

  void setHoveredAction(ActionType? action) {
    if (hoveredAction == action && hoveredPlan == null) return;
    hoveredAction = action;
    hoveredPlan = null;
    _rebuildRange(); // the range bar lights up for the hovered action
    notifyListeners();
  }

  void setHoveredPlan(CompoundPlan? plan) {
    if (hoveredPlan == plan && hoveredAction == null) return;
    hoveredPlan = plan;
    hoveredAction = null;
    _rebuildRange();
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
    hoveredPlan = null;
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
    hoveredPlan = null;
    _engine.applyAction(state, action);
    _rebuildRange();
    notifyListeners();
    _run();
  }

  /// Play a two-step "advanced" plan, narrating each move at a watchable pace:
  /// our first action, the bot's reply, then — only if the bot hands the ball
  /// back — our planned second action and the bot's final reply. If the bot
  /// raises our second raise (raise-raise / check-raise), the sequence stops and
  /// control returns to the player (we don't script a third move).
  Future<void> playCompound(CompoundPlan plan) async {
    if (!isHumanTurn) return;
    hoveredAction = null;
    hoveredPlan = null;
    busy = true;

    _engine.applyAction(state, _planFirst(plan.first));
    _rebuildRange();
    notifyListeners();
    await Future<void>.delayed(_stepDelay);

    await _botRespond();

    // Bot handed the ball back → play our planned second action.
    if (state.phase == HandPhase.betting && state.toAct == humanSeat) {
      final v = humanView;
      if (v != null) {
        await Future<void>.delayed(_stepDelay);
        _engine.applyAction(state, _planSecond(plan.second, v));
        _rebuildRange();
        notifyListeners();
        await Future<void>.delayed(_stepDelay);
        await _botRespond();
      }
    }

    await _settle();
  }

  GameAction _planFirst(ActionType first) => first == ActionType.check
      ? const GameAction.check()
      : const GameAction.bet(0);

  GameAction _planSecond(PlanReply second, GameView v) {
    switch (second) {
      case PlanReply.raise:
        if (v.canBet) return const GameAction.bet(0);
        return v.toCall > 0
            ? GameAction.call(v.toCall)
            : const GameAction.check();
      case PlanReply.call:
        return v.toCall > 0
            ? GameAction.call(v.toCall)
            : const GameAction.check();
      case PlanReply.fold:
        return v.toCall > 0
            ? const GameAction.fold()
            : const GameAction.check();
    }
  }

  // ---- Bot loop -----------------------------------------------------------
  Future<void> _run() async {
    await _botRespond();
    await _settle();
  }

  /// Plays the bot's transparent reply (looping while it's the bot's turn).
  Future<void> _botRespond() async {
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
  }

  /// Ends the turn: clears busy and, if the hand is over, pauses then reveals.
  Future<void> _settle() async {
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
        return view.toCall > 0
            ? GameAction.call(view.toCall)
            : const GameAction.check();
      case BotMove.call:
        return view.toCall > 0
            ? GameAction.call(view.toCall)
            : const GameAction.check();
      case BotMove.check:
        return const GameAction.check();
      case BotMove.fold:
        return view.toCall > 0
            ? const GameAction.fold()
            : const GameAction.check();
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
      rangeCells = _cells(node: node, potAllIn: _potAllIn(state, botSeat));
      statusMessage = '${profile.name} is thinking…';
      return;
    }

    // Human to act: the range bar reflects the action / plan you're hovering.
    statusMessage = 'Your move.';

    // An advanced two-step plan is hovered.
    final plan = hoveredPlan;
    if (plan != null) {
      _buildPlanRange(plan);
      return;
    }

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
      rangeCells = _cells(
          node: node, potAllIn: _botPotAllInAfter(const GameAction.bet(0)));
      return;
    }

    // Checking when the bot still gets to act → colour by his check/bet choice.
    if (action == ActionType.check && !seats[botSeat].hasActed) {
      rangeTitle = 'If you check, ${profile.name} will:';
      botSpeech = _botOpenSpeech(BetNode.checkedTo);
      rangeCells = _cells(
          node: BetNode.checkedTo,
          potAllIn: _botPotAllInAfter(const GameAction.check()));
      return;
    }

    // Call, or a check that ends the hand → it's a showdown. The range bar shows
    // only the range (neutral grey) — never a win/lose/split matchup.
    rangeTitle = action == ActionType.call ? 'If you CALL:' : 'At showdown:';
    botSpeech = _matchupSpeech();
    rangeCells = _cells(neutral: true);
  }

  // ---- Advanced plan range view -------------------------------------------

  void _buildPlanRange(CompoundPlan plan) {
    final first = plan.first == ActionType.check ? 'check' : 'raise';
    final second = plan.second == PlanReply.raise
        ? 'raise'
        : plan.second == PlanReply.call
            ? 'call'
            : 'fold';
    rangeTitle = 'Plan: $first, then $second';
    botSpeech = plan.first == ActionType.bet
        ? _facingSpeech(_botNodeIfHumanPots())
        : _botOpenSpeech(BetNode.checkedTo);
    rangeCells = [for (final r in Rank.values.reversed) _planCell(r, plan)];
  }

  /// One range-bar cell for a hovered plan: coloured by the bot's reply to our
  /// *first* action; for raise-raise / check-raise, cards that actually reach
  /// our second raise are split (our raise = purple | his reply to it).
  RankCell _planCell(Rank r, CompoundPlan plan) {
    final v = r.value;
    if (!_botRange.contains(v)) {
      return RankCell(r, false, RangeBucket.shown, false);
    }

    final s = state.clone();
    _engine.applyAction(s, _planFirst(plan.first));
    if (!(s.phase == HandPhase.betting && s.toAct == botSeat)) {
      return RankCell(r, true, RangeBucket.shown, false); // first move ended it
    }

    final move1 = profile.moveAt(_nodeAt(s, botSeat), v);
    final bucket1 = _bucketForMove(s, botSeat, move1);

    // Split only when our planned second action is a raise and the bot's reply
    // hands the ball back, so our raise actually fires.
    if (plan.second == PlanReply.raise) {
      _engine.applyAction(s, _moveActionAt(s, botSeat, move1));
      if (s.phase == HandPhase.betting && s.toAct == humanSeat) {
        _engine.applyAction(s, _heroRaiseAt(s));
        var right = RangeBucket.shown;
        if (s.phase == HandPhase.betting && s.toAct == botSeat) {
          final move2 = profile.moveAt(_nodeAt(s, botSeat), v);
          right = _bucketForMove(s, botSeat, move2);
        }
        return RankCell(r, true, RangeBucket.pot, false, splitRight: right);
      }
    }
    return RankCell(r, true, bucket1, false);
  }

  // ---- All-in detection ---------------------------------------------------

  /// Whether, in [s] with [seat] to act, a pot-sized bet/raise is all-in (it
  /// commits the seat's whole stack). Card-independent, so it's the same for
  /// every rank at a node.
  bool _potAllIn(HandState s, int seat) {
    if (s.phase != HandPhase.betting || s.toAct != seat) return false;
    return _moveIsAllIn(s, seat);
  }

  bool _moveIsAllIn(HandState s, int seat) {
    final v = _engine.buildView(s, seat);
    final me = s.seats[seat];
    return v.canBet && v.raiseTarget >= me.committed + me.stack;
  }

  /// All-in status of the bot's pot bet in the hypothetical after we play
  /// [heroAction] right now.
  bool _botPotAllInAfter(GameAction heroAction) {
    final s = state.clone();
    _engine.applyAction(s, heroAction);
    return _potAllIn(s, botSeat);
  }

  // ---- State-parameterised helpers (for hypothetical simulation) ----------

  BetNode _nodeAt(HandState s, int seat) {
    final me = s.seats[seat];
    final toCall = s.currentBet - me.committed;
    if (toCall > 0) return _facingNode(s.raiseCount);
    final other = s.seats[seat == botSeat ? humanSeat : botSeat];
    return other.lastAction?.type == ActionType.check
        ? BetNode.checkedTo
        : BetNode.open;
  }

  GameAction _moveActionAt(HandState s, int seat, BotMove move) {
    final me = s.seats[seat];
    final toCall = s.currentBet - me.committed;
    final canBet = me.stack > toCall;
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

  GameAction _heroRaiseAt(HandState s) {
    final me = s.seats[humanSeat];
    final toCall = s.currentBet - me.committed;
    return me.stack > toCall
        ? const GameAction.bet(0)
        : (toCall > 0 ? const GameAction.call(0) : const GameAction.check());
  }

  RangeBucket _bucketForMove(HandState s, int seat, BotMove move) {
    switch (move) {
      case BotMove.pot:
        return _moveIsAllIn(s, seat) ? RangeBucket.allIn : RangeBucket.pot;
      case BotMove.call:
        return RangeBucket.call;
      case BotMove.fold:
        return RangeBucket.fold;
      case BotMove.check:
        return RangeBucket.check;
    }
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

  List<RankCell> _cells(
      {BetNode? node,
      bool neutral = false,
      int? highlight,
      bool potAllIn = false}) {
    final ranks = Rank.values.reversed.toList(); // A (top) → 2 (bottom)
    return [
      for (final r in ranks)
        RankCell(
          r,
          _botRange.contains(r.value),
          neutral ? RangeBucket.shown : _bucketFor(r.value, node!, potAllIn),
          highlight != null && r.value == highlight,
        ),
    ];
  }

  RangeBucket _bucketFor(int v, BetNode node, bool potAllIn) {
    switch (profile.moveAt(node, v)) {
      case BotMove.pot:
        return potAllIn ? RangeBucket.allIn : RangeBucket.pot;
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
    return _assembleEv(_ev.evaluate(state, h, _botRange.toList(), action));
  }

  /// EV cells for a hovered advanced plan — the net chips at the end of the
  /// played-out line per card (or "?" when it ends with the bot raising again).
  List<EvCell> evCellsForCompound(CompoundPlan plan) {
    final ranks = Rank.values.reversed.toList();
    final h = seats[humanSeat].card?.rank.value;
    final view = humanView;
    if (h == null || view == null || !isHumanTurn) {
      return [for (final r in ranks) EvCell(r, false, false, 0, 0, '')];
    }
    return _assembleEv(_ev.evaluateCompound(
        state, h, _botRange.toList(), plan.first, plan.second));
  }

  /// Turn per-card results into bar cells. The colour gradient is scaled by the
  /// biggest swing so the brightest red/green mark the worst/best card. When the
  /// range bar is hidden, cards outside the bot's range show "?" (so the bar
  /// doesn't leak the range) instead of being blanked.
  List<EvCell> _assembleEv(Map<int, ImmediateEv?> results) {
    final ranks = Rank.values.reversed.toList();
    var maxAbs = 1;
    for (final r in results.values) {
      if (r != null && r.ev.abs() > maxAbs) maxAbs = r.ev.abs();
    }
    return [
      for (final r in ranks)
        if (!_botRange.contains(r.value))
          (rangeOn
              ? EvCell(r, false, false, 0, 0, '')
              : EvCell(r, true, true, 0, 0, '?'))
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
    final mine =
        botCard == null ? 'my hand' : 'my ${_bare(botCard.rank.value)}';
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
