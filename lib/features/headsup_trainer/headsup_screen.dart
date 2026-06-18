import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../engine/game/action.dart';
import '../../engine/game/hand_state.dart';
import '../../engine/game/seat.dart';
import '../../engine/players/bot_profile.dart';
import '../../theme/app_colors.dart';
import '../quest_one_card/widgets/chip_stack_widget.dart';
import '../quest_one_card/widgets/playing_card_widget.dart';
import 'headsup_controller.dart';
import 'widgets/ev_bar.dart';
import 'widgets/range_bar.dart';

/// Heads-up trainer: defend your big blind against a transparent range bot.
class HeadsUpScreen extends StatefulWidget {
  const HeadsUpScreen({super.key, required this.profile});

  final BotProfile profile;

  @override
  State<HeadsUpScreen> createState() => _HeadsUpScreenState();
}

class _HeadsUpScreenState extends State<HeadsUpScreen> {
  late final HeadsUpController controller;

  @override
  void initState() {
    super.initState();
    controller = HeadsUpController(profile: widget.profile);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is KeyDownEvent && isEnter && controller.handOver) {
      controller.sessionOver ? controller.resetSession() : controller.startHand();
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
                    _TopBar(controller: controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _Table(controller: controller)),
                            const SizedBox(width: 8),
                            RangeBar(
                              title: controller.rangeTitle,
                              cells: controller.rangeCells,
                            ),
                            if (controller.hintOn) ...[
                              const SizedBox(width: 8),
                              EvBar(
                                title: _evTitle(controller.hoveredAction),
                                cells: controller.hoveredAction == null
                                    ? const []
                                    : controller
                                        .evCellsForAction(controller.hoveredAction!),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _BottomPanel(controller: controller, state: state),
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
              isActive: state.toAct == HeadsUpController.botSeat && !controller.handOver,
              isWinner: controller.handOver && state.winners.contains(HeadsUpController.botSeat),
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
              isWinner: controller.handOver && state.winners.contains(HeadsUpController.humanSeat),
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
        gradient: const RadialGradient(colors: [Colors.white, Color(0xFFE9E2CF)]),
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
        PlayingCardWidget(card: seat.card, faceUp: faceUp, width: 50, highlight: isWinner),
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
            border: Border.all(color: ring, width: isActive || isWinner ? 3 : 1.5),
          ),
          child: Text(seat.isHuman ? '🙂' : '🤖', style: const TextStyle(fontSize: 22)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.chipBlue.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.chipBlue.withValues(alpha: 0.7)),
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
        if (seat.committed > 0 && !seat.folded) ChipStackWidget(amount: seat.committed),
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
    ).animate(key: ValueKey('${action.type}_${action.amount}')).fadeIn(duration: 200.ms).scaleXY(begin: 0.7, end: 1);
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
    ).animate(key: ValueKey(text)).fadeIn(duration: 250.ms).slideY(begin: -0.15);
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
  const _TopBar({required this.controller});

  final HeadsUpController controller;

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
          const Text(
            'Heads-Up Trainer',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          const Text(
            '💡 Hint',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Switch(
            value: controller.hintOn,
            activeColor: AppColors.potPurple,
            onChanged: controller.toggleHint,
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.controller, required this.state});

  final HeadsUpController controller;
  final HandState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      height: 78,
      child: controller.handOver ? _endControls() : _actionControls(),
    );
  }

  Widget _endControls() {
    if (controller.sessionOver) {
      final won = controller.botBusted;
      return _FullButton(
        label: won ? '🏆 You busted Dex! — Play again' : 'Out of chips — Reset',
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

  Widget _actionControls() {
    final view = controller.humanView;
    if (!controller.isHumanTurn || view == null) {
      return Center(
        child: Text(
          controller.statusMessage,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final buttons = <Widget>[
      if (view.toCall > 0)
        _ActBtn(
          label: 'Fold',
          color: AppColors.danger,
          onTap: controller.fold,
          onHover: (h) => controller.setHoveredAction(h ? ActionType.fold : null),
        ),
      if (view.canCheck)
        _ActBtn(
          label: 'Check',
          color: AppColors.chipBlue,
          onTap: controller.check,
          onHover: (h) => controller.setHoveredAction(h ? ActionType.check : null),
        ),
      if (view.canCall)
        _ActBtn(
          label: 'Call ${view.toCall}',
          color: AppColors.chipGreen,
          onTap: controller.call,
          onHover: (h) => controller.setHoveredAction(h ? ActionType.call : null),
        ),
      if (view.canBet)
        _ActBtn(
          label: 'Pot ${view.raiseTarget}',
          color: AppColors.potPurpleDeep,
          onTap: controller.pot,
          onHover: (h) => controller.setHoveredAction(h ? ActionType.bet : null),
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

class _ActBtn extends StatelessWidget {
  const _ActBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.onHover,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

class _FullButton extends StatelessWidget {
  const _FullButton({required this.label, required this.color, required this.onTap});

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onTap,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}
