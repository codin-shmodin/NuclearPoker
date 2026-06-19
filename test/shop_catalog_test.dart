import 'package:flutter_test/flutter_test.dart';
import 'package:nuclear_poker/features/shop/shop_catalog.dart';

void main() {
  test('starts owning nothing', () {
    const s = ShopState();
    expect(s.ownedIds, isEmpty);
    for (final f in ShopFeature.values) {
      expect(s.ownsFeature(f), isFalse);
    }
  });

  test('buying an item marks its feature owned and counts as spent', () {
    final ranger = shopItemFor(ShopFeature.rangometer);
    final s = const ShopState().withOwned(ranger.id);
    expect(s.ownsFeature(ShopFeature.rangometer), isTrue);
    expect(shopSpent(s), ranger.price);
  });

  test('balance = level coins + Asaf grants − spent', () {
    var s = const ShopState();
    // 5 from levels, nothing spent or granted.
    expect(coinBalance(levelCoins: 5, shop: s), 5);

    // Buy the rangometer (2): balance drops by 2.
    s = s.withOwned(shopItemFor(ShopFeature.rangometer).id);
    expect(coinBalance(levelCoins: 5, shop: s), 3);

    // An Asaf freebie adds 1.
    s = s.withAsafGrant();
    expect(coinBalance(levelCoins: 5, shop: s), 4);
  });

  test('admin owns everything for free (nothing counts as spent)', () {
    final s = ShopState.allOwned;
    for (final f in ShopFeature.values) {
      expect(s.ownsFeature(f), isTrue);
    }
    expect(shopSpent(s, admin: true), 0);
    expect(coinBalance(levelCoins: 0, shop: s, admin: true), 0);
  });

  test('lazy Asaf gives exactly kAsafFreebies coins, then stops', () {
    var s = const ShopState();
    for (var i = 0; i < kAsafFreebies; i++) {
      expect(s.asafStillGiving, isTrue, reason: 'grant ${i + 1} should pay');
      s = s.withAsafGrant();
    }
    // The (kAsafFreebies + 1)-th press no longer pays — it rickrolls instead.
    expect(s.asafStillGiving, isFalse);
    expect(s.asafGrants, kAsafFreebies);
  });
}
