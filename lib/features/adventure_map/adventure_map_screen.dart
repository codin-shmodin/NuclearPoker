import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../identity/identity.dart';
import '../../theme/app_colors.dart';
import '../headsup_trainer/headsup_controller.dart';
import '../headsup_trainer/headsup_screen.dart';
import 'level.dart';
import 'line_store.dart';
import 'progress_store.dart';
import 'range_chart_screen.dart';

// ---- Desert palette (placeholder art) -------------------------------------
const Color _skyTop = Color(0xFFF6DCA6);
const Color _skyHorizon = Color(0xFFE7B36A);
const Color _sandBase = Color(0xFFD49A52);
const Color _duneLight = Color(0xFFEAC585);
const Color _duneMid = Color(0xFFCF9A52);
const Color _duneDark = Color(0xFFB57D3C);
const Color _sunColor = Color(0xFFF9E6A8);
const Color _trailBrown = Color(0xFF8A5A2B);

/// The Candy-Crush-style level map — the app's home screen. A scrolling path of
/// nodes, one per [LevelDef]; beating a level (busting its bot) unlocks the next.
/// Art is placeholder (gradient + dotted trail + gold badges); the layout
/// positions everything by normalized coordinates so real art slots into the
/// same frame later with no structural change. See docs/adventure-map.md.
class AdventureMapScreen extends StatefulWidget {
  const AdventureMapScreen({
    super.key,
    this.store,
    this.identity = const Identity('guest', ''),
    this.showIntro = false,
  });

  /// Injectable for tests; defaults to the on-device prefs store.
  final ProgressStore? store;

  /// Who's playing — keys per-user storage and grants admin (all levels +
  /// auto-play).
  final Identity identity;

  /// Show the one-time how-to-play intro once the map appears (set right after a
  /// fresh registration).
  final bool showIntro;

  @override
  State<AdventureMapScreen> createState() => _AdventureMapScreenState();
}

class _AdventureMapScreenState extends State<AdventureMapScreen> {
  late final ProgressStore _store =
      widget.store ?? SharedPrefsProgressStore(namespace: widget.identity.namespace);
  late final LineStore _lineStore =
      SharedPrefsLineStore(namespace: widget.identity.namespace);
  final ScrollController _scroll = ScrollController();

  /// Live trainer controllers per level. A level kept here after you leave it is
  /// auto-playing in the background (its map badge animates).
  final Map<int, HeadsUpController> _sessions = {};

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
    for (final c in _sessions.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Admin sees every level cleared (so all are unlocked + auto-play enabled).
    final progress = widget.identity.isAdmin
        ? LevelProgress({for (final l in kLevels) l.id})
        : await _store.load();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _loading = false;
    });
    if (widget.showIntro && !_introShown) {
      _introShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showIntroDialog();
      });
    }
  }

  bool _introShown = false;

  void _showIntroDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.feltDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('How it works',
            style: TextStyle(
                color: AppColors.goldBright, fontWeight: FontWeight.w900)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IntroPoint(
              icon: Icons.lock_open_rounded,
              text: 'Beat a level to unlock auto-play for that level.',
            ),
            SizedBox(height: 14),
            _IntroPoint(
              icon: Icons.bolt_rounded,
              text: 'Then play hands and hit Save line to teach your own bot. '
                  'Turn on Auto and it plays your saved line for you.',
            ),
            SizedBox(height: 14),
            _IntroPoint(
              icon: Icons.grid_view_rounded,
              text: 'See your saved ranges any time from the grid button '
                  'up top.',
            ),
            SizedBox(height: 14),
            _IntroPoint(
              icon: Icons.play_circle_outline,
              text: "Auto-play keeps running even when you're not seated at "
                  'the table — watch the level badge.',
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.goldDeep),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// Build (or reuse) the trainer controller for a level and load its line.
  HeadsUpController _makeController(LevelDef level, bool unlocked) {
    final c = HeadsUpController(
      profile: botProfileFor(level.botProfileId),
      startingStack: level.startingStack,
      autoPlayUnlocked: unlocked,
    );
    c.onLineChanged = () => _lineStore.save(level.id, c.savedLine);
    _lineStore.load(level.id).then((line) => c.setSavedLine(line));
    return c;
  }

  Future<void> _launchLevel(LevelDef level) async {
    final wasCompleted = _progress.isCompleted(level.id);
    // Resume a backgrounded session if one is already running here.
    final controller =
        _sessions[level.id] ??= _makeController(level, wasCompleted);
    setState(() {}); // node starts reflecting the session

    final won = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => HeadsUpScreen(
          profile: botProfileFor(level.botProfileId),
          startingStack: level.startingStack,
          levelTitle: botProfileFor(level.botProfileId).name,
          levelId: level.id,
          // Save-line + auto-play unlock once you've already cleared this level.
          autoPlayUnlocked: wasCompleted,
          lineStore: _lineStore,
          controller: controller,
        ),
      ),
    );
    if (!mounted) return;

    // Keep the session alive only if it's auto-playing in the background;
    // otherwise tear it down.
    if (!controller.autoPlayOn) {
      controller.dispose();
      _sessions.remove(level.id);
    }

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
        _rewardBurst = '🪙 +${level.coinReward}';
      });
    } else {
      setState(() {}); // refresh badges (a session may have started/stopped)
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
            colors: [_skyTop, _skyHorizon, _sandBase],
            stops: [0.0, 0.32, 1.0],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _trailBrown))
              : Stack(
                  children: [
                    _buildMap(),
                    // HUD is anchored to a top band — it must NOT fill the Stack,
                    // or it would swallow taps/scroll over the whole map.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _Hud(
                        completed: _progress.completedLevelIds.length,
                        total: kLevels.length,
                        coins: [
                          for (final l in kLevels)
                            if (_progress.isCompleted(l.id)) l.coinReward,
                        ].fold(0, (sum, c) => sum + c),
                        onRangeChart: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RangeChartScreen(lineStore: _lineStore),
                          ),
                        ),
                      ),
                    ),
                    if (_rewardBurst != null)
                      _rewardBurstOverlay(_rewardBurst!),
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
        // Taller than the screen so the path is a journey — scroll DOWN past
        // level 1 to see the later levels waiting, still locked.
        final h = (constraints.maxHeight * 1.8).clamp(820.0, double.infinity);
        return SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _DesertPainter()),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrailPainter(
                      [for (final l in kLevels) l.mapPosition],
                    ),
                  ),
                ),
                for (final level in kLevels) _positionedNode(level, Size(w, h)),
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
        session: _sessions[level.id],
        onTap: status == LevelStatus.locked ? null : () => _launchLevel(level),
      ),
    );
  }

  Widget _rewardBurstOverlay(String reward) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Text(
            reward,
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: AppColors.goldBright,
            ),
          )
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
              .moveY(
                  begin: 0, end: -160, duration: 600.ms, curve: Curves.easeIn)
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
    required this.coins,
    required this.onRangeChart,
  });

  final int completed;
  final int total;
  final int coins;
  final VoidCallback onRangeChart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _skyTop,
            _skyTop.withValues(alpha: 0.0),
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
                        color: AppColors.goldDeep,
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
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          _RewardTray(coins: coins),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Your ranges',
            onPressed: onRangeChart,
            icon: const Icon(Icons.grid_view_rounded,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The coin purse in the header: total coins earned across cleared levels.
class _RewardTray extends StatelessWidget {
  const _RewardTray({required this.coins});

  final int coins;

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
          const Text('🪙', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          Text(
            '$coins',
            style: const TextStyle(
              color: AppColors.goldBright,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
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
    required this.session,
    required this.onTap,
  });

  final LevelDef level;
  final LevelStatus status;
  final bool justUnlocked;

  /// The live controller if a session is running here (foreground or auto-play
  /// in the background); null otherwise. Drives the badge's play/pause overlay.
  final HeadsUpController? session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final node = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badgeWithIndicator(),
        const SizedBox(height: 6),
        _NameTag(
          name: botProfileFor(level.botProfileId).name,
          locked: status == LevelStatus.locked,
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
          .scaleXY(
              begin: 0.6, end: 1, duration: 500.ms, curve: Curves.easeOutBack)
          .shimmer(
              delay: 200.ms, duration: 900.ms, color: AppColors.goldBright);
    }
    return tappable;
  }

  /// The badge plus, when a session runs here, a corner indicator: a pulsing
  /// green dot while a hand is being played, or a paused tag when auto-play hit
  /// a spot it doesn't know.
  Widget _badgeWithIndicator() {
    final s = session;
    if (s == null) return _badge();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _badge(),
        Positioned(
          right: -6,
          top: -6,
          child: ListenableBuilder(
            listenable: s,
            builder: (_, __) => _AutoBadge(controller: s),
          ),
        ),
      ],
    );
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
          const Icon(Icons.check_circle, color: AppColors.win, size: 24),
          Text(
            '🪙${level.coinReward}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.goldBright,
            ),
          ),
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

/// The corner overlay on a level node whose trainer is running: a pulsing green
/// dot ("a hand is being played here") or an amber paused tag ("auto-play hit a
/// spot you haven't taught it — tap to decide").
class _AutoBadge extends StatelessWidget {
  const _AutoBadge({required this.controller});

  final HeadsUpController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.autoPaused) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE08A2B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: const Icon(Icons.pause, size: 13, color: Colors.white),
      );
    }
    if (controller.autoPlaying) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: AppColors.chipGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.7, end: 1.1, duration: 600.ms, curve: Curves.easeInOut)
          .fadeIn(duration: 300.ms);
    }
    return const SizedBox.shrink();
  }
}

/// One bullet in the how-to-play intro dialog: an icon + a line of text.
class _IntroPoint extends StatelessWidget {
  const _IntroPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.goldBright, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// A name label under a node, on a translucent pill so it stays readable over
/// the bright sand.
class _NameTag extends StatelessWidget {
  const _NameTag({required this.name, required this.locked});

  final String name;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A1A).withValues(alpha: locked ? 0.35 : 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: locked ? const Color(0xFFE7D6BE) : Colors.white,
        ),
      ),
    );
  }
}

/// A simple desert backdrop: a warm sun and layered dunes down the canvas.
/// Placeholder art — swapped for a real image later with no layout change.
class _DesertPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Sun, high on the right.
    canvas.drawCircle(
      Offset(size.width * 0.76, size.height * 0.07),
      size.width * 0.14,
      Paint()..color = _sunColor.withValues(alpha: 0.85),
    );

    // Stacked dune bands, alternating tones, each a gentle wave.
    const tones = [_duneLight, _duneMid, _duneDark, _duneMid, _duneLight];
    final amp = size.height * 0.035;
    for (var i = 0; i < tones.length; i++) {
      final baseY = size.height * (0.20 + i * 0.16);
      final paint = Paint()
        ..color = tones[i].withValues(alpha: 0.55)
        ..style = PaintingStyle.fill;
      final path = Path()..moveTo(0, baseY);
      const waves = 3;
      for (var x = 0; x < waves; x++) {
        final cx = size.width * ((x + 0.5) / waves);
        final cy = baseY + (x.isEven ? -amp : amp);
        final ex = size.width * ((x + 1) / waves);
        path.quadraticBezierTo(cx, cy, ex, baseY);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_DesertPainter oldDelegate) => false;
}

/// The dotted trail connecting the level nodes, drawn through their normalized
/// centers in id order. Baked into real background art later.
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
      ..color = _trailBrown.withValues(alpha: 0.55)
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
