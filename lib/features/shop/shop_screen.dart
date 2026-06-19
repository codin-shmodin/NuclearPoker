import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import 'shop_catalog.dart';
import 'shop_store.dart';

/// The shop: spend coins to unlock the trainer's hint features. Each purchase
/// adds a toggle to the trainer's top bar on *every* level. The player starts
/// owning nothing — this is the only way to turn the hints on.
///
/// Owned items + coins-granted are persisted via [store]; every mutation is also
/// pushed up through [onChanged] so the map can refresh its coin purse and
/// re-arm any live trainer sessions.
class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    required this.store,
    required this.initial,
    required this.levelCoins,
    required this.onChanged,
    this.isAdmin = false,
  });

  final ShopStore store;

  /// The shop state as the map currently knows it.
  final ShopState initial;

  /// Coins earned by clearing levels — fixed for the life of this screen; the
  /// balance is this plus Asaf grants minus what's spent here.
  final int levelCoins;

  /// Admin owns everything for free.
  final bool isAdmin;

  /// Called after every purchase or coin grant so the map stays in sync.
  final ValueChanged<ShopState> onChanged;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  /// Rick Astley — "Never Gonna Give You Up".
  static final Uri _rickroll =
      Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

  late ShopState _shop = widget.initial;

  int get _balance =>
      coinBalance(levelCoins: widget.levelCoins, shop: _shop, admin: widget.isAdmin);

  void _commit(ShopState next) {
    setState(() => _shop = next);
    widget.onChanged(next);
  }

  Future<void> _buy(ShopItem item) async {
    if (widget.isAdmin || _shop.owns(item.id) || _balance < item.price) return;
    await widget.store.markOwned(item.id);
    _commit(_shop.withOwned(item.id));
    if (mounted) _toast('Unlocked ${item.name}! Toggle it on at the table.');
  }

  Future<void> _lazyAsaf() async {
    if (_shop.asafStillGiving) {
      await widget.store.recordAsafGrant();
      _commit(_shop.withAsafGrant());
      if (mounted) _toast('🪙 Fine, here\'s a coin. Don\'t spend it all at once.');
      return;
    }
    // Out of freebies — you know what happens next.
    await launchUrl(_rickroll, mode: LaunchMode.externalApplication);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.feltDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ));
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
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final item in kShopItems) ...[
                      _ShopCard(
                        item: item,
                        owned: widget.isAdmin || _shop.owns(item.id),
                        affordable: _balance >= item.price,
                        onBuy: () => _buy(item),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 8),
                    _LazyAsafButton(
                      stillGiving: _shop.asafStillGiving,
                      onTap: _lazyAsaf,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Text('🛒', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          const Text(
            'Shop',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          _CoinPill(coins: _balance),
        ],
      ),
    );
  }
}

/// The coin purse, mirroring the map's reward tray.
class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 5),
          Text(
            '$coins',
            style: const TextStyle(
              color: AppColors.goldBright,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// One purchasable feature: icon, name, tagline, and a price/Buy/Owned trailing
/// control. Greys out and disables when you can't afford it.
class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.item,
    required this.owned,
    required this.affordable,
    required this.onBuy,
  });

  final ShopItem item;
  final bool owned;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final dim = !owned && !affordable;
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.feltLight, AppColors.feltDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: owned
                ? AppColors.win.withValues(alpha: 0.7)
                : AppColors.gold.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: Icon(item.icon, color: AppColors.goldBright, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.tagline,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _trailing(),
          ],
        ),
      ),
    );
  }

  Widget _trailing() {
    if (owned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.win.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.win.withValues(alpha: 0.7)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 16, color: AppColors.win),
            SizedBox(width: 4),
            Text('OWNED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: AppColors.win,
                )),
          ],
        ),
      );
    }
    return FilledButton(
      onPressed: affordable ? onBuy : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.goldDeep,
        disabledBackgroundColor: AppColors.background.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 4),
          Text('${item.price}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              )),
        ],
      ),
    );
  }
}

/// The cheeky beta button: hands out three free coins, then rickrolls forever.
class _LazyAsafButton extends StatelessWidget {
  const _LazyAsafButton({required this.stillGiving, required this.onTap});

  final bool stillGiving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.feltDark.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.35),
                style: BorderStyle.solid),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  "I'm lazy Asaf please can i have a coin?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: 8),
              // Two fingers pointing toward each other — the shy "please?" meme.
              Text('👉👈', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
          delay: 1200.ms,
          duration: 1400.ms,
          color: AppColors.goldBright.withValues(alpha: 0.25),
        );
  }
}
