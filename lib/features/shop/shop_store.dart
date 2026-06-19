import 'package:shared_preferences/shared_preferences.dart';

import 'shop_catalog.dart';

/// Persists [ShopState]. A thin interface mirroring `ProgressStore` so the
/// backing store can swap from on-device prefs to Firebase later without
/// touching the shop UI.
abstract class ShopStore {
  Future<ShopState> load();

  /// Record that [itemId] has been bought. Idempotent.
  Future<void> markOwned(String itemId);

  /// Record one "lazy Asaf" coin grant (bumps the counter that eventually
  /// trips the rickroll).
  Future<void> recordAsafGrant();
}

/// The PoC store: owned ids + the Asaf grant count in `shared_preferences`,
/// keyed per-user via [namespace].
class SharedPrefsShopStore implements ShopStore {
  SharedPrefsShopStore({this.namespace = ''});

  /// Per-user key prefix, so each account's purchases are separate.
  final String namespace;

  String get _ownedKey => '${namespace}shop_owned_ids';
  String get _grantsKey => '${namespace}shop_asaf_grants';

  @override
  Future<ShopState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final owned = (prefs.getStringList(_ownedKey) ?? const <String>[]).toSet();
    final grants = prefs.getInt(_grantsKey) ?? 0;
    return ShopState(ownedIds: owned, asafGrants: grants);
  }

  @override
  Future<void> markOwned(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_ownedKey) ?? const <String>[]).toSet()
      ..add(itemId);
    await prefs.setStringList(_ownedKey, ids.toList());
  }

  @override
  Future<void> recordAsafGrant() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(_grantsKey) ?? 0) + 1;
    await prefs.setInt(_grantsKey, n);
  }
}
