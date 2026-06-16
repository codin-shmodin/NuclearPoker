import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../engine/game/rule_config.dart';
import '../../engine/game/seat.dart';
import '../../theme/app_colors.dart';
import 'quest_controller.dart';
import 'widgets/action_bar.dart';
import 'widgets/chip_stack_widget.dart';
import 'widgets/pot_widget.dart';
import 'widgets/seat_widget.dart';

/// Quest 1 main screen: the poker table, the seats, and the human controls.
class OneCardTableScreen extends StatefulWidget {
  const OneCardTableScreen({super.key, this.opponentCount = 5});

  final int opponentCount;

  /// Level 1 rules: 30 chips, no ante, 1/1 blinds, pot-sized bets/raises.
  static const RuleConfig levelOneRules = RuleConfig(
    startingStack: 30,
    smallBlind: 1,
    bigBlind: 1,
    maxPlayers: 6,
  );

  @override
  State<OneCardTableScreen> createState() => _OneCardTableScreenState();
}

class _OneCardTableScreenState extends State<OneCardTableScreen> {
  late final QuestController controller;

  @override
  void initState() {
    super.initState();
    controller = QuestController(
      rules: OneCardTableScreen.levelOneRules,
      opponentCount: widget.opponentCount,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Explicit fan for a full 6-handed table — every seat gets a distinct x so
  /// the side seats never line up / overlap.
  static const List<Alignment> _sixSeatLayout = [
    Alignment(0.0, 0.94), // 0 hero (bottom)
    Alignment(1.0, 0.36), // 1 lower-right
    Alignment(0.66, -0.64), // 2 upper-right
    Alignment(0.0, -0.88), // 3 top
    Alignment(-0.66, -0.64), // 4 upper-left
    Alignment(-1.0, 0.36), // 5 lower-left
  ];

  Alignment _seatAlignment(int seatIndex, int n) {
    final relative = (seatIndex - controller.humanSeat + n) % n;
    if (n == 6) return _sixSeatLayout[relative];
    final theta = 2 * pi * relative / n; // 0 → bottom (the human)
    return Alignment(sin(theta) * 0.94, cos(theta) * 0.82);
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
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Column(
                children: [
                  _TopBar(controller: controller),
                  Expanded(child: _buildTable(context)),
                  _BottomPanel(controller: controller),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Position of the dealer button: near the dealer's seat, nudged sideways so
  /// it sits clearly on the felt rather than on top of their chips.
  Alignment _dealerButtonAlignment(int n) {
    final a = _seatAlignment(controller.state.button, n);
    final len = sqrt(a.x * a.x + a.y * a.y);
    final perpX = len == 0 ? 0.0 : -a.y / len;
    final perpY = len == 0 ? 0.0 : a.x / len;
    return Alignment(a.x * 0.70 + perpX * 0.22, a.y * 0.70 + perpY * 0.22);
  }

  Widget _buildTable(BuildContext context) {
    final state = controller.state;
    final n = state.seats.length;
    final revealAll = controller.handOver;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The felt.
          const _Felt(),

          // Centre: pot with the status line directly beneath it.
          Align(
            alignment: const Alignment(0, -0.1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PotWidget(amount: state.pot),
                const SizedBox(height: 8),
                _StatusChip(text: controller.statusMessage),
              ],
            ),
          ),

          // Per-seat committed chips, between each seat and the pot (animated).
          if (!controller.handOver)
            for (final Seat seat in state.seats)
              if (seat.committed > 0)
                Align(
                  alignment: Alignment(
                    _seatAlignment(seat.index, n).x * 0.62,
                    _seatAlignment(seat.index, n).y * 0.62,
                  ),
                  child: _BetChips(
                    seatIndex: seat.index,
                    amount: seat.committed,
                    from: _seatAlignment(seat.index, n),
                  ),
                ),

          // Seats around the rail.
          for (final Seat seat in state.seats)
            Align(
              alignment: _seatAlignment(seat.index, n),
              child: SeatWidget(
                seat: seat,
                isActive: state.toAct == seat.index && !controller.handOver,
                blind: seat.index == state.smallBlindSeat
                    ? 'SB'
                    : seat.index == state.bigBlindSeat
                        ? 'BB'
                        : null,
                cardAbove: _seatAlignment(seat.index, n).y < 0,
                revealCard: seat.isHuman || revealAll,
                isWinner: controller.handOver &&
                    state.winners.contains(seat.index),
              ),
            ),

          // The dealer button — a chip on the felt that slides to the new
          // dealer each hand.
          AnimatedAlign(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            alignment: _dealerButtonAlignment(n),
            child: const _DealerButton(),
          ),
        ],
      ),
    );
  }
}

class _DealerButton extends StatelessWidget {
  const _DealerButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Colors.white, Color(0xFFE9E2CF)],
        ),
        border: Border.all(color: AppColors.goldDeep, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Text(
        'D',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          color: AppColors.cardBlack,
          height: 1,
        ),
      ),
    );
  }
}

/// A seat's chips committed this round, shown between the seat and the pot.
/// Re-animates (slides in from the seat + pops) whenever the amount changes —
/// so blinds, bets and calls each get a chip animation.
class _BetChips extends StatelessWidget {
  const _BetChips({
    required this.seatIndex,
    required this.amount,
    required this.from,
  });

  final int seatIndex;
  final int amount;
  final Alignment from;

  @override
  Widget build(BuildContext context) {
    return ChipStackWidget(amount: amount)
        .animate(key: ValueKey('bet_${seatIndex}_$amount'))
        .fadeIn(duration: 180.ms)
        .scaleXY(begin: 0.4, end: 1, duration: 260.ms, curve: Curves.easeOutBack)
        .move(
          begin: Offset(from.x * 24, from.y * 24),
          duration: 260.ms,
          curve: Curves.easeOut,
        );
  }
}

class _Felt extends StatelessWidget {
  const _Felt();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(180),
        gradient: const RadialGradient(
          radius: 0.9,
          colors: [AppColors.feltCenter, AppColors.feltEdge],
        ),
        border: Border.all(color: AppColors.feltRail, width: 10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final QuestController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Text(
            'One Card Poker',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Text('💰 ', style: TextStyle(fontSize: 14)),
                Text(
                  '${controller.seats[controller.humanSeat].stack}',
                  style: const TextStyle(
                    color: AppColors.goldBright,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ).animate(key: ValueKey(text)).fadeIn(duration: 200.ms);
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.controller});

  final QuestController controller;

  @override
  Widget build(BuildContext context) {
    final view = controller.humanView;
    final showActions = controller.isHumanTurn && view != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SizedBox(
        height: 64,
        child: () {
          if (controller.handOver) {
            return _HandOverControls(controller: controller);
          }
          if (showActions) {
            return ActionBar(
              view: view,
              onFold: controller.fold,
              onCheck: controller.check,
              onCall: controller.call,
              onBet: controller.bet,
            );
          }
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
        }(),
      ),
    );
  }
}

class _HandOverControls extends StatelessWidget {
  const _HandOverControls({required this.controller});

  final QuestController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.humanBusted) {
      return _FullWidthButton(
        label: 'Out of chips — Reset',
        color: AppColors.danger,
        onTap: controller.resetSession,
      );
    }
    if (controller.tableCleared) {
      return _FullWidthButton(
        label: '🏆 You cleared the table! — Play again',
        color: AppColors.goldDeep,
        onTap: controller.resetSession,
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.feltLight,
            ),
            onPressed: controller.startHand,
            child: const Text('Next Hand'),
          ),
        ),
      ],
    );
  }
}

class _FullWidthButton extends StatelessWidget {
  const _FullWidthButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: onTap,
            child: Text(label),
          ),
        ),
      ],
    );
  }
}
