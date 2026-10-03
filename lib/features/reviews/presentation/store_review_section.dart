import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/application/auth_controller.dart';
import '../domain/review.dart';
import '../domain/review_report.dart';
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
const reviewReportButtonKey = ValueKey<String>('review-report-button');
const reviewReportSubmitButtonKey = ValueKey<String>(
  'review-report-submit-button',
);
const reviewReportDetailFieldKey = ValueKey<String>(
  'review-report-detail-field',
);

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
  String? _pendingReportReviewId;
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
      _pendingReportReviewId = null;
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
    if (_pendingReportReviewId != null &&
        _activeAuthController?.state == AuthGateState.signedInNeedsProfile &&
        !_nicknameRequested &&
        widget.onSetNickname != null) {
      _nicknameRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingReportReviewId != null) {
          widget.onSetNickname?.call();
        }
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
        final pendingReport = _pendingReportReviewId;
        if (pendingReport != null && _readyUserId != null) {
          _pendingReportReviewId = null;
          final target = reviews.where((review) => review.id == pendingReport);
          if (target.isNotEmpty &&
              target.first.userId != _readyUserId &&
              !target.first.isHidden) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  generation == _loadGeneration &&
                  storeId == widget.storeId) {
                _openReport(target.first);
              }
            });
          }
        }
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
      _pendingReportReviewId = null;
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

  void _requestReport(StoreReview review) {
    if (_readyUserId != null) {
      _openReport(review);
      return;
    }
    _pendingReportReviewId = review.id;
    _pendingWrite = false;
    _nicknameRequested = false;
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

  Future<void> _openReport(StoreReview review) async {
    final storeId = widget.storeId;
    final userId = _readyUserId;
    if (userId == null ||
        review.userId == userId ||
        review.isHidden ||
        _reviews?.any((row) => row.id == review.id) != true) {
      return;
    }
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReviewReportDialog(
        reviewId: review.id,
        repository: widget.repository,
        isCurrent: () =>
            mounted &&
            storeId == widget.storeId &&
            userId == _readyUserId &&
            _reviews?.any((row) => row.id == review.id && !row.isHidden) ==
                true,
      ),
    );
    if (mounted &&
        submitted == true &&
        storeId == widget.storeId &&
        userId == _readyUserId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
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
            if (!isOwn && !review.isHidden)
              TextButton.icon(
                key: reviewReportButtonKey,
                onPressed: () => _requestReport(review),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('신고'),
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

class _ReviewReportDialog extends StatefulWidget {
  const _ReviewReportDialog({
    required this.reviewId,
    required this.repository,
    required this.isCurrent,
  });

  final String reviewId;
  final ReviewRepository repository;
  final bool Function() isCurrent;

  @override
  State<_ReviewReportDialog> createState() => _ReviewReportDialogState();
}

class _ReviewReportDialogState extends State<_ReviewReportDialog> {
  final TextEditingController _detailController = TextEditingController();
  ReviewReportReason? _reason;
  String? _error;
  bool _submitting = false;
  bool _unknownOutcome = false;
  bool _invalidated = false;

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _unknownOutcome || _invalidated) return;
    if (!widget.isCurrent()) {
      // A public-store refresh can dispose the section while this dialog route
      // remains open. Keep the draft and explain why no request was sent.
      setState(() {
        _invalidated = true;
        _error = '로그인 또는 매장 정보가 변경되었습니다. 신고 창을 닫고 다시 열어 주세요.';
      });
      return;
    }
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = '신고 사유를 선택해 주세요.');
      return;
    }
    final detail = normalizedReportDetail(reason, _detailController.text);
    final validation = reportDetailValidationMessage(reason, detail);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.report(
        reviewId: widget.reviewId,
        reason: reason,
        detail: detail,
      );
      if (mounted) Navigator.pop(context, true);
    } on ReviewException catch (error) {
      if (!mounted) return;
      setState(() {
        _unknownOutcome = error.failure == ReviewFailure.unknownOutcome;
        _error = switch (error.failure) {
          ReviewFailure.alreadyExists => '이미 신고한 리뷰입니다.',
          ReviewFailure.noLongerAvailable => '신고할 수 없는 리뷰입니다.',
          ReviewFailure.unavailable => '신고를 접수하지 못했습니다. 다시 시도해 주세요.',
          ReviewFailure.unknownOutcome =>
            '접수 결과를 확인하지 못했습니다. 중복 신고를 피하려면 나중에 확인해 주세요.',
        };
      });
    } on Object {
      if (mounted) {
        setState(() {
          _unknownOutcome = true;
          _error = '접수 결과를 확인하지 못했습니다. 중복 신고를 피하려면 나중에 확인해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AlertDialog(
      title: const Text('리뷰 신고'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('운영자가 내용을 확인합니다. 신고만으로 리뷰가 숨겨지지는 않습니다.'),
            const SizedBox(height: 12),
            RadioGroup<ReviewReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (_submitting || _invalidated) return;
                setState(() {
                  _reason = value;
                  _error = null;
                });
              },
              child: Column(
                children: [
                  for (final reason in ReviewReportReason.values)
                    RadioListTile<ReviewReportReason>(
                      key: ValueKey<String>(
                        'review-report-reason-${reason.name}',
                      ),
                      title: Text(reviewReportReasonLabel(reason)),
                      value: reason,
                    ),
                ],
              ),
            ),
            TextField(
              key: reviewReportDetailFieldKey,
              controller: _detailController,
              enabled: !_submitting && !_invalidated,
              maxLines: 3,
              maxLength: 990,
              decoration: InputDecoration(
                labelText: _reason == ReviewReportReason.other
                    ? '설명 (필수)'
                    : '설명 (선택)',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          key: reviewReportSubmitButtonKey,
          onPressed: _submitting || _unknownOutcome || _invalidated
              ? null
              : _submit,
          child: Text(_submitting ? '접수 중' : '신고 접수'),
        ),
      ],
    ),
  );
}
