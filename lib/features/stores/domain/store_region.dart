enum StoreRegionFilterLevel { sido, sigungu, dong }

/// A legal 읍·면·동 path. This is separate from administrative-dong codes.
final class StoreRegion {
  StoreRegion({
    required this.sidoCode,
    required this.sidoName,
    required this.sigunguCode,
    required this.sigunguName,
    required this.dongCode,
    required this.dongName,
  }) {
    _requireCode(sidoCode, 2, 'sidoCode');
    _requireName(sidoName, 'sidoName');
    _requireCode(sigunguCode, 5, 'sigunguCode');
    if (!sigunguCode.startsWith(sidoCode)) {
      throw ArgumentError.value(
        sigunguCode,
        'sigunguCode',
        'The sigungu code must start with the sido code.',
      );
    }
    if (sigunguName != sigunguName.trim()) {
      throw ArgumentError.value(
        sigunguName,
        'sigunguName',
        'The sigungu name must not contain surrounding whitespace.',
      );
    }
    _requireCode(dongCode, 10, 'dongCode');
    if (!dongCode.startsWith(sigunguCode)) {
      throw ArgumentError.value(
        dongCode,
        'dongCode',
        'The dong code must start with the sigungu code.',
      );
    }
    if (!dongCode.endsWith('00') || dongCode.substring(5, 8) == '000') {
      throw ArgumentError.value(
        dongCode,
        'dongCode',
        'Use a legal 읍·면·동 code, not a parent or lower 리 code.',
      );
    }
    _requireName(dongName, 'dongName');
  }

  factory StoreRegion.fromJson(Object? value) {
    const fields = <String>{
      'sidoCode',
      'sidoName',
      'sigunguCode',
      'sigunguName',
      'dongCode',
      'dongName',
    };
    if (value is! Map ||
        value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        !fields.every(value.containsKey)) {
      throw const FormatException(
        'A store region must be an object with exactly six region fields.',
      );
    }
    if (!fields.every((field) => value[field] is String)) {
      throw const FormatException('Every store region field must be a string.');
    }

    try {
      return StoreRegion(
        sidoCode: value['sidoCode']! as String,
        sidoName: value['sidoName']! as String,
        sigunguCode: value['sigunguCode']! as String,
        sigunguName: value['sigunguName']! as String,
        dongCode: value['dongCode']! as String,
        dongName: value['dongName']! as String,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid store region: ${error.message}');
    }
  }

  final String sidoCode;
  final String sidoName;
  final String sigunguCode;
  final String sigunguName;
  final String dongCode;
  final String dongName;

  @override
  bool operator ==(Object other) {
    return other is StoreRegion &&
        sidoCode == other.sidoCode &&
        sigunguCode == other.sigunguCode &&
        dongCode == other.dongCode;
  }

  @override
  int get hashCode => Object.hash(sidoCode, sigunguCode, dongCode);

  static void _requireCode(String value, int length, String name) {
    if (!RegExp('^[0-9]{$length}\$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        'The code must contain exactly $length ASCII digits.',
      );
    }
  }

  static void _requireName(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'The name must not be empty.');
    }
  }
}

/// A filter anchored to a validated full region path.
///
/// Only the codes through [level] participate in matching and equality.
final class StoreRegionFilter {
  const StoreRegionFilter.sido(this.region)
    : level = StoreRegionFilterLevel.sido;

  const StoreRegionFilter.sigungu(this.region)
    : level = StoreRegionFilterLevel.sigungu;

  const StoreRegionFilter.dong(this.region)
    : level = StoreRegionFilterLevel.dong;

  final StoreRegion region;
  final StoreRegionFilterLevel level;

  String get label => switch (level) {
    StoreRegionFilterLevel.sido => region.sidoName,
    StoreRegionFilterLevel.sigungu =>
      region.sigunguName.trim().isEmpty ? region.sidoName : region.sigunguName,
    StoreRegionFilterLevel.dong => region.dongName,
  };

  String get pathLabel {
    final path = <String>[
      region.sidoName,
      if (level != StoreRegionFilterLevel.sido &&
          region.sigunguName.trim().isNotEmpty)
        region.sigunguName,
      if (level == StoreRegionFilterLevel.dong) region.dongName,
    ].join(' > ');
    return level == StoreRegionFilterLevel.dong ? path : '$path 전체';
  }

  bool matches(StoreRegion? candidate) {
    if (candidate == null || candidate.sidoCode != region.sidoCode) {
      return false;
    }
    if (level == StoreRegionFilterLevel.sido) {
      return true;
    }
    if (candidate.sigunguCode != region.sigunguCode) {
      return false;
    }
    return level == StoreRegionFilterLevel.sigungu ||
        candidate.dongCode == region.dongCode;
  }

  @override
  bool operator ==(Object other) {
    if (other is! StoreRegionFilter || level != other.level) {
      return false;
    }
    if (region.sidoCode != other.region.sidoCode) {
      return false;
    }
    if (level == StoreRegionFilterLevel.sido) {
      return true;
    }
    if (region.sigunguCode != other.region.sigunguCode) {
      return false;
    }
    return level == StoreRegionFilterLevel.sigungu ||
        region.dongCode == other.region.dongCode;
  }

  @override
  int get hashCode => switch (level) {
    StoreRegionFilterLevel.sido => Object.hash(level, region.sidoCode),
    StoreRegionFilterLevel.sigungu => Object.hash(
      level,
      region.sidoCode,
      region.sigunguCode,
    ),
    StoreRegionFilterLevel.dong => Object.hash(
      level,
      region.sidoCode,
      region.sigunguCode,
      region.dongCode,
    ),
  };
}
