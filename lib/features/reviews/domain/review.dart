class StoreReview {
  const StoreReview({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.rating,
    required this.content,
    required this.createdAt,
    required this.isHidden,
    this.nickname,
  });

  final String id;
  final String storeId;
  final String userId;
  final int rating;
  final String? content;
  final DateTime createdAt;
  final bool isHidden;
  final String? nickname;

  StoreReview withNickname(String? value) => StoreReview(
    id: id,
    storeId: storeId,
    userId: userId,
    rating: rating,
    content: content,
    createdAt: createdAt,
    isHidden: isHidden,
    nickname: value,
  );
}

const reviewPreferenceLabels = <int, String>{
  5: '매우 선호',
  4: '선호',
  3: '보통',
  2: '비선호',
  1: '매우 비선호',
};

String preferenceLabel(int rating) =>
    reviewPreferenceLabels[rating] ?? '선호 정보 없음';

/// Empty or whitespace-only input has one canonical database representation.
String? normalizedReviewContent(String input) {
  final content = input.trim();
  return content.isEmpty ? null : content;
}

String? reviewContentValidationMessage(String? content) {
  if (content == null) return null;
  final characterCount = content.runes.length;
  if (characterCount < 10) return '리뷰 글은 10자 이상 입력해 주세요.';
  if (characterCount > 2000) return '리뷰 글은 2000자 이하로 입력해 주세요.';
  return null;
}
