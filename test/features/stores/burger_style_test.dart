import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StoreLocation store(String id, String burgerStyle) {
    return StoreLocation(
      id: id,
      name: 'Store $id',
      address: 'Seoul test address $id',
      latitude: 37.53,
      longitude: 126.99,
      burgerStyle: burgerStyle,
    );
  }

  test('parses every internal code', () {
    for (final style in BurgerStyle.values) {
      expect(BurgerStyle.parse(style.code), style);
    }
  });

  test('parses Korean display values and safe legacy aliases', () {
    expect(BurgerStyle.parse('클래식'), BurgerStyle.classic);
    expect(BurgerStyle.parse('스매시'), BurgerStyle.smash);
    expect(BurgerStyle.parse('치킨'), BurgerStyle.chicken);
    expect(BurgerStyle.parse('비건·식물성'), BurgerStyle.plantBased);
    expect(BurgerStyle.parse('기타'), BurgerStyle.other);
    expect(BurgerStyle.parse('미분류'), BurgerStyle.unclassified);
    expect(BurgerStyle.parse('스매시 버거'), BurgerStyle.smash);
    expect(BurgerStyle.parse('치킨버거'), BurgerStyle.chicken);
  });

  test('normalizes surrounding spaces, repeated spaces, and letter case', () {
    expect(BurgerStyle.parse('  SMASH  '), BurgerStyle.smash);
    expect(BurgerStyle.parse('  스매시   버거  '), BurgerStyle.smash);
    expect(BurgerStyle.parse(' Plant_Based '), BurgerStyle.plantBased);
  });

  test('maps empty and unknown values to unclassified', () {
    expect(BurgerStyle.parse(''), BurgerStyle.unclassified);
    expect(BurgerStyle.parse('   '), BurgerStyle.unclassified);
    expect(BurgerStyle.parse(null), BurgerStyle.unclassified);
    expect(BurgerStyle.parse('unsupported-style'), BurgerStyle.unclassified);
  });

  test('provides user labels without exposing internal codes', () {
    expect(BurgerStyle.classic.displayLabel, '클래식');
    expect(BurgerStyle.smash.displayLabel, '스매시');
    expect(BurgerStyle.chicken.displayLabel, '치킨');
    expect(BurgerStyle.plantBased.displayLabel, '비건·식물성');
    expect(BurgerStyle.other.displayLabel, '기타');
    expect(BurgerStyle.unclassified.displayLabel, '미분류');
    expect(BurgerStyle.unclassified.detailLabel, '아직 분류되지 않았습니다.');
  });

  test('available styles are deduplicated in taxonomy order', () {
    final styles = availableBurgerStyles([
      store('1', '미분류'),
      store('2', 'SMASH'),
      store('3', 'classic'),
      store('4', '스매시'),
      store('5', 'unknown'),
    ]);

    expect(styles, [
      BurgerStyle.classic,
      BurgerStyle.smash,
      BurgerStyle.unclassified,
    ]);
  });

  test('invalid selection safely falls back to all after data reload', () {
    final stores = [store('1', 'classic')];

    expect(
      validBurgerStyleSelection(BurgerStyle.classic, stores),
      BurgerStyle.classic,
    );
    expect(validBurgerStyleSelection(BurgerStyle.smash, stores), isNull);
    expect(validBurgerStyleSelection(null, stores), isNull);
  });
}
