import 'package:flutter/material.dart';

/// The four buyable hint features. Each maps to a toggle in the trainer's top
/// bar that only appears once the matching item is owned. The player starts with
/// none of them — the trainer is bare until you spend coins here.
enum ShopFeature { rangometer, evSupercomputer, doubleAction, autoPlay }

/// A single shop entry: a [ShopFeature], its price in coins, and the copy/icon
/// shown on its card. [id] is the stable string persisted in [ShopState].
class ShopItem {
  const ShopItem({
    required this.feature,
    required this.id,
    required this.name,
    required this.tagline,
    required this.price,
    required this.icon,
  });

  final ShopFeature feature;
  final String id;
  final String name;
  final String tagline;
  final int price;
  final IconData icon;
}

/// The catalog — the single source of truth for what's for sale and how much it
/// costs. Order is cheapest → priciest, which is also the display order.
const List<ShopItem> kShopItems = [
  ShopItem(
    feature: ShopFeature.rangometer,
    id: 'rangometer',
    name: 'Rangometer',
    tagline: "See the bot's live range as a colour-coded bar.",
    price: 2,
    icon: Icons.bar_chart_rounded,
  ),
  ShopItem(
    feature: ShopFeature.evSupercomputer,
    id: 'ev_supercomputer',
    name: 'EV Supercomputer',
    tagline: 'Exact chip EV for every action, every card.',
    price: 3,
    icon: Icons.calculate_rounded,
  ),
  ShopItem(
    feature: ShopFeature.doubleAction,
    id: 'double_action',
    name: 'Double Action',
    tagline: 'Plan two-step lines: check ▸ raise, raise ▸ call…',
    price: 4,
    icon: Icons.alt_route_rounded,
  ),
  ShopItem(
    feature: ShopFeature.autoPlay,
    id: 'auto_play',
    name: 'Auto Play',
    tagline: 'Bot plays your saved range — no need to beat a level first.',
    price: 6,
    icon: Icons.smart_toy_rounded,
  ),
];

/// The [ShopItem] for a [ShopFeature].
ShopItem shopItemFor(ShopFeature f) =>
    kShopItems.firstWhere((i) => i.feature == f);

/// How many free coins the "lazy Asaf" button hands out before it gives up and
/// rickrolls instead.
const int kAsafFreebies = 3;

/// The player's shop state: which items they own and how many "lazy Asaf" coins
/// they've claimed. Pure data (like `LevelProgress`) so it's unit-testable and
/// the backing store can swap to a server later. Owned items + grant count are
/// the only two facts persisted; the coin balance is *derived* from them plus
/// level rewards (see [coinBalance]), so there's no separate balance to keep in
/// sync and no way to double-spend.
class ShopState {
  const ShopState({this.ownedIds = const {}, this.asafGrants = 0});

  /// The [ShopItem.id]s the player has bought.
  final Set<String> ownedIds;

  /// How many coins the "lazy Asaf" button has granted (also the press counter:
  /// once it hits [kAsafFreebies] the button rickrolls instead of paying out).
  final int asafGrants;

  bool owns(String id) => ownedIds.contains(id);
  bool ownsFeature(ShopFeature f) => owns(shopItemFor(f).id);

  /// Whether the next "lazy Asaf" press still pays a coin (vs. rickrolling).
  bool get asafStillGiving => asafGrants < kAsafFreebies;

  ShopState withOwned(String id) =>
      ShopState(ownedIds: {...ownedIds, id}, asafGrants: asafGrants);

  ShopState withAsafGrant() =>
      ShopState(ownedIds: ownedIds, asafGrants: asafGrants + 1);

  /// Everything owned — used to grant the admin account the full toolkit.
  static ShopState get allOwned =>
      ShopState(ownedIds: {for (final i in kShopItems) i.id});
}

/// Coins spent on owned items. Admin gets everything for free, so nothing is
/// counted as spent for them.
int shopSpent(ShopState shop, {bool admin = false}) => admin
    ? 0
    : kShopItems
        .where((i) => shop.owns(i.id))
        .fold(0, (sum, i) => sum + i.price);

/// The spendable coin balance: coins earned by clearing levels, plus the "lazy
/// Asaf" freebies, minus what's been spent in the shop.
int coinBalance({
  required int levelCoins,
  required ShopState shop,
  bool admin = false,
}) =>
    levelCoins + shop.asafGrants - shopSpent(shop, admin: admin);
