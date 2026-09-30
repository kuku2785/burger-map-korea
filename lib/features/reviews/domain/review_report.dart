enum ReviewReportReason {
  abuse,
  privacy,
  spam,
  falseInformation,
  irrelevant,
  other,
}

String reviewReportReasonLabel(ReviewReportReason reason) => switch (reason) {
  ReviewReportReason.abuse => '욕설·비방',
  ReviewReportReason.privacy => '개인정보 노출',
  ReviewReportReason.spam => '광고·도배',
  ReviewReportReason.falseInformation => '허위 정보 의심',
  ReviewReportReason.irrelevant => '매장/버거와 무관',
  ReviewReportReason.other => '기타',
};

/// The existing database accepts five reasons; the UI has six choices.
String reviewReportDatabaseReason(ReviewReportReason reason) =>
    switch (reason) {
      ReviewReportReason.abuse => 'harassment',
      ReviewReportReason.privacy => 'personal_information',
      ReviewReportReason.spam => 'spam',
      ReviewReportReason.falseInformation ||
      ReviewReportReason.other => 'other',
      ReviewReportReason.irrelevant => 'irrelevant',
    };

String? normalizedReportDetail(ReviewReportReason reason, String input) {
  final detail = input.trim();
  if (reason == ReviewReportReason.falseInformation) {
    return detail.isEmpty ? '허위 정보 의심' : '허위 정보 의심: $detail';
  }
  return detail.isEmpty ? null : detail;
}

String? reportDetailValidationMessage(
  ReviewReportReason reason,
  String? detail,
) {
  if (reason == ReviewReportReason.other && detail == null) {
    return '기타 사유를 입력해 주세요.';
  }
  if (detail != null && detail.runes.length > 1000) {
    return '설명은 1000자 이하로 입력해 주세요.';
  }
  return null;
}
