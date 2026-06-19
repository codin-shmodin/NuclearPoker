import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_colors.dart';
import '../headsup_trainer/bot_picker_screen.dart';
import '../headsup_trainer/headsup_screen.dart';
import 'level.dart';
import 'line_store.dart';
import 'progress_store.dart';

/// The Candy-Crush-style level map — the app's home screen. A scrolling path of
/// nodes, one per [LevelDef]; beating a level (busting its bot) unlocks the next.
/// Art is placeholder (gradient + dotted trail + gold badges); the layout
/// positions everything by normalized coordinates so real art slots into the
/// same frame later with no structural change. See docs/adventure-map.md.
class AdventureMapScreen extends StatefulWidget {
  const AdventureMapScreen({super.key, this.store});

  /// Injectable for tests; defaults to the on-device prefs store.
  final ProgressStore? store;

  @override
  State<AdventureMapScreen> createState() => _AdventureMapScreenState();
}

class _AdventureMapScreenState extends State<AdventureMapScreen> {
  late final ProgressStore _store = widget.store ?? SharedPrefsProgressStore();
  final LineStore _lineStore = SharedPrefsLineStore();
  final ScrollController _scroll = ScrollController();

  LevelProgress _progress = const LevelProgress.empty();
  bool _loading = true;

  /// A level that just flipped locked→unlocked, to pop+glow once.
  int? _justUnlockedId;

  /// A reward burst to play over the map after a first clear.
  String? _rewardBurst;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final progress = await _store.load();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _loading = false;
    });
    // Start the view at the bottom — the journey begins at level 1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _launchLevel(LevelDef level) async {
    final wasCompleted = _progress.isCompleted(level.id);
    final won = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => HeadsUpScreen(
          profile: botProfileFor(level.botProfileId),
          startingStack: level.startingStack,
          levelTitle: level.title,
          levelId: level.id,
          // Save-line + auto-play unlock once you've already cleared this level.
          autoPlayUnlocked: wasCompleted,
          lineStore: _lineStore,
        ),
      ),
    );
    if (!mounted) return;
    // Reward + unlock only fire on the *first* clear (replays are rewardless).
    if (won == true && !wasCompleted) {
      await _store.markComplete(level.id);
      final updated = await _store.load();
      if (!mounted) return;
      final nextId = level.id + 1;
      final hasNext = kLevels.any((l) => l.id == nextId);
      setState(() {
        _progress = updated;
        _justUnlockedId = hasNext ? nextId : null;
        _rewardBurst = level.rewardId;
      });
    }
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
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold))
              : Stack(
                  children: [
                    _buildMap(),
                    _Hud(
                      completed: _progress.completedLevelIds.length,
                      total: kLevels.length,
                      rewards: [
                        for (final l in kLevels)
                          if (_progress.isCompleted(l.id)) l.rewardId,
                      ],
                      onPractice: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BotPickerScreen(),
                        ),
                      ),
                    ),
                    if (_rewardBurst != null) _rewardBurstOverlay(_rewardBurst!),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Taller than the screen so the path feels like a journey to scroll up.
        final h = (constraints.maxHeight * 1.9).clamp(720.0, double.infinity);
        return SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrailPainter(
                      [for (final l in kLevels) l.mapPosition],
                    ),
                  ),
                ),
                for (final level in kLevels)
                  _positionedNode(level, Size(w, h)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positionedNode(LevelDef level, Size map) {
    const nodeW = 132.0;
    final cx = level.mapPosition.dx * map.width;
    final cy = level.mapPosition.dy * map.height;
    final status = _progress.statusOf(level.id);
    return Positioned(
      left: cx - nodeW / 2,
      top: cy - 44,
      width: nodeW,
      child: _LevelNode(
        level: level,
        status: status,
        justUnlocked: _justUnlockedId == level.id,
        onTap: status == LevelStatus.locked ? null : () => _launchLevel(level),
      ),
    );
  }

  Widget _rewardBurstOverlay(String reward) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Text(reward, style: const TextStyle(fontSize: 96))
              .animate(
                onComplete: (_) {
                  if (mounted) setState(() => _rewardBurst = null);
                },
              )
              .scale(
                begin: const Offset(0.2, 0.2),
                end: const Offset(1.3, 1.3),
                duration: 500.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 200.ms)
              .then(delay: 350.ms)
              .moveY(begin: 0, end: -160, duration: 600.ms, curve: Curves.easeIn)
              .fadeOut(duration: 600.ms),
        ),
      ),
    );
  }
}

/// Pinned header: title, progress, and the reward tray. Does not scroll.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.completed,
    required this.total,
    required this.rewards,
    required this.onPractice,
  });

  final int completed;
  final int total;
  final List<String> rewards;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundTop,
              AppColors.backgroundTop.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('☢️', style: TextStyle(fontSize: 26)),
                      SizedBox(width: 8),
                      Text(
                        'NUCLEAR',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: AppColors.goldBright,
                        ),
                      ),
                      Text(
                        'POKER',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Climb the ladder · $completed / $total cleared',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            _RewardTray(rewards: rewards),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Free play',
              onPressed: onPractice,
              icon: const Icon(Icons.sports_esports,
                  color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardTray extends StatelessWidget {
  const _RewardTray({required this.rewards});

  final List<String> rewards;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rewards.isEmpty)
            const Text('—',
                style: TextStyle(color: AppColors.textMuted, fontSize: 16))
          else
            for (final r in rewards) ...[
              Text(r, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 2),
            ],
        ],
      ),
    );
  }
}

/// A single tappable level node. Three looks: locked (dimmed + padlock),
/// unlocked (gold glow + play), completed (green check + reward).
class _LevelNode extends StatelessWidget {
  const _LevelNode({
    required this.level,
    required this.status,
    required this.justUnlocked,
    required this.onTap,
  });

  final LevelDef level;
  final LevelStatus status;
  final bool justUnlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final node = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(),
        const SizedBox(height: 6),
        Text(
          level.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: status == LevelStatus.locked
                ? AppColors.textMuted
                : AppColors.textPrimary,
          ),
        ),
      ],
    );

    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(44),
        onTap: onTap,
        child: node,
      ),
    );

    if (justUnlocked) {
      return tappable
          .animate()
          .scaleXY(begin: 0.6, end: 1, duration: 500.ms, curve: Curves.easeOutBack)
          .shimmer(delay: 200.ms, duration: 900.ms, color: AppColors.goldBright);
    }
    return tappable;
  }

  Widget _badge() {
    final locked = status == LevelStatus.locked;
    final completed = status == LevelStatus.completed;
    final borderColor = locked
        ? AppColors.textMuted
        : completed
            ? AppColors.win
            : AppColors.gold;
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.feltLight, AppColors.feltDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: locked
            ? null
            : [
                BoxShadow(
                  color: (completed ? AppColors.win : AppColors.gold)
                      .withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: _badgeContent(locked, completed),
      ),
    );
  }

  Widget _badgeContent(bool locked, bool completed) {
    if (locked) {
      return const Icon(Icons.lock, color: AppColors.textMuted, size: 28);
    }
    if (completed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.win, size: 26),
          Text(level.rewardId, style: const TextStyle(fontSize: 16)),
        ],
      );
    }
    // Unlocked, not yet cleared.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${level.id}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.goldBright,
            height: 1,
          ),
        ),
        const Icon(Icons.play_arrow_rounded,
            color: AppColors.goldBright, size: 20),
      ],
    );
  }
}

/// The dotted gold trail connecting the level nodes, drawn through their
/// normalized centers in id order. Baked into real background art later.
class _TrailPainter extends CustomPainter {
  _TrailPainter(this.normalizedPoints);

  final List<Offset> normalizedPoints;

  @override
  void paint(Canvas canvas, Size size) {
    if (normalizedPoints.length < 2) return;
    final pts = [
      for (final p in normalizedPoints)
        Offset(p.dx * size.width, p.dy * size.height),
    ];

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, mid.dy, mid.dx, mid.dy);
      path.quadraticBezierTo(b.dx, mid.dy, b.dx, b.dy);
    }

    final dot = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final tan = metric.getTangentForOffset(d);
        if (tan != null) canvas.drawCircle(tan.position, 3.2, dot);
        d += 18;
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) =>
      oldDelegate.normalizedPoints != normalizedPoints;
}
