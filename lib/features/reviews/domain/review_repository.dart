import 'review.dart';

enum ReviewFailure {
  unavailable,
  alreadyExists,
  noLongerAvailable,
  unknownOutcome,
}

class ReviewException implements Exception {
  const ReviewException(this.failure);

  final ReviewFailure failure;
}

abstract class ReviewRepository {
  Future<List<StoreReview>> loadForStore(String storeId, {String? userId});
  Future<void> create({
    required String storeId,
    required int rating,
    required String? content,
  });
  Future<void> update({
    required String reviewId,
    required int rating,
    required String? content,
  });
  Future<void> delete(String reviewId);
}
