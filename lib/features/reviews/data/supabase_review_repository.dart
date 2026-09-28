import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/review.dart';
import '../domain/review_repository.dart';

const defaultReviewTimeout = Duration(seconds: 10);
const reviewPublicSelectColumns =
    'id,store_id,user_id,rating,content,created_at';
const reviewOwnerSelectColumns =
    'id,store_id,user_id,rating,content,created_at,is_hidden';

class SupabaseReviewRepository implements ReviewRepository {
  const SupabaseReviewRepository({
    required this.clientLoader,
    this.timeout = defaultReviewTimeout,
  });

  final Future<SupabaseClient> Function() clientLoader;
  final Duration timeout;

  @override
  Future<List<StoreReview>> loadForStore(
    String storeId, {
    String? userId,
  }) async {
    try {
      return await (() async {
        final client = await clientLoader();
        final publicRows = await client
            .from('public_reviews')
            .select(reviewPublicSelectColumns)
            .eq('store_id', storeId)
            .order('created_at', ascending: false);
        final reviews = <String, StoreReview>{
          for (final row in publicRows)
            row['id'] as String: _reviewFromRow(row, isHidden: false),
        };
        if (userId != null) {
          // The base table exposes only this user's additional hidden review.
          final ownRows = await client
              .from('reviews')
              .select(reviewOwnerSelectColumns)
              .eq('store_id', storeId)
              .eq('user_id', userId);
          for (final row in ownRows) {
            reviews[row['id'] as String] = _reviewFromRow(
              row,
              isHidden: row['is_hidden'] as bool,
            );
          }
        }
        final result = reviews.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (result.isEmpty) return result;
        try {
          // Profiles expose only the public author's nickname, never email.
          final ids = result.map((review) => review.userId).toSet().toList();
          final profiles = await client
              .from('profiles')
              .select('id,nickname')
              .inFilter('id', ids);
          final nicknames = <String, String>{
            for (final profile in profiles)
              profile['id'] as String: profile['nickname'] as String,
          };
          return [
            for (final review in result)
              review.withNickname(nicknames[review.userId]),
          ];
        } on Object {
          // Public review data remains usable if optional author names fail.
          return result;
        }
      })().timeout(timeout);
    } on Object {
      throw const ReviewException(ReviewFailure.unavailable);
    }
  }

  @override
  Future<void> create({
    required String storeId,
    required int rating,
    required String? content,
  }) => _write((client, _) async {
    // user_id is deliberately omitted: the database default and RLS own it.
    await client.from('reviews').insert({
      'store_id': storeId,
      'rating': rating,
      'content': content,
    });
  });

  @override
  Future<void> update({
    required String reviewId,
    required int rating,
    required String? content,
  }) => _write((client, userId) async {
    final rows = await client
        .from('reviews')
        .update({'rating': rating, 'content': content})
        .eq('id', reviewId)
        .eq('user_id', userId)
        .select('id');
    if (rows.isEmpty) {
      throw const ReviewException(ReviewFailure.noLongerAvailable);
    }
  });

  @override
  Future<void> delete(String reviewId) => _write((client, userId) async {
    final rows = await client
        .from('reviews')
        .delete()
        .eq('id', reviewId)
        .eq('user_id', userId)
        .select('id');
    if (rows.isEmpty) {
      throw const ReviewException(ReviewFailure.noLongerAvailable);
    }
  });

  Future<void> _write(
    Future<void> Function(SupabaseClient client, String userId) operation,
  ) async {
    try {
      await (() async {
        final client = await clientLoader();
        final userId = client.auth.currentUser?.id;
        if (userId == null) {
          throw const ReviewException(ReviewFailure.unavailable);
        }
        await operation(client, userId);
      })().timeout(timeout);
    } on ReviewException {
      rethrow;
    } on TimeoutException {
      // Future.timeout does not cancel a request already accepted by PostgREST.
      throw const ReviewException(ReviewFailure.unknownOutcome);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const ReviewException(ReviewFailure.alreadyExists);
      }
      throw const ReviewException(ReviewFailure.unavailable);
    } on Object {
      throw const ReviewException(ReviewFailure.unknownOutcome);
    }
  }
}

StoreReview _reviewFromRow(Map<String, dynamic> row, {required bool isHidden}) {
  return StoreReview(
    id: row['id'] as String,
    storeId: row['store_id'] as String,
    userId: row['user_id'] as String,
    rating: row['rating'] as int,
    content: row['content'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    isHidden: isHidden,
  );
}
