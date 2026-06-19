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
import 'human_line.dart';

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

/// One move in the just-played hand, in play order — who acted and what they
/// did. Used to render the "line" preview on the save-line button.
class LineStep {
  const LineStep(this.isHuman, this.type);

  final bool isHuman;
  final ActionType type;
}

/// One branch an advanced plan covers, for the save prompt. A "Check ▸ Raise"
/// plan, say, covers two: [Check] (the bot answers passively → showdown) and
/// [Check, bot bets, Raise] (the bot bets, we raise). [complete] is false when
/// our final action is a raise the bot could still re-raise — the line isn't
/// resolved because we haven't decided how to answer that re-raise.
class PlanLine {
  const PlanLine(this.steps, this.complete);

  final List<LineStep> steps;
  final bool complete;
}

/// Drives the heads-up trainer: the human defends against a fully transparent
/// [BotProfile]. Play, the narration, the range bar and the EV hint all read
/// the *same* profile, so what the bar predicts is exactly what the bot does.
class HeadsUpController extends ChangeNotifier {
  HeadsUpController({
    BotProfile? profile,
    int? seed,
    int startingStack = 50,
    this.autoPlayUnlocked = false,
    HumanLine? initialLine,
  })  : profile = profile ?? BotProfile.pro,
        savedLine = initialLine ?? HumanLine(),
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

  /// Whether the "automate your range" features (save-line + auto-play) are
  /// available here. Unlocked once the level has been beaten (see
  /// docs/expansion-plans.md §1); always false in free-play.
  final bool autoPlayUnlocked;

  /// The "Auto" toggle: when on (and a move is saved for the spot) the player's
  /// saved line is played out for them, hand after hand, at a watchable pace.
  bool autoPlayOn = false;

  /// Whether a screen is currently showing this controller. The map keeps a
  /// cleared level's controller alive after you leave the table, so auto-play
  /// keeps running in the background. When detached, a bust (win *or* loss)
  /// shouldn't freeze on the end-of-session screen with nobody watching — it
  /// silently resets and plays on. Set by the screen on attach/detach.
  bool screenAttached = false;

  /// The player's saved strategy for this level — grows each time they capture a
  /// hand with [saveLine]. Persisted by the screen via [onLineChanged].
  HumanLine savedLine;

  /// Persistence hook, set by the screen: called after [saveLine] mutates
  /// [savedLine] so the new line is written to disk.
  VoidCallback? onLineChanged;

  // The decisions captured in the *current* hand, committed into [savedLine]
  // only when the player hits "Save line".
  HumanLine _pendingLine = HumanLine();
  bool _lineSaved = false;

  /// Every move of the current hand in play order (both seats), for the save
  /// button's line preview. Reset each hand.
  final List<LineStep> handLog = [];

  /// The line as it's actually saved: [handLog] truncated at our last action.
  /// A trailing bot move (its reply to our final bet) isn't a decision we store,
  /// so the save preview shouldn't show it either.
  List<LineStep> get savableLine {
    var end = handLog.length;
    while (end > 0 && !handLog[end - 1].isHuman) {
      end--;
    }
    return handLog.sublist(0, end);
  }

  /// When the just-played hand was an advanced plan, the branches it covers —
  /// each saved on "Save line". Empty for simple actions (use [savableLine]).
  List<PlanLine> _planLines = const [];
  List<PlanLine> get planLines => _planLines;

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

  void toggleAutoPlay(bool v) {
    autoPlayOn = v;
    notifyListeners();
    if (v) _maybeAutoStep(); // kick it off if it's already our turn
  }

  /// Called by the screen when it detaches from a map-owned controller. If
  /// auto-play left the session resting on a bust (so nothing else will fire
  /// [_afterSettle]), restart it now that there's nobody watching the result.
  void maybeResumeUnattended() {
    if (autoPlayOn && !screenAttached && handOver && sessionOver) {
      resetSession();
    }
  }

  /// Replace the saved line (used by the screen once it has loaded the level's
  /// line from disk).
  void setSavedLine(HumanLine line) {
    savedLine = line;
    notifyListeners();
  }

  /// Whether there's a fresh, unsaved capture to commit right now.
  bool get canSaveLine =>
      autoPlayUnlocked && handOver && !_pendingLine.isEmpty && !_lineSaved;

  /// Whether the current hand's capture has already been saved.
  bool get lineSaved => _lineSaved;

  /// True in the brief gap where auto-play has finished a hand cleanly and is
  /// about to deal the next one itself. The screen uses this to suppress the
  /// manual "Next Hand" button, which would otherwise flash for an instant.
  bool get autoAdvancing =>
      autoPlayOn && handOver && !sessionOver && _pendingLine.isEmpty;

  /// How many (spot, card) decisions the saved line currently covers.
  int get savedMoveCount => savedLine.count;

  /// Auto-play is on and a hand is actively in motion (bot thinking, our saved
  /// move stepping, or between hands) — drives the map badge's "playing" pulse.
  bool get autoPlaying => autoPlayOn && !sessionOver && !isHumanTurn;

  /// Auto-play is on but it hit a spot with no saved move and is waiting for a
  /// human decision — drives the map badge's "paused" indicator.
  bool get autoPaused => autoPlayOn && isHumanTurn;

  /// Commit the current hand's captured decisions into [savedLine] and persist.
  void saveLine() {
    if (!canSaveLine) return;
    savedLine.merge(_pendingLine);
    _lineSaved = true;
    onLineChanged?.call();
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
    _pendingLine = HumanLine(); // fresh capture for the new hand
    _lineSaved = false;
    _planLines = const [];
    handLog.clear();
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
    _planLines = const []; // a simple action — the single-line preview applies
    _capture(action);
    handLog.add(LineStep(true, action.type));
    _engine.applyAction(state, action);
    _rebuildRange();
    notifyListeners();
    _run();
  }

  /// Capture a human decision into the current hand's pending line, keyed by the
  /// spot ([BetNode]) and our card. Read *before* the action is applied, so the
  /// node reflects what we're facing. No-op if the feature is locked.
  void _capture(GameAction action) {
    if (!autoPlayUnlocked) return;
    final card = seats[humanSeat].card;
    if (card == null || state.toAct != humanSeat) return;
    _pendingLine.record(
        _nodeForSeat(humanSeat), card.rank.value, _moveOf(action));
  }

  BotMove _moveOf(GameAction action) {
    switch (action.type) {
      case ActionType.fold:
        return BotMove.fold;
      case ActionType.check:
        return BotMove.check;
      case ActionType.call:
        return BotMove.call;
      case ActionType.bet:
        return BotMove.pot;
    }
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

    // Capture *both* branches of the plan up front (our first action and our
    // planned reply if the bot puts the ball back), so the saved line covers
    // both contingencies even if only one actually plays out this hand.
    _captureCompound(plan);

    final firstAction = _planFirst(plan.first);
    handLog.add(LineStep(true, firstAction.type));
    _engine.applyAction(state, firstAction);
    _rebuildRange();
    notifyListeners();
    await Future<void>.delayed(_stepDelay);

    await _botRespond();

    // Bot handed the ball back → play our planned second action.
    if (state.phase == HandPhase.betting && state.toAct == humanSeat) {
      final v = humanView;
      if (v != null) {
        await Future<void>.delayed(_stepDelay);
        final secondAction = _planSecond(plan.second, v);
        handLog.add(LineStep(true, secondAction.type));
        _engine.applyAction(state, secondAction);
        _rebuildRange();
        notifyListeners();
        await Future<void>.delayed(_stepDelay);
        await _botRespond();
      }
    }

    await _settle();
  }

  /// Record both of an advanced plan's decisions into the pending line, and
  /// build the [planLines] preview. Reads the live state *before* anything is
  /// played, simulating the bot's aggressive reply to find the node our second
  /// action would face. No-op for capture if the feature is locked, but the
  /// preview is still built so the save prompt can show the branches.
  void _captureCompound(CompoundPlan plan) {
    final card = seats[humanSeat].card;
    if (card == null || state.toAct != humanSeat) {
      _planLines = const [];
      return;
    }
    final v = card.rank.value;
    final firstAction = _planFirst(plan.first);

    if (autoPlayUnlocked) {
      _pendingLine.record(
          _nodeForSeat(humanSeat), v, _moveOf(firstAction));
    }

    // Branch A: our first action, then the bot answers passively → showdown.
    final lines = <PlanLine>[PlanLine([LineStep(true, plan.first)], true)];

    // Branch B: simulate our first action + the bot's aggressive reply to see
    // whether the second decision is even reachable, and at which node.
    final sim = state.clone();
    _engine.applyAction(sim, firstAction);
    if (sim.phase == HandPhase.betting && sim.toAct == botSeat) {
      final botView = _engine.buildView(sim, botSeat);
      if (botView.canBet) {
        _engine.applyAction(sim, const GameAction.bet(0)); // bot's raise
        if (sim.phase == HandPhase.betting && sim.toAct == humanSeat) {
          final node2 = _nodeAt(sim, humanSeat);
          if (autoPlayUnlocked) {
            _pendingLine.record(node2, v, _secondMove(plan.second));
          }
          lines.add(PlanLine(
            [
              LineStep(true, plan.first),
              const LineStep(false, ActionType.bet),
              LineStep(true, _planReplyType(plan.second)),
            ],
            _branchBComplete(plan, sim),
          ));
        }
      }
    }
    _planLines = lines;
  }

  /// The saved [BotMove] for the planned second action.
  BotMove _secondMove(PlanReply r) {
    switch (r) {
      case PlanReply.raise:
        return BotMove.pot;
      case PlanReply.call:
        return BotMove.call;
      case PlanReply.fold:
        return BotMove.fold;
    }
  }

  /// The [ActionType] to *show* for the planned second action (a raise is a bet
  /// over the bot's bet).
  ActionType _planReplyType(PlanReply r) {
    switch (r) {
      case PlanReply.raise:
        return ActionType.bet;
      case PlanReply.call:
        return ActionType.call;
      case PlanReply.fold:
        return ActionType.fold;
    }
  }

  /// Branch B is resolved unless our final action is a raise the bot could still
  /// re-raise: if any card the bot can hold here pots over our raise, we haven't
  /// decided the answer, so the line isn't complete. [sim] is the state with the
  /// bot to act after raising into our check/bet.
  bool _branchBComplete(CompoundPlan plan, HandState sim) {
    if (plan.second != PlanReply.raise) return true; // call/fold ends it
    final s = sim.clone();
    _engine.applyAction(s, _heroRaiseAt(s)); // our raise
    if (!(s.phase == HandPhase.betting && s.toAct == botSeat)) return true;
    final node = _nodeAt(s, botSeat);
    return !_botRange.any((vv) => profile.moveAt(node, vv) == BotMove.pot);
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
      final botAction = _moveAction(move, view);
      handLog.add(LineStep(false, botAction.type));
      _engine.applyAction(state, botAction);
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
    await _afterSettle();
  }

  /// Auto-play hook, run at the end of every settle. With auto-play on we either
  /// play our saved move for the current spot, or — when the hand is over and we
  /// never had to step in by hand — deal the next hand so the line keeps playing.
  Future<void> _afterSettle() async {
    if (!autoPlayOn) return;
    if (isHumanTurn) {
      await _maybeAutoStep();
      return;
    }
    // Hand finished cleanly under auto-play (no manual decision to save) → keep
    // the line rolling. If we *did* step in, _pendingLine isn't empty, so we
    // stop and let the player hit Save.
    if (handOver && _pendingLine.isEmpty) {
      if (!sessionOver) {
        await Future<void>.delayed(_revealDelay);
        if (autoPlayOn && handOver && !sessionOver) startHand();
      } else if (!screenAttached) {
        // Running unattended (player left the table): a bust either way
        // shouldn't stop the show — reset the whole session and play on.
        await Future<void>.delayed(_revealDelay);
        if (autoPlayOn && sessionOver && !screenAttached) resetSession();
      }
    }
  }

  /// If it's our turn and the saved line covers this spot, play that move at a
  /// watchable pace and run the rest of the hand out. If the spot isn't covered,
  /// hand control back to the player (and let them capture it).
  Future<void> _maybeAutoStep() async {
    if (!autoPlayOn || !isHumanTurn) return;
    final card = seats[humanSeat].card;
    final node = _nodeForSeat(humanSeat);
    final move = card == null ? null : savedLine.moveAt(node, card.rank.value);
    if (move == null) {
      statusMessage = 'Auto-play: no saved move for this spot — your call.';
      notifyListeners();
      return;
    }
    busy = true;
    statusMessage = 'Auto-playing your saved line…';
    _rebuildRange();
    notifyListeners();
    await Future<void>.delayed(_stepDelay);
    final view = humanView;
    if (view == null) {
      busy = false;
      notifyListeners();
      return;
    }
    final autoAction = _moveAction(move, view);
    handLog.add(LineStep(true, autoAction.type));
    _engine.applyAction(state, autoAction);
    _rebuildRange();
    notifyListeners();
    await _botRespond();
    await _settle(); // recurses through _afterSettle for any further spots
  }

  /// The betting node the bot is currently at (or would face).
  BetNode _botNode() => _nodeForSeat(botSeat);

  /// The node the bot would be at if the human bets/raises (pots) right now.
  BetNode _botNodeIfHumanPots() => _facingNode(state.raiseCount + 1);

  /// Would the bot — with its *current* range — ever shove back if the human
  /// pots/raises right now? When false there's no second decision to plan for:
  /// the bot only calls or folds, so a two-step "Raise ▸ …" plan is pointless.
  bool get botRaisesAfterPot {
    final node = _botNodeIfHumanPots();
    return _botRange.any((v) => profile.moveAt(node, v) == BotMove.pot);
  }

  /// Would the bot ever bet after the human checks? When false the bot just
  /// checks behind and the hand goes to showdown, so a "Check ▸ …" plan never
  /// triggers its second step.
  bool get botRaisesAfterCheck =>
      _botRange.any((v) => profile.moveAt(BetNode.checkedTo, v) == BotMove.pot);

  /// Would the bot's bet after the human checks be all-in? If so the human
  /// can't raise over it, so a "Check ▸ Raise" plan is impossible.
  bool get botShovesAfterCheck =>
      _botPotIsAllInAfter(const GameAction.check());

  /// Would the bot's re-raise after the human pots be all-in? If so the human
  /// can't raise again, so a "Raise ▸ Raise" plan is impossible.
  bool get botShovesAfterPot => _botPotIsAllInAfter(const GameAction.bet(0));

  /// Whether the bot's pot bet/raise would commit his whole stack in the spot
  /// after the human plays [heroAction] now.
  bool _botPotIsAllInAfter(GameAction heroAction) {
    final s = _botStateAfter(heroAction);
    if (!_botWillAct(s)) return false;
    final me = s.seats[botSeat];
    final v = _engine.buildView(s, botSeat);
    return v.canBet && v.raiseTarget >= me.committed + me.stack;
  }

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
        highlight: revealShowdown ? seats[botSeat].card?.rank.value : null,
      );
      return;
    }

    if (state.toAct == botSeat) {
      final node = _botNode();
      final facing = node != BetNode.open && node != BetNode.checkedTo;
      rangeTitle = facing ? 'Facing your raise I would:' : 'My range';
      botSpeech = facing ? _botFacingSpeech(node) : _botOpenSpeech(node);
      rangeCells = _cellsForBotDecision(state);
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
      rangeCells = _cells();
      return;
    }

    // Betting → colour by his response to the bet/raise. If he's already all-in
    // (e.g. forced in by the blind) your pot can't make him act, so it's just a
    // showdown — his whole range shows grey.
    if (action == ActionType.bet) {
      final s = _botStateAfter(const GameAction.bet(0));
      if (_botWillAct(s)) {
        rangeTitle = 'If you POT, ${profile.name} will:';
        botSpeech = _facingSpeech(_nodeAt(s, botSeat));
      } else {
        rangeTitle = "${profile.name}'s range";
        botSpeech = _matchupSpeech();
      }
      rangeCells = _cellsForBotDecision(s);
      return;
    }

    // Checking when the bot still gets to act → colour by his check/bet choice.
    if (action == ActionType.check && !seats[botSeat].hasActed) {
      final s = _botStateAfter(const GameAction.check());
      if (_botWillAct(s)) {
        rangeTitle = 'If you check, ${profile.name} will:';
        botSpeech = _botOpenSpeech(BetNode.checkedTo);
      } else {
        rangeTitle = "${profile.name}'s range";
        botSpeech = _matchupSpeech();
      }
      rangeCells = _cellsForBotDecision(s);
      return;
    }

    // Call, or a check that ends the hand → it's a showdown. The range bar shows
    // only the range (neutral grey) — never a win/lose/split matchup.
    rangeTitle = "${profile.name}'s range";
    botSpeech = _matchupSpeech();
    rangeCells = _cells();
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
    final bucket1 = _liveBucket(s, v);

    // Split only when our planned second action is a raise and the bot's reply
    // hands the ball back, so our raise actually fires.
    if (plan.second == PlanReply.raise) {
      _engine.applyAction(s, _moveActionAt(s, botSeat, move1));
      if (s.phase == HandPhase.betting && s.toAct == humanSeat) {
        _engine.applyAction(s, _heroRaiseAt(s));
        var right = RangeBucket.shown;
        if (s.phase == HandPhase.betting && s.toAct == botSeat) {
          right = _liveBucket(s, v);
        }
        return RankCell(r, true, RangeBucket.pot, false, splitRight: right);
      }
    }
    return RankCell(r, true, bucket1, false);
  }

  // ---- Bot-decision range cells -------------------------------------------

  /// The state after the human plays [heroAction] right now — used to ask what
  /// the bot would face (and whether he even gets to act) in that line.
  HandState _botStateAfter(GameAction heroAction) {
    final s = state.clone();
    _engine.applyAction(s, heroAction);
    return s;
  }

  /// Whether the bot still has a live betting decision in [s]. False once he's
  /// all-in (e.g. forced in by the blind) or the round is over — then there's
  /// nothing for him to do and his whole range just goes to showdown.
  bool _botWillAct(HandState s) =>
      s.phase == HandPhase.betting && s.toAct == botSeat;

  /// Range-bar cells for the spot where the bot is about to act in [s]. If he
  /// has no decision left, the whole range is shown neutral grey.
  List<RankCell> _cellsForBotDecision(HandState s) {
    if (!_botWillAct(s)) return _cells();
    return [
      for (final r in Rank.values.reversed)
        RankCell(r, _botRange.contains(r.value), _liveBucket(s, r.value), false),
    ];
  }

  /// The bucket to paint for card [v] given the bot is to act in [s] — what he
  /// can *actually* do with his stack, not just his preferred move:
  ///   - a raise he can only make all-in still paints as a raise (no separate
  ///     all-in colour, and the same range as a normal raise);
  ///   - a "raise" he's too short to make collapses into the call (all-in) or
  ///     check he's forced into;
  ///   - an all-in call is just a call.
  RangeBucket _liveBucket(HandState s, int v) {
    final me = s.seats[botSeat];
    final toCall = s.currentBet - me.committed;
    final canBet = me.stack > toCall;
    switch (profile.moveAt(_nodeAt(s, botSeat), v)) {
      case BotMove.pot:
        if (canBet) return RangeBucket.pot;
        return toCall > 0 ? RangeBucket.call : RangeBucket.check;
      case BotMove.call:
        return toCall > 0 ? RangeBucket.call : RangeBucket.check;
      case BotMove.fold:
        return toCall > 0 ? RangeBucket.fold : RangeBucket.check;
      case BotMove.check:
        return RangeBucket.check;
    }
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

  /// The bot's whole range shown neutral grey — for showdowns and any spot
  /// where he has no live decision. [highlight] outlines a revealed card.
  List<RankCell> _cells({int? highlight}) {
    final ranks = Rank.values.reversed.toList(); // A (top) → 2 (bottom)
    return [
      for (final r in ranks)
        RankCell(
          r,
          _botRange.contains(r.value),
          RangeBucket.shown,
          highlight != null && r.value == highlight,
        ),
    ];
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
