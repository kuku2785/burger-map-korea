import 'package:burger_map_korea/features/stores/domain/store_region.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> validJson() => <String, Object?>{
    'sidoCode': '11',
    'sidoName': 'Alpha Province',
    'sigunguCode': '11170',
    'sigunguName': 'Central District',
    'dongCode': '1117010100',
    'dongName': 'River Neighborhood',
  };

  StoreRegion region({
    String sidoCode = '11',
    String sidoName = 'Alpha Province',
    String sigunguCode = '11170',
    String sigunguName = 'Central District',
    String dongCode = '1117010100',
    String dongName = 'River Neighborhood',
  }) {
    return StoreRegion(
      sidoCode: sidoCode,
      sidoName: sidoName,
      sigunguCode: sigunguCode,
      sigunguName: sigunguName,
      dongCode: dongCode,
      dongName: dongName,
    );
  }

  group('StoreRegion', () {
    test('parses an object with exactly the six region fields', () {
      final parsed = StoreRegion.fromJson(validJson());

      expect(parsed.sidoCode, '11');
      expect(parsed.sidoName, 'Alpha Province');
      expect(parsed.sigunguCode, '11170');
      expect(parsed.sigunguName, 'Central District');
      expect(parsed.dongCode, '1117010100');
      expect(parsed.dongName, 'River Neighborhood');
    });

    test('rejects missing, extra, non-string, non-ASCII, and bad prefixes', () {
      final missingField = validJson()..remove('dongName');
      final extraField = validJson()..['unexpected'] = 'value';
      final nonStringField = validJson()..['sidoCode'] = 11;
      final nonAsciiCode = validJson()..['sidoCode'] = '１１';
      final badSigunguPrefix = validJson()..['sigunguCode'] = '22170';
      final badDongPrefix = validJson()..['dongCode'] = '1120010100';

      for (final value in <Object?>[
        missingField,
        extraField,
        nonStringField,
        nonAsciiCode,
        badSigunguPrefix,
        badDongPrefix,
      ]) {
        expect(
          () => StoreRegion.fromJson(value),
          throwsFormatException,
          reason: 'Rejected value: $value',
        );
      }
    });

    test(
      'accepts legal-dong codes and rejects parent or lower-level codes',
      () {
        expect(region().dongCode, '1117010100');

        expect(
          () => region(dongCode: '1117000000'),
          throwsArgumentError,
          reason: 'A sigungu aggregate is not a selectable dong.',
        );
        expect(
          () => region(dongCode: '1117010101'),
          throwsArgumentError,
          reason: 'A lower-level code must not be treated as a legal dong.',
        );
      },
    );
  });

  test('filters match parent codes without relying on names', () {
    final reference = region();
    final renamedSamePath = region(
      sidoName: 'Renamed Province',
      sigunguName: 'Renamed District',
      dongName: 'Renamed Neighborhood',
    );
    final collidingNames = region(
      sidoCode: '22',
      sigunguCode: '22110',
      dongCode: '2211010100',
    );
    final otherDistrict = region(sigunguCode: '11200', dongCode: '1120010100');

    expect(StoreRegionFilter.sido(reference).matches(renamedSamePath), isTrue);
    expect(StoreRegionFilter.sido(reference).matches(collidingNames), isFalse);
    expect(
      StoreRegionFilter.sigungu(reference).matches(otherDistrict),
      isFalse,
    );
    expect(StoreRegionFilter.dong(reference).matches(renamedSamePath), isTrue);
    expect(StoreRegionFilter.dong(reference).matches(null), isFalse);
  });
}
