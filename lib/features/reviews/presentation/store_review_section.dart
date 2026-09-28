import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/application/auth_controller.dart';
import '../domain/review.dart';
import '../domain/review_repository.dart';

const reviewWriteButtonKey = ValueKey<String>('review-write-button');
const reviewRetryButtonKey = ValueKey<String>('review-retry-button');
const reviewContentFieldKey = ValueKey<String>('review-content-field');
const reviewSubmitButtonKey = ValueKey<String>('review-submit-button');
const reviewCheckResultButtonKey = ValueKey<String>(
  'review-check-result-button',
);
const reviewEditButtonKey = ValueKey<String>('review-edit-button');
const reviewDeleteButtonKey = ValueKey<String>('review-delete-button');

ValueKey<String> reviewPreferenceKey(int rating) =>
    ValueKey<String>('review-preference-$rating');

class StoreReviewSection extends StatefulWidget {
  const StoreReviewSection({
    super.key,
    required this.storeId,
    required this.repository,
    this.authController,
    this.authControllerListenable,
    this.onSignIn,
    this.onSetNickname,
    this.onRetryAuth,
  });

  final String storeId;
  final ReviewRepository repository;
  final AuthController? authController;
  final ValueListenable<AuthController?>? authControllerListenable;
  final VoidCallback? onSignIn;
  final VoidCallback? onSetNickname;
  final VoidCallback? onRetryAuth;

  @override
  State<StoreReviewSection> createState() => _StoreReviewSectionState();
}

class _StoreReviewSectionState extends State<StoreReviewSection> {
  final TextEditingController _contentController = TextEditingController();
  List<StoreReview>? _reviews;
  String? _requestedUserId;
  String? _loadError;
  String? _actionError;
  String? _validationError;
  int? _rating;
  int _loadGeneration = 0;
  bool _pendingWrite = false;
  bool _nicknameRequested = false;
  bool _editing = false;
  bool _saving = false;
  bool _needsResultCheck = false;
  AuthController? _listenedAuthController;

  AuthController? get _activeAuthController =>
      widget.authControllerListenable?.value ?? widget.authController;

  String? get _readyUserId {
    final auth = _activeAuthController;
    return auth?.state == AuthGateState.signedInReady
        ? auth?.profile?.id
        : null;
  }

  StoreReview? get _ownReview {
    final userId = _readyUserId;
    if (userId == null) return null;
    for (final review in _reviews ?? const <StoreReview>[]) {
      if (review.userId == userId) return review;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.authControllerListenable?.addListener(
      _handleControllerReferenceChanged,
    );
    _listenedAuthController = _activeAuthController;
    _listenedAuthController?.addListener(_handleAuthChanged);
    _load();
  }

  @override
  void didUpdateWidget(StoreReviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authController != widget.authController) {
      _syncAuthControllerListener();
    }
    if (oldWidget.authControllerListenable != widget.authControllerListenable) {
      oldWidget.authControllerListenable?.removeListener(
        _handleControllerReferenceChanged,
      );
      widget.authControllerListenable?.addListener(
        _handleControllerReferenceChanged,
      );
      _syncAuthControllerListener();
    }
    if (oldWidget.storeId != widget.storeId ||
        oldWidget.repository != widget.repository ||
        oldWidget.authController != widget.authController ||
        oldWidget.authControllerListenable != widget.authControllerListenable) {
      _clearEditor();
      _pendingWrite = false;
      _nicknameRequested = false;
      _load();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.authControllerListenable?.removeListener(
      _handleControllerReferenceChanged,
    );
    _listenedAuthController?.removeListener(_handleAuthChanged);
    _contentController.dispose();
    super.dispose();
  }

  void _handleAuthChanged() {
    if (!mounted) return;
    final userId = _readyUserId;
    if (_requestedUserId != userId) {
      _clearEditor();
      _load();
    }
    if (_pendingWrite &&
        _activeAuthController?.state == AuthGateState.signedInNeedsProfile &&
        !_nicknameRequested &&
        widget.onSetNickname != null) {
      _nicknameRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingWrite) widget.onSetNickname?.call();
      });
    }
  }

  void _handleControllerReferenceChanged() {
    _syncAuthControllerListener();
    _handleAuthChanged();
  }

  void _syncAuthControllerListener() {
    final next = _activeAuthController;
    if (identical(_listenedAuthController, next)) return;
    _listenedAuthController?.removeListener(_handleAuthChanged);
    _listenedAuthController = next;
    next?.addListener(_handleAuthChanged);
  }

  void _load() {
    final generation = ++_loadGeneration;
    final storeId = widget.storeId;
    final userId = _readyUserId;
    _requestedUserId = userId;
    setState(() {
      _reviews = null;
      _loadError = null;
    });
    unawaited(() async {
      try {
        final reviews = await widget.repository.loadForStore(
          storeId,
          userId: userId,
        );
        if (!mounted ||
            generation != _loadGeneration ||
            storeId != widget.storeId) {
          return;
        }
        setState(() {
          _reviews = reviews;
          if (_needsResultCheck) {
            _needsResultCheck = false;
            _actionError = null;
          }
          if (_pendingWrite && _readyUserId != null) {
            _pendingWrite = false;
            _beginEditor();
          }
        });
      } on Object {
        if (!mounted ||
            generation != _loadGeneration ||
            storeId != widget.storeId) {
          return;
        }
        setState(() => _loadError = '리뷰를 불러오지 못했습니다.');
      }
    }());
  }

  void _clearEditor() {
    _editing = false;
    _saving = false;
    _rating = null;
    _validationError = null;
    _actionError = null;
    _needsResultCheck = false;
    _contentController.clear();
  }

  void _beginEditor() {
    final own = _ownReview;
    _editing = true;
    _rating = own?.rating;
    _contentController.text = own?.content ?? '';
    _validationError = null;
    _actionError = null;
  }

  void _requestWrite() {
    if (_saving || _needsResultCheck) return;
    if (_readyUserId != null) {
      if (_reviews == null) return;
      setState(_beginEditor);
      return;
    }
    setState(() {
      _pendingWrite = true;
      _nicknameRequested = false;
    });
    if (_activeAuthController?.state == AuthGateState.signedInNeedsProfile) {
      _nicknameRequested = true;
      widget.onSetNickname?.call();
    } else if (_activeAuthController?.state == AuthGateState.error &&
        _activeAuthController?.hasSession == true) {
      widget.onRetryAuth?.call();
    } else {
      widget.onSignIn?.call();
    }
  }

  Future<void> _submit() async {
    if (_saving ||
        _needsResultCheck ||
        !_editing ||
        _readyUserId == null ||
        _rating == null) {
      return;
    }
    final content = normalizedReviewContent(_contentController.text);
    final validation = reviewContentValidationMessage(content);
    if (validation != null) {
      setState(() => _validationError = validation);
      return;
    }
    final own = _ownReview;
    final storeId = widget.storeId;
    final userId = _readyUserId;
    setState(() {
      _saving = true;
      _validationError = null;
      _actionError = null;
    });
    try {
      if (own == null) {
        await widget.repository.create(
          storeId: storeId,
          rating: _rating!,
          content: content,
        );
      } else {
        await widget.repository.update(
          reviewId: own.id,
          rating: _rating!,
          content: content,
        );
      }
      if (!mounted || storeId != widget.storeId || userId != _readyUserId) {
        return;
      }
      setState(() {
        _editing = false;
        _saving = false;
      });
      _load();
    } on ReviewException catch (error) {
      if (!mounted || storeId != widget.storeId || userId != _readyUserId) {
        return;
      }
      setState(() {
        _needsResultCheck = error.failure != ReviewFailure.unavailable;
        _actionError = switch (error.failure) {
          ReviewFailure.alreadyExists => '이미 작성한 리뷰가 있습니다. 다시 불러와 주세요.',
          ReviewFailure.noLongerAvailable => '리뷰를 변경할 수 없습니다. 다시 불러와 주세요.',
          ReviewFailure.unavailable => '리뷰를 저장하지 못했습니다. 다시 시도해 주세요.',
          ReviewFailure.unknownOutcome => '저장 결과를 확인하지 못했습니다. 다시 불러와 확인해 주세요.',
        };
      });
    } on Object {
      if (!mounted || storeId != widget.storeId || userId != _readyUserId) {
        return;
      }
      setState(() {
        _needsResultCheck = true;
        _actionError = '저장 결과를 확인하지 못했습니다. 다시 불러와 확인해 주세요.';
      });
    } finally {
      if (mounted && storeId == widget.storeId && userId == _readyUserId) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final own = _ownReview;
    if (_saving || own == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('리뷰를 삭제할까요?'),
        content: const Text('삭제한 리뷰는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _saving || _ownReview?.id != own.id) {
      return;
    }
    final storeId = widget.storeId;
    final userId = _readyUserId;
    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      await widget.repository.delete(own.id);
      if (!mounted || storeId != widget.storeId || userId != _readyUserId) {
        return;
      }
      setState(_clearEditor);
      _load();
    } on Object {
      if (!mounted || storeId != widget.storeId || userId != _readyUserId) {
        return;
      }
      setState(() => _actionError = '리뷰를 삭제하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted && storeId == widget.storeId && userId == _readyUserId) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('매장 선호 리뷰', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_reviews == null && _loadError == null)
          Semantics(
            liveRegion: true,
            label: '리뷰를 불러오는 중',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_loadError != null) ...[
          Text(_loadError!),
          OutlinedButton.icon(
            key: reviewRetryButtonKey,
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ] else ...[
          if (_reviews!.isEmpty) const Text('아직 작성된 리뷰가 없습니다.'),
          for (final review in _reviews!) _reviewCard(context, review),
          if (!_editing)
            OutlinedButton.icon(
              key: reviewWriteButtonKey,
              onPressed: _needsResultCheck ? null : _requestWrite,
              icon: const Icon(Icons.edit_outlined),
              label: Text(_ownReview == null ? '리뷰 작성' : '내 리뷰 수정'),
            ),
          if (_editing) _editor(context),
          if (_actionError != null) ...[
            const SizedBox(height: 8),
            Text(
              _actionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (_needsResultCheck)
              OutlinedButton.icon(
                key: reviewCheckResultButtonKey,
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 불러오기'),
              ),
          ],
        ],
      ],
    );
  }

  Widget _reviewCard(BuildContext context, StoreReview review) {
    final isOwn = review.userId == _readyUserId;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${preferenceLabel(review.rating)}${isOwn
                  ? ' · 내 리뷰'
                  : review.nickname == null
                  ? ''
                  : ' · ${review.nickname}'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (review.isHidden) const Text('이 리뷰는 현재 공개되지 않습니다.'),
            if (review.content != null && review.content!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(review.content!),
            ],
            const SizedBox(height: 6),
            Text(
              '${review.createdAt.toLocal().year}.${review.createdAt.toLocal().month.toString().padLeft(2, '0')}.${review.createdAt.toLocal().day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isOwn)
              Wrap(
                children: [
                  TextButton(
                    key: reviewEditButtonKey,
                    onPressed: _saving || _needsResultCheck
                        ? null
                        : () => setState(_beginEditor),
                    child: const Text('수정'),
                  ),
                  TextButton(
                    key: reviewDeleteButtonKey,
                    onPressed: _saving || _needsResultCheck ? null : _delete,
                    child: const Text('삭제'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _editor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('이 매장을 얼마나 선호하시나요?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final rating in const [5, 4, 3, 2, 1])
              Semantics(
                label: '선호도: ${preferenceLabel(rating)}',
                selected: _rating == rating,
                child: ChoiceChip(
                  key: reviewPreferenceKey(rating),
                  label: Text(preferenceLabel(rating)),
                  selected: _rating == rating,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _rating = rating),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: reviewContentFieldKey,
          controller: _contentController,
          enabled: !_saving,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: '리뷰 글 (선택)',
            hintText: '글 없이 선호도만 남겨도 됩니다.',
            border: OutlineInputBorder(),
          ),
        ),
        if (_validationError != null)
          Text(
            _validationError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: reviewSubmitButtonKey,
              onPressed: _saving || _needsResultCheck || _rating == null
                  ? null
                  : _submit,
              child: Text(_saving ? '저장 중' : '저장'),
            ),
            TextButton(
              onPressed: _saving || _needsResultCheck
                  ? null
                  : () => setState(_clearEditor),
              child: const Text('취소'),
            ),
          ],
        ),
      ],
    );
  }
}
