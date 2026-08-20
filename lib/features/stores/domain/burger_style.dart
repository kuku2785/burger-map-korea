import 'store_location.dart';

enum BurgerStyle {
  classic(code: 'classic', displayLabel: '클래식'),
  smash(code: 'smash', displayLabel: '스매시'),
  chicken(code: 'chicken', displayLabel: '치킨'),
  plantBased(code: 'plant_based', displayLabel: '비건·식물성'),
  other(code: 'other', displayLabel: '기타'),
  unclassified(code: 'unclassified', displayLabel: '미분류');

  const BurgerStyle({required this.code, required this.displayLabel});

  final String code;
  final String displayLabel;

  String get detailLabel =>
      this == BurgerStyle.unclassified ? '아직 분류되지 않았습니다.' : displayLabel;

  static BurgerStyle parse(String? value) {
    final normalizedValue = _normalizeBurgerStyleValue(value);
    return switch (normalizedValue) {
      'classic' || '클래식' || '클래식버거' || '클래식 버거' => BurgerStyle.classic,
      'smash' || '스매시' || '스매시버거' || '스매시 버거' => BurgerStyle.smash,
      'chicken' || '치킨' || '치킨버거' || '치킨 버거' => BurgerStyle.chicken,
      'plant_based' || '비건·식물성' || '비건' || '식물성' => BurgerStyle.plantBased,
      'other' || '기타' => BurgerStyle.other,
      'unclassified' || '미분류' => BurgerStyle.unclassified,
      _ => BurgerStyle.unclassified,
    };
  }
}

List<BurgerStyle> availableBurgerStyles(Iterable<StoreLocation> stores) {
  final availableStyles = stores
      .map((store) => BurgerStyle.parse(store.burgerStyle))
      .toSet();
  return List<BurgerStyle>.unmodifiable(
    BurgerStyle.values.where(availableStyles.contains),
  );
}

BurgerStyle? validBurgerStyleSelection(
  BurgerStyle? selectedStyle,
  Iterable<StoreLocation> stores,
) {
  if (selectedStyle == null) {
    return null;
  }
  return availableBurgerStyles(stores).contains(selectedStyle)
      ? selectedStyle
      : null;
}

String _normalizeBurgerStyleValue(String? value) {
  return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
