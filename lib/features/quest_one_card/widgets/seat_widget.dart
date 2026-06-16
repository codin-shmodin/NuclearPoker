import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../engine/game/seat.dart';
import '../../../theme/app_colors.dart';
import 'playing_card_widget.dart';

/// A player position at the table: avatar, name, stack, their card and last
/// action. Highlights when it's their turn and glows when they win.
class SeatWidget extends StatelessWidget {
  const SeatWidget({
    super.key,
    required this.seat,
    required this.isActive,
    required this.blind,
    required this.revealCard,
    required this.isWinner,
    this.cardAbove = false,
  });

  final Seat seat;
  final bool isActive;

  /// 'SB' / 'BB' badge, or null.
  final String? blind;

  /// Whether this seat's card should be shown face-up (always for the human;
  /// at showdown for opponents that didn't fold).
  final bool revealCard;
  final bool isWinner;

  /// For opponents: place the card above the avatar (used for top-half seats so
  /// the card points away from the pot).
  final bool cardAbove;

  @override
  Widget build(BuildContext context) {
    final isOut = seat.card == null; // sitting out (no chips)
    final dimmed = seat.folded;
    final avatar = Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(
            seat: seat,
            isActive: isActive,
            isWinner: isWinner,
          ),
          const SizedBox(height: 6),
          _NamePlate(seat: seat),
          if (blind != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _RoleBadge(label: blind!),
            ),
          if (seat.lastAction != null && !seat.folded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ActionBubble(text: seat.lastAction!.toString()),
            ),
          if (isOut)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _ActionBubble(text: 'Sitting out', muted: true),
            )
          else if (seat.folded)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _ActionBubble(text: 'Folded', muted: true),
            ),
        ],
      ),
    );

    // Sitting-out seats show no card at all.
    final Widget card = isOut
        ? const SizedBox.shrink()
        : PlayingCardWidget(
            card: seat.card,
            faceUp: revealCard && !seat.folded,
            width: seat.isHuman ? 56 : 42,
            highlight: isWinner,
          );

    // Hero: card beside the avatar (short, so it doesn't reach the centre).
    // Opponents: card on the outside of the table (above for top-half seats,
    // below for bottom-half) so it never covers the pot.
    final content = seat.isHuman
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [card, const SizedBox(width: 10), avatar],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: cardAbove
                ? [card, const SizedBox(height: 8), avatar]
                : [avatar, const SizedBox(height: 8), card],
          );

    if (isWinner) {
      return content.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(
            begin: 1,
            end: 1.06,
            duration: 600.ms,
            curve: Curves.easeInOut,
          );
    }
    return content;
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.seat,
    required this.isActive,
    required this.isWinner,
  });

  final Seat seat;
  final bool isActive;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final ringColor = isWinner
        ? AppColors.win
        : isActive
            ? AppColors.goldBright
            : Colors.white24;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.feltLight, AppColors.feltEdge],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: ringColor, width: isActive || isWinner ? 3 : 1.5),
        boxShadow: isActive
            ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.6), blurRadius: 14)]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        seat.isHuman ? '🙂' : '🤖',
        style: const TextStyle(fontSize: 24),
      ),
    );
  }
}

class _NamePlate extends StatelessWidget {
  const _NamePlate({required this.seat});

  final Seat seat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            seat.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '${seat.stack}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.goldBright,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.chipBlue.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.chipBlue.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ActionBubble extends StatelessWidget {
  const _ActionBubble({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.danger.withValues(alpha: 0.18)
            : AppColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: muted ? AppColors.danger : AppColors.goldBright,
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).scaleXY(begin: 0.8, end: 1);
  }
}
