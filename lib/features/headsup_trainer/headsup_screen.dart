import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../engine/cards/card.dart';
import '../../engine/ev/immediate_ev.dart' show PlanReply;
import '../../engine/game/action.dart';
import '../../engine/game/hand_state.dart';
import '../../engine/game/seat.dart';
import '../../engine/players/bot_profile.dart';
import '../../theme/app_colors.dart';
import '../adventure_map/line_store.dart';
import '../quest_one_card/widgets/chip_stack_widget.dart';
import '../quest_one_card/widgets/playing_card_widget.dart';
import 'headsup_controller.dart';
import 'widgets/ev_bar.dart';
import 'widgets/range_bar.dart';

/// Heads-up trainer: defend your big blind against a transparent range bot.
///
/// Reached two ways: free-play from the bot picker ([levelTitle] null), or as a
/// map level — then [levelTitle] names the level and busting the bot pops `true`
/// back to the map to mark it complete.
class HeadsUpScreen extends StatefulWidget {
  const HeadsUpScreen({
    super.key,
    required this.profile,
    this.startingStack = 50,
    this.levelTitle,
    this.levelId,
    this.autoPlayUnlocked = false,
    this.lineStore,
    this.controller,
  });

  /// An externally-owned controller (the map keeps it alive so auto-play can
  /// keep running after you leave the screen). When null, the screen creates and
  /// owns its own.
  final HeadsUpController? controller;

  final BotProfile profile;
  final int startingStack;

  /// When non-null, this screen is a map level: the top bar shows this title and
  /// busting the bot offers a "Level Complete" button that pops `true`.
  final String? levelTitle;

  /// The level's id — the key the saved line is persisted under. Null in
  /// free-play (no saving).
  final int? levelId;

  /// Whether the "automate your range" features (save-line + auto-play) are
  /// available — true only on a level the player has already cleared.
  final bool autoPlayUnlocked;

  /// Where the saved line is loaded from / persisted to. Provided by the map for
  /// unlocked levels; null in free-play.
  final LineStore? lineStore;

  @override
  State<HeadsUpScreen> createState() => _HeadsUpScreenState();
}

class _HeadsUpScreenState extends State<HeadsUpScreen> {
  late final HeadsUpController controller;
  late final bool _ownsController;

  bool get _isLevel => widget.levelTitle != null;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      // Map-owned: it stays alive after we leave, so don't dispose or re-wire.
      controller = widget.controller!;
      _ownsController = false;
      controller.screenAttached = true;
    } else {
      controller = HeadsUpController(
        profile: widget.profile,
        startingStack: widget.startingStack,
        autoPlayUnlocked: widget.autoPlayUnlocked,
      );
      _ownsController = true;
      final store = widget.lineStore;
      final id = widget.levelId;
      if (widget.autoPlayUnlocked && store != null && id != null) {
        controller.onLineChanged = () => store.save(id, controller.savedLine);
        store.load(id).then((line) {
          if (mounted) controller.setSavedLine(line);
        });
      }
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      controller.dispose();
    } else {
      // Map-owned controller lives on; mark it detached so auto-play knows it's
      // now running unattended and should reset itself on a bust.
      controller.screenAttached = false;
      controller.maybeResumeUnattended();
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is KeyDownEvent && isEnter && controller.handOver) {
      controller.sessionOver
          ? controller.resetSession()
          : controller.startHand();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundTop, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final state = controller.state;
                return Column(
                  children: [
                    _TopBar(
                      controller: controller,
                      title: widget.levelTitle ?? 'Heads-Up Trainer',
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _Table(controller: controller)),
                            if (controller.rangeOn) ...[
                              const SizedBox(width: 8),
                              RangeBar(
                                title: controller.rangeTitle,
                                cells: controller.rangeCells,
                              ),
                            ],
                            if (controller.evOn) ...[
                              const SizedBox(width: 8),
                              EvBar(
                                title: controller.hoveredPlan != null
                                    ? _planEvTitle(controller.hoveredPlan!)
                                    : _evTitle(controller.hoveredAction),
                                cells: controller.hoveredPlan != null
                                    ? controller.evCellsForCompound(
                                        controller.hoveredPlan!)
                                    : controller.hoveredAction == null
                                        ? const []
                                        : controller.evCellsForAction(
                                            controller.hoveredAction!),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _BottomPanel(
                      controller: controller,
                      state: state,
                      onLevelComplete:
                          _isLevel ? () => Navigator.of(context).pop(true) : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _evTitle(ActionType? action) {
  switch (action) {
    case ActionType.bet:
      return 'IMMEDIATE EV\nif you pot';
    case ActionType.call:
      return 'IMMEDIATE EV\nif you call';
    case ActionType.check:
      return 'IMMEDIATE EV\nif you check';
    case ActionType.fold:
      return 'IMMEDIATE EV\nif you fold';
    case null:
      return 'IMMEDIATE EV';
  }
}

String _planEvTitle(CompoundPlan plan) {
  final first = plan.first == ActionType.check ? 'check' : 'raise';
  final second = plan.second == PlanReply.raise
      ? 'raise'
      : plan.second == PlanReply.call
          ? 'call'
          : 'fold';
  return 'EV — $first\nthen $second';
}

class _Table extends StatelessWidget {
  const _Table({required this.controller});

  final HeadsUpController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final bot = state.seats[HeadsUpController.botSeat];
    final human = state.seats[HeadsUpController.humanSeat];

    final dealerOnBot = state.button == HeadsUpController.botSeat;

    return Stack(
      children: [
        Column(
          children: [
            _SeatRow(
              seat: bot,
              faceUp: controller.revealShowdown && !bot.folded,
              isActive: state.toAct == HeadsUpController.botSeat &&
                  !controller.handOver,
              isWinner: controller.handOver &&
                  state.winners.contains(HeadsUpController.botSeat),
              blind: _blindFor(state, HeadsUpController.botSeat),
            ),
            const SizedBox(height: 8),
            _SpeechBubble(text: controller.botSpeech),
            const Spacer(),
            _PotPill(amount: state.pot, status: controller.statusMessage),
            const Spacer(),
            _SeatRow(
              seat: human,
              faceUp: true,
              isActive: controller.isHumanTurn,
              isWinner: controller.handOver &&
                  state.winners.contains(HeadsUpController.humanSeat),
              blind: _blindFor(state, HeadsUpController.humanSeat),
            ),
          ],
        ),
        // Dealer button that slides between the two players each hand.
        AnimatedAlign(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: Alignment(0.96, dealerOnBot ? -0.62 : 0.62),
          child: const _DealerButton(),
        ),
      ],
    );
  }

  String? _blindFor(HandState state, int seat) {
    if (seat == state.smallBlindSeat) return 'SB';
    if (seat == state.bigBlindSeat) return 'BB';
    return null;
  }
}

class _DealerButton extends StatelessWidget {
  const _DealerButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            const RadialGradient(colors: [Colors.white, Color(0xFFE9E2CF)]),
        border: Border.all(color: AppColors.goldDeep, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'D',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: AppColors.cardBlack,
          height: 1,
        ),
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.seat,
    required this.faceUp,
    required this.isActive,
    required this.isWinner,
    required this.blind,
  });

  final Seat seat;
  final bool faceUp;
  final bool isActive;
  final bool isWinner;
  final String? blind;

  @override
  Widget build(BuildContext context) {
    final ring = isWinner
        ? AppColors.win
        : isActive
            ? AppColors.goldBright
            : Colors.white24;
    return Row(
      children: [
        PlayingCardWidget(
            card: seat.card, faceUp: faceUp, width: 50, highlight: isWinner),
        const SizedBox(width: 12),
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.feltLight, AppColors.feltEdge],
            ),
            border:
                Border.all(color: ring, width: isActive || isWinner ? 3 : 1.5),
          ),
          child: Text(seat.isHuman ? '🙂' : '🤖',
              style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  seat.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (blind != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.chipBlue.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.chipBlue.withValues(alpha: 0.7)),
                    ),
                    child: Text(
                      blind!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${seat.stack} chips',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.goldBright,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        if (seat.lastAction != null) _ActionTag(action: seat.lastAction!),
        const Spacer(),
        if (seat.committed > 0 && !seat.folded)
          ChipStackWidget(amount: seat.committed),
      ],
    );
  }
}

class _ActionTag extends StatelessWidget {
  const _ActionTag({required this.action});

  final GameAction action;

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    )
        .animate(key: ValueKey('${action.type}_${action.amount}'))
        .fadeIn(duration: 200.ms)
        .scaleXY(begin: 0.7, end: 1);
  }

  String _label() {
    switch (action.type) {
      case ActionType.bet:
        return 'POT ${action.amount}';
      case ActionType.call:
        return 'CALL ${action.amount}';
      case ActionType.check:
        return 'CHECK';
      case ActionType.fold:
        return 'FOLD';
    }
  }

  Color _color() {
    switch (action.type) {
      case ActionType.bet:
        return AppColors.potPurple;
      case ActionType.call:
        return AppColors.chipGreen;
      case ActionType.check:
        return AppColors.chipBlue;
      case ActionType.fold:
        return AppColors.danger;
    }
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox(height: 8);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.feltDark.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('💬 ', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    )
        .animate(key: ValueKey(text))
        .fadeIn(duration: 250.ms)
        .slideY(begin: -0.15);
  }
}

class _PotPill extends StatelessWidget {
  const _PotPill({required this.amount, required this.status});

  final int amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('POT  ',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted)),
              ChipStackWidget(amount: amount),
            ],
          ),
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            status,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.title});

  final HeadsUpController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          if (controller.autoPlayUnlocked)
            _MiniToggle(
              label: 'Auto',
              value: controller.autoPlayOn,
              onChanged: controller.toggleAutoPlay,
            ),
          _MiniToggle(
            label: 'EV',
            value: controller.evOn,
            onChanged: controller.toggleEv,
          ),
          _MiniToggle(
            label: 'Range',
            value: controller.rangeOn,
            onChanged: controller.toggleRange,
          ),
          _MiniToggle(
            label: 'Advanced',
            value: controller.advancedOn,
            onChanged: controller.toggleAdvanced,
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Transform.scale(
          scale: 0.78,
          child: Switch(
            value: value,
            activeThumbColor: AppColors.potPurple,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.controller,
    required this.state,
    this.onLevelComplete,
  });

  final HeadsUpController controller;
  final HandState state;

  /// In map-level mode: called when the player busts the bot, to pop the win
  /// result back to the map. Null in free-play.
  final VoidCallback? onLevelComplete;

  @override
  Widget build(BuildContext context) {
    final view = controller.humanView;
    final live = !controller.handOver && controller.isHumanTurn && view != null;
    final buttons = live ? _liveButtons(view) : const <Widget>[];
    final twoRows = buttons.length > 4;
    // The save-line prompt (card + colored action blocks) is taller than a row
    // of buttons, so it gets its own height.
    final savePrompt = controller.handOver &&
        !controller.autoAdvancing &&
        controller.canSaveLine &&
        !controller.sessionOver;
    // An advanced plan shows two branch lines stacked, so it needs more height.
    final tallSave = savePrompt && controller.planLines.length > 1;
    final height = tallSave
        ? 160.0
        : (savePrompt ? 124.0 : (twoRows ? 132.0 : 78.0));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      height: height,
      child: controller.handOver
          // Auto-play is about to deal the next hand itself — don't flash a
          // manual "Next Hand" button in the gap.
          ? (controller.autoAdvancing
              ? _waiting()
              : savePrompt
                  ? _SaveLinePrompt(
                      controller: controller, onDecline: controller.startHand)
                  : _primaryEndButton())
          : live
              ? _layout(buttons, twoRows)
              : _waiting(),
    );
  }

  Widget _waiting() => Center(
        child: Text(
          controller.statusMessage,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _layout(List<Widget> buttons, bool twoRows) {
    if (!twoRows) return _row(buttons);
    final mid = (buttons.length / 2).ceil();
    return Column(
      children: [
        Expanded(child: _row(buttons.sublist(0, mid))),
        const SizedBox(height: 8),
        Expanded(child: _row(buttons.sublist(mid))),
      ],
    );
  }

  Widget _row(List<Widget> buttons) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ],
      );

  Widget _primaryEndButton() {
    if (controller.sessionOver) {
      final won = controller.botBusted;
      // Map level + win → hand the victory back to the map to unlock the next.
      if (won && onLevelComplete != null) {
        return _FullButton(
          label: '🏆 Level cleared! — Continue',
          color: AppColors.goldDeep,
          onTap: onLevelComplete!,
        );
      }
      return _FullButton(
        label: won ? '🏆 You busted the bot! — Play again' : 'Out of chips — Reset',
        color: won ? AppColors.goldDeep : AppColors.danger,
        onTap: controller.resetSession,
      );
    }
    return _FullButton(
      label: 'Next Hand',
      color: AppColors.feltLight,
      onTap: controller.startHand,
    );
  }

  /// The action buttons for the player's turn. With the "advanced" toggle on,
  /// and when we're not last to act, the plain Check/Pot are replaced by
  /// two-step plans (see [_advancedButtons]).
  List<Widget> _liveButtons(view) {
    // On touch there's no hover, so the first tap *arms* an action (revealing
    // its range/EV info) and a second tap confirms — but only while there's
    // something to preview (a toggle is on). On desktop, hover arms.
    final previewOn = controller.evOn || controller.rangeOn;
    return controller.advancedOn
        ? _advancedButtons(view, previewOn)
        : _simpleButtons(view, previewOn);
  }

  List<Widget> _simpleButtons(view, bool previewOn) => [
        if (view.toCall > 0)
          _simpleBtn('Fold', AppColors.danger, ActionType.fold, controller.fold,
              previewOn),
        if (view.canCheck)
          _simpleBtn('Check', AppColors.chipBlue, ActionType.check,
              controller.check, previewOn),
        if (view.canCall)
          _simpleBtn('Call ${view.toCall}', AppColors.chipGreen,
              ActionType.call, controller.call, previewOn),
        if (view.canBet)
          _simpleBtn('Pot ${view.raiseTarget}', AppColors.potPurpleDeep,
              ActionType.bet, controller.pot, previewOn),
      ];

  /// Two-step plans. First-to-act → the six check/raise plans. Facing a bet →
  /// Fold / Call / the three raise plans. After the bot checks to us → Check /
  /// the three raise plans (a check would just end the hand, so check-plans
  /// don't apply there).
  List<Widget> _advancedButtons(view, bool previewOn) {
    final facing = view.toCall > 0;
    final botChecked =
        controller.state.seats[HeadsUpController.botSeat].lastAction?.type ==
            ActionType.check;
    // A two-step plan only makes sense if the bot would actually put the ball
    // back. If after your raise the bot only ever calls/folds, the "Raise ▸ …"
    // plans collapse to a plain Pot; same for "Check ▸ …" if the bot checks
    // behind your check.
    final raiseStep = view.canBet
        ? (controller.botRaisesAfterPot
            ? _raisePlans(previewOn)
            : [_simplePotBtn(view, previewOn, dense: true)])
        : const <Widget>[];
    if (facing) {
      return [
        _simpleBtn('Fold', AppColors.danger, ActionType.fold, controller.fold,
            previewOn,
            dense: true),
        _simpleBtn('Call ${view.toCall}', AppColors.chipGreen, ActionType.call,
            controller.call, previewOn,
            dense: true),
        ...raiseStep,
      ];
    }
    if (botChecked) {
      return [
        _simpleBtn('Check', AppColors.chipBlue, ActionType.check,
            controller.check, previewOn,
            dense: true),
        ...raiseStep,
      ];
    }
    return [
      if (controller.botRaisesAfterCheck)
        ..._checkPlans(previewOn)
      else
        _simpleBtn('Check', AppColors.chipBlue, ActionType.check,
            controller.check, previewOn,
            dense: true),
      ...raiseStep,
    ];
  }

  Widget _simplePotBtn(view, bool previewOn, {bool dense = false}) => _simpleBtn(
      'Pot ${view.raiseTarget}',
      AppColors.potPurpleDeep,
      ActionType.bet,
      controller.pot,
      previewOn,
      dense: dense);

  List<Widget> _checkPlans(bool previewOn) => [
        // If the bot's bet would be all-in, you can't raise over it — drop the
        // "▸ Raise" plan.
        if (!controller.botShovesAfterCheck)
          _planBtn(const CompoundPlan(ActionType.check, PlanReply.raise),
              'Check ▸ Raise', AppColors.potPurpleDeep, previewOn),
        _planBtn(const CompoundPlan(ActionType.check, PlanReply.call),
            'Check ▸ Call', AppColors.chipGreen, previewOn),
        _planBtn(const CompoundPlan(ActionType.check, PlanReply.fold),
            'Check ▸ Fold', AppColors.danger, previewOn),
      ];

  List<Widget> _raisePlans(bool previewOn) => [
        // If the bot's re-raise would be all-in, you can't raise again — drop
        // the "▸ Raise" plan.
        if (!controller.botShovesAfterPot)
          _planBtn(const CompoundPlan(ActionType.bet, PlanReply.raise),
              'Raise ▸ Raise', AppColors.potPurpleDeep, previewOn),
        _planBtn(const CompoundPlan(ActionType.bet, PlanReply.call),
            'Raise ▸ Call', AppColors.chipGreen, previewOn),
        _planBtn(const CompoundPlan(ActionType.bet, PlanReply.fold),
            'Raise ▸ Fold', AppColors.danger, previewOn),
      ];

  Widget _simpleBtn(String label, Color color, ActionType type,
          VoidCallback onConfirm, bool previewOn,
          {bool dense = false}) =>
      _ActBtn(
        label: label,
        color: color,
        dense: dense,
        armed: controller.hoveredAction == type,
        previewOn: previewOn,
        onConfirm: onConfirm,
        onHover: (h) => controller.setHoveredAction(h ? type : null),
      );

  Widget _planBtn(
          CompoundPlan plan, String label, Color color, bool previewOn) =>
      _ActBtn(
        label: label,
        color: color,
        dense: true,
        armed: controller.hoveredPlan == plan,
        previewOn: previewOn,
        onConfirm: () => controller.playCompound(plan),
        onHover: (h) => controller.setHoveredPlan(h ? plan : null),
      );
}

class _ActBtn extends StatelessWidget {
  const _ActBtn({
    required this.label,
    required this.color,
    required this.onConfirm,
    this.onHover,
    this.armed = false,
    this.previewOn = false,
    this.dense = false,
  });

  final String label;
  final Color color;
  final VoidCallback onConfirm;
  final ValueChanged<bool>? onHover;

  /// This action is currently previewed (hovered, or armed by a first tap).
  final bool armed;

  /// There's info to preview (a toggle is on), so the first tap arms instead of
  /// acting immediately.
  final bool previewOn;

  /// Compact sizing — used for the advanced (two-step) buttons, where up to six
  /// share the action bar.
  final bool dense;

  void _handleTap() {
    if (previewOn && !armed) {
      onHover?.call(true); // first tap: arm + reveal this action's info
    } else {
      onConfirm(); // second tap (or nothing to preview): commit
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: FilledButton(
        onPressed: _handleTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
              vertical: dense ? 6 : 12, horizontal: dense ? 4 : 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: armed
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
          ),
          textStyle:
              TextStyle(fontSize: dense ? 12 : 16, fontWeight: FontWeight.w800),
        ),
        child: armed
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: dense ? 11 : 14, height: 1.1),
                  ),
                  SizedBox(height: dense ? 1 : 2),
                  Text(
                    dense ? 'CONFIRM' : 'TAP TO CONFIRM',
                    style: TextStyle(
                      fontSize: dense ? 8 : 9,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}

class _FullButton extends StatelessWidget {
  const _FullButton(
      {required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onTap,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}

/// End-of-hand prompt: save the line you just played, or decline. The save
/// button *is* the line — your card followed by a row of colour-coded blocks,
/// one per action in play order (yours and the bot's). "Don't save line"
/// dismisses and deals the next hand.
class _SaveLinePrompt extends StatelessWidget {
  const _SaveLinePrompt({required this.controller, required this.onDecline});

  final HeadsUpController controller;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final card = controller.state.seats[HeadsUpController.humanSeat].card;
    // Saving deals the next hand too — no separate "Next Hand" step.
    void save() {
      controller.saveLine();
      controller.startHand();
    }

    final lines = controller.planLines;
    final lineWidget = lines.length > 1
        ? _MultiLineSave(
            card: card,
            lines: lines,
            botName: controller.profile.name,
            onTap: save,
          )
        : _LineButton(
            card: card,
            steps: controller.savableLine,
            botName: controller.profile.name,
            onTap: save,
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: lineWidget),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.feltLight,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Colors.white24),
              ),
            ),
            onPressed: onDecline,
            child: const Text(
              "Don't save line",
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontWeight: FontWeight.w800, height: 1.1),
            ),
          ),
        ),
      ],
    );
  }
}

/// The graphical "save this line" button: the player's card + a row of action
/// blocks (one per move this hand, in order). The whole thing is tappable.
class _LineButton extends StatelessWidget {
  const _LineButton({
    required this.card,
    required this.steps,
    required this.botName,
    required this.onTap,
  });

  final PlayingCard? card;
  final List<LineStep> steps;
  final String botName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.potPurpleDeep.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Row(
            children: [
              const Text('💾 ', style: TextStyle(fontSize: 16)),
              if (card != null) ...[
                PlayingCardWidget(card: card, faceUp: true, width: 32),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        if (i > 0)
                          const Icon(Icons.chevron_right,
                              size: 14, color: Colors.white54),
                        _ActionBlock(step: steps[i], botName: botName),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'SAVE\nLINE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.05,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The advanced-plan save button: the player's card plus the two branch lines
/// the plan covers, stacked — each tagged resolved (✓) or open ("?", the bot
/// could still re-raise). The whole thing saves both lines in one tap.
class _MultiLineSave extends StatelessWidget {
  const _MultiLineSave({
    required this.card,
    required this.lines,
    required this.botName,
    required this.onTap,
  });

  final PlayingCard? card;
  final List<PlanLine> lines;
  final String botName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.potPurpleDeep.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Row(
            children: [
              if (card != null) ...[
                PlayingCardWidget(card: card, faceUp: true, width: 30),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final line in lines) ...[
                      _BranchRow(line: line, botName: botName),
                      if (line != lines.last) const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '💾\nSAVE\nBOTH',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.15,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One branch line in the advanced save prompt: its action blocks, a "passive
/// bot" chip when the branch ends with the bot answering quietly, and a
/// resolved/open tag.
class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.line, required this.botName});

  final PlanLine line;
  final String botName;

  @override
  Widget build(BuildContext context) {
    // A single-step branch is the "bot answered passively → showdown" line.
    final passiveBranch = line.steps.length == 1;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < line.steps.length; i++) ...[
                  if (i > 0)
                    const Icon(Icons.chevron_right,
                        size: 13, color: Colors.white54),
                  _ActionBlock(step: line.steps[i], botName: botName),
                ],
                if (passiveBranch) ...[
                  const Icon(Icons.chevron_right,
                      size: 13, color: Colors.white54),
                  _PassiveChip(botName: botName),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _StatusTag(complete: line.complete),
      ],
    );
  }
}

/// A muted block standing in for "the bot just answers passively and we go to
/// showdown" — the tail of the first branch.
class _PassiveChip extends StatelessWidget {
  const _PassiveChip({required this.botName});

  final String botName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            botName.toUpperCase(),
            style: const TextStyle(
              fontSize: 7,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const Text(
            'PASSIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white70,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The resolved/open tag at the end of a branch line: a green ✓ when the line
/// is fully decided, an amber "?" when the bot could still re-raise it.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) {
    final color = complete ? AppColors.win : const Color(0xFFE08A2B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Icon(
        complete ? Icons.check_rounded : Icons.help_outline_rounded,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

/// One coloured block in the line strip: the action, tinted by its kind, tagged
/// with who made it (you / the bot).
class _ActionBlock extends StatelessWidget {
  const _ActionBlock({required this.step, required this.botName});

  final LineStep step;
  final String botName;

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(step.type);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: step.isHuman ? Colors.white : Colors.black38,
          width: step.isHuman ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            step.isHuman ? 'YOU' : botName.toUpperCase(),
            style: const TextStyle(
              fontSize: 7,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            _actionLabel(step.type),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

Color _actionColor(ActionType type) {
  switch (type) {
    case ActionType.bet:
      return AppColors.potPurple;
    case ActionType.call:
      return AppColors.chipGreen;
    case ActionType.check:
      return AppColors.chipBlue;
    case ActionType.fold:
      return AppColors.danger;
  }
}

String _actionLabel(ActionType type) {
  switch (type) {
    case ActionType.bet:
      return 'POT';
    case ActionType.call:
      return 'CALL';
    case ActionType.check:
      return 'CHECK';
    case ActionType.fold:
      return 'FOLD';
  }
}
