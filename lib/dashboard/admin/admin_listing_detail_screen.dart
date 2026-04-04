import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/admin_action_service.dart';
import '../../services/auth_service.dart';
import '../../services/auction_lifecycle_service.dart';
import '../../services/phase1_notification_engine.dart';

class _AdminUiException implements Exception {
  const _AdminUiException(this.message);

  final String message;
}

class AdminListingDetailScreen extends StatefulWidget {
  const AdminListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  State<AdminListingDetailScreen> createState() =>
      _AdminListingDetailScreenState();
}

class _AdminListingDetailScreenState extends State<AdminListingDetailScreen> {
  static const Color _bg = Color(0xFF0B1F3A);
  static const Color _panelColor = Color(0xFF122B4A);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AdminActionService _adminActions = AdminActionService();
  final AuthService _authService = AuthService();
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();
  final AuctionLifecycleService _auctionLifecycleService =
      AuctionLifecycleService();
  final Set<String> _loadingActions = <String>{};

  void _diag(String message) {
    debugPrint('[AdminListingDetail] $message');
  }

  String _status(Map<String, dynamic> data) {
    return _s(
      data['status'],
      fallback: _s(
        data['listingStatus'],
        fallback: _s(data['auctionStatus'], fallback: ''),
      ),
    ).toLowerCase();
  }

  String _auctionStatus(Map<String, dynamic> data) {
    return _s(data['auctionStatus'], fallback: _status(data)).toLowerCase();
  }

  String _safeError(Object error) {
    if (error is _AdminUiException) return error.message;
    if (error is FirebaseException && (error.message ?? '').trim().isNotEmpty) {
      return error.message!.trim();
    }
    return 'Operation failed';
  }

  String _errorCode(Object error) {
    if (error is FirebaseException) return error.code;
    return 'unknown';
  }

  String _buildActionErrorMessage(String failedMessage, Object error) {
    final String code = _errorCode(error).trim();
    final String detail = _safeError(error).trim();
    if (detail.isEmpty || detail == 'Operation failed') {
      return failedMessage;
    }
    if (code.isEmpty || code == 'unknown') {
      return '$failedMessage ($detail)';
    }
    return '$failedMessage ($code: $detail)';
  }

  Future<Map<String, dynamic>> _loadListing() async {
    final snap = await _db.collection('listings').doc(widget.listingId).get();
    if (!snap.exists) {
      throw const _AdminUiException('Listing not found');
    }
    return snap.data() ?? <String, dynamic>{};
  }

  Future<void> _traceFailure({
    required String action,
    required String targetId,
    required Object error,
    String? previousStatus,
    String? intendedStatus,
  }) async {
    await _db.collection('admin_action_logs').add({
      'entityType': 'listing',
      'entityId': targetId,
      'actionType': action,
      'actionBy': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
      'actionAt': FieldValue.serverTimestamp(),
      'targetCollection': 'listings',
      'targetDocId': targetId,
      'previousStatus': previousStatus,
      'intendedStatus': intendedStatus,
      'error': _safeError(error),
      'result': 'failed',
    });
  }

  bool _isActionLoading(String key) => _loadingActions.contains(key);

  Future<void> _runAction({
    required String actionKey,
    required String failedMessage,
    required String failureAction,
    required String targetId,
    String? previousStatus,
    String? intendedStatus,
    required Future<void> Function() action,
    String? successMessage,
  }) async {
    if (_isActionLoading(actionKey)) return;
    final String firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    debugPrint('[ADMIN_ACTION] action=$failureAction');
    debugPrint('[ADMIN_ACTION] firebaseUid=$firebaseUid');
    debugPrint('[ADMIN_ACTION] docPath=listings/$targetId');
    debugPrint('[ADMIN_ACTION] payload={"actionKey":"$actionKey"}');
    _diag('action_tap action=$failureAction target=listings/$targetId');
    setState(() => _loadingActions.add(actionKey));
    try {
      final bool hasSession = await _authService.ensureFirebaseSessionForAdminWrite(
        flowLabel: 'admin_listing_detail_$failureAction',
      );
      if (!hasSession) {
        throw const _AdminUiException(
          'Admin Firebase session is not active or lacks admin role. Please sign in again.',
        );
      }
      await action();
      debugPrint('[ADMIN_ACTION] errorCode=');
      debugPrint('[ADMIN_ACTION] errorMessage=');
      debugPrint('[ADMIN_ACTION] success=true');
      if (!mounted) return;
      if (successMessage != null && successMessage.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      debugPrint('[ADMIN_ACTION] errorCode=${_errorCode(error)}');
      debugPrint('[ADMIN_ACTION] errorMessage=${_safeError(error)}');
      debugPrint('[ADMIN_ACTION] success=false');
      _diag(
        'action_failure action=$failureAction target=listings/$targetId error=${_safeError(error)}',
      );
      try {
        await _traceFailure(
          action: failureAction,
          targetId: targetId,
          error: error,
          previousStatus: previousStatus,
          intendedStatus: intendedStatus,
        );
      } catch (_) {
        _diag(
          'action_failure_log_write_failed action=$failureAction target=listings/$targetId',
        );
      }
      if (!mounted) return;
      final String failureText = _buildActionErrorMessage(
        failedMessage,
        error,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureText)));
    } finally {
      if (mounted) setState(() => _loadingActions.remove(actionKey));
    }
  }

  Future<void> _logAction({
    required String actionType,
    String notes = '',
    String? previousStatus,
    String? newStatus,
    String? previousAuctionStatus,
    String? newAuctionStatus,
    String? previousPromotionStatus,
    String? newPromotionStatus,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    final now = FieldValue.serverTimestamp();
    await _db.collection('admin_action_logs').add({
      'entityType': 'listing',
      'entityId': widget.listingId,
      'actionType': actionType,
      'actionBy': uid,
      'actionAt': now,
      'notes': notes,
      'reason': notes,
      'targetCollection': 'listings',
      'targetDocId': widget.listingId,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'previousAuctionStatus': previousAuctionStatus,
      'newAuctionStatus': newAuctionStatus,
      'previousPromotionStatus': previousPromotionStatus,
      'newPromotionStatus': newPromotionStatus,
      'previousStateSummary': {
        'status': previousStatus,
        'auctionStatus': previousAuctionStatus,
        'promotionStatus': previousPromotionStatus,
      },
      'newStateSummary': {
        'status': newStatus,
        'auctionStatus': newAuctionStatus,
        'promotionStatus': newPromotionStatus,
      },
      'result': 'success',
    });

    await _db.collection('listings').doc(widget.listingId).set({
      'lastAdminAction': {
        'actionType': actionType,
        'actionBy': uid,
        'actionAt': now,
        'notes': notes,
      },
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  Future<void> _writeRevenueLedger({
    required String entryType,
    required String sellerId,
    required double amount,
    required String revenueCategory,
    required String status,
    required String notes,
    bool markApproved = false,
  }) async {
    await _db.collection('revenue_ledger').add({
      'entryType': entryType,
      'sourceListingId': widget.listingId,
      'sellerId': sellerId,
      'amount': amount,
      'revenueCategory': revenueCategory,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'approvedAt': markApproved ? FieldValue.serverTimestamp() : null,
      'notes': notes,
    });
  }

  Future<void> _notifyUser({
    required String userId,
    required String type,
    required String title,
    required String body,
    required Map<String, dynamic> metadata,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedType = type.trim().toUpperCase();
    final listingId = widget.listingId.trim();
    if (normalizedUserId.isEmpty || listingId.isEmpty) return;
    if (!Phase1NotificationType.all.contains(normalizedType)) {
      debugPrint(
        '[NotifWrite] skipped_unsupported_type type=$normalizedType toUid=$normalizedUserId listingId=$listingId',
      );
      return;
    }
    await _phase1Notifications.createOnce(
      userId: normalizedUserId,
      type: normalizedType,
      listingId: listingId,
      titleEn: title,
      bodyEn: body,
      targetRole: (metadata['targetRole'] ?? 'seller').toString(),
    );
  }

  Future<void> _approveListing() async {
    final current = await _loadListing();
    _diag(
      'approve_listing start listing=${widget.listingId} status=${_status(current)} approved=${current['isApproved'] == true}',
    );
    final status = _status(current);
    if ((current['isApproved'] == true) &&
        (status == 'active' || status == 'live')) {
      throw const _AdminUiException('Listing is already approved');
    }
    _diag(
      'approve_listing request_start listing=${widget.listingId} function=approveListingAdmin',
    );
    await _adminActions.approveListingAdmin(listingId: widget.listingId);
    final updated = await _db
        .collection('listings')
        .doc(widget.listingId)
        .get();
    final sellerUid = (updated.data()?['sellerId'] ?? '').toString().trim();
    if (sellerUid.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerUid,
        type: Phase1NotificationType.listingApproved,
        listingId: widget.listingId,
        targetRole: 'seller',
      );
    }
    final um = updated.data() ?? <String, dynamic>{};
    _diag(
      'approve_listing doc listing=${widget.listingId} isApproved=${um['isApproved']} status=${um['status']} listingStatus=${um['listingStatus']} auctionStatus=${um['auctionStatus']}',
    );
    _diag('approve_listing success listing=${widget.listingId}');
  }

  Future<void> _rejectListing(String notes) async {
    final current = await _loadListing();
    final status = _status(current);
    if (notes.trim().isEmpty) {
      throw const _AdminUiException('Admin note is required to reject listing');
    }
    _diag(
      'reject_listing request_start listing=${widget.listingId} function=rejectListingAdmin',
    );
    await _adminActions.rejectListingAdmin(
      listingId: widget.listingId,
      note: notes,
    );
    final updated = await _db
        .collection('listings')
        .doc(widget.listingId)
        .get();
    final sellerUid = (updated.data()?['sellerId'] ?? '').toString().trim();
    if (sellerUid.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerUid,
        type: Phase1NotificationType.listingRejected,
        listingId: widget.listingId,
        targetRole: 'seller',
      );
    }
    _diag(
      'reject_listing success listing=${widget.listingId} previousStatus=$status',
    );
  }

  Future<void> _requestChanges(String notes) async {
    final current = await _loadListing();
    final status = _status(current);
    if (notes.trim().isEmpty) {
      throw const _AdminUiException(
        'Admin note is required to request changes',
      );
    }
    _diag(
      'request_changes request_start listing=${widget.listingId} function=requestListingChangesAdmin',
    );
    await _adminActions.requestListingChangesAdmin(
      listingId: widget.listingId,
      note: notes,
    );
    _diag(
      'request_changes success listing=${widget.listingId} previousStatus=$status',
    );
  }

  Future<void> _startAuction() async {
    final current = await _loadListing();
    _diag(
      'start_auction tap listing=${widget.listingId} status=${_status(current)} auction=${_auctionStatus(current)}',
    );
    final status = _status(current);
    final auction = _auctionStatus(current);
    if (status == 'rejected') {
      throw const _AdminUiException(
        'Cannot start auction for rejected listing',
      );
    }
    if (auction == 'live') {
      throw const _AdminUiException('Auction is already live');
    }
    if (auction == 'cancelled' || auction == 'completed') {
      throw const _AdminUiException(
        'Cannot restart cancelled or completed auction',
      );
    }
    _diag(
      'start_auction request_start listing=${widget.listingId} function=startAuctionAdmin',
    );
    await _adminActions.startAuctionAdmin(listingId: widget.listingId);
    final updated = await _db
        .collection('listings')
        .doc(widget.listingId)
        .get();
    final um = updated.data() ?? <String, dynamic>{};
    _diag(
      'start_auction doc listing=${widget.listingId} isApproved=${um['isApproved']} status=${um['status']} listingStatus=${um['listingStatus']} auctionStatus=${um['auctionStatus']}',
    );
    _diag('start_auction success listing=${widget.listingId}');
  }

  Future<void> _pauseAuction() async {
    final current = await _loadListing();
    final auction = _auctionStatus(current);
    if (auction != 'live') {
      throw _AdminUiException('Cannot pause auction while status is $auction');
    }
    _diag(
      'pause_auction request_start listing=${widget.listingId} function=pauseAuctionAdmin',
    );
    await _adminActions.pauseAuctionAdmin(listingId: widget.listingId);
    _diag(
      'pause_auction success listing=${widget.listingId} previousAuction=$auction',
    );
  }

  Future<void> _cancelAuction(String note) async {
    final current = await _loadListing();
    final auction = _auctionStatus(current);
    if (auction == 'cancelled' || auction == 'completed') {
      throw _AdminUiException('Cannot cancel auction while status is $auction');
    }
    if (note.trim().isEmpty) {
      throw const _AdminUiException('Admin note is required to cancel auction');
    }
    _diag(
      'cancel_auction request_start listing=${widget.listingId} function=cancelAuctionAdmin',
    );
    await _adminActions.cancelAuctionAdmin(
      listingId: widget.listingId,
      note: note,
    );
    _diag(
      'cancel_auction success listing=${widget.listingId} previousAuction=$auction',
    );
  }

  Future<void> _resumeAuction() async {
    final current = await _loadListing();
    final auction = _auctionStatus(current);
    if (auction != 'paused') {
      throw _AdminUiException('Cannot resume auction while status is $auction');
    }
    _diag(
      'resume_auction request_start listing=${widget.listingId} function=resumeAuctionAdmin',
    );
    await _adminActions.resumeAuctionAdmin(listingId: widget.listingId);
    _diag(
      'resume_auction success listing=${widget.listingId} previousAuction=$auction',
    );
  }

  Future<void> _extendAuction() async {
    final data = await _loadListing();
    final auction = _auctionStatus(data);
    if (auction != 'live' && auction != 'paused') {
      throw _AdminUiException(
        'Can only extend live or paused auction, current: $auction',
      );
    }
    _diag(
      'extend_auction request_start listing=${widget.listingId} function=extendAuctionAdmin extensionHours=2',
    );
    await _adminActions.extendAuctionAdmin(
      listingId: widget.listingId,
      extensionHours: 2,
    );
    _diag(
      'extend_auction success listing=${widget.listingId} previousAuction=$auction',
    );
  }

  Future<void> _finalizeAuctionNow() async {
    await _auctionLifecycleService.finalizeAuctionIfEnded(
      listingId: widget.listingId,
      force: true,
      source: 'admin_listing_detail',
    );
  }

  Future<void> _markDealOutcomeAdmin(String status) async {
    await _auctionLifecycleService.updateDealOutcome(
      listingId: widget.listingId,
      outcomeStatus: status,
      note: 'Updated by admin listing detail',
    );
  }

  Future<void> _setPromotionStatus(String status, {String note = ''}) async {
    final current = await _loadListing();
    final previousPromo = _s(
      current['promotionStatus'],
      fallback: 'none',
    ).toLowerCase();
    final promoType = _s(
      current['promotionType'],
      fallback: current['featuredAuction'] == true
          ? 'featured_auction'
          : 'featured_listing',
    ).toLowerCase();
    final amount = _n(current['featuredCost']);
    if (status == previousPromo) {
      throw _AdminUiException('Promotion is already $status');
    }
    if (status == 'active' && previousPromo != 'approved') {
      throw const _AdminUiException('Approve promotion before activation');
    }
    if (status == 'rejected' && note.trim().isEmpty) {
      throw const _AdminUiException('Rejection reason is required');
    }
    if (status == 'pending_review' && note.trim().isEmpty) {
      throw const _AdminUiException(
        'Reason is required to request better proof',
      );
    }

    final updates = <String, dynamic>{
      'promotionStatus': status,
      'promotionDecisionNote': note.trim(),
      'moderationReason': note.trim(),
      'promotionReview': {
        'status': status,
        'reason': note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'promotionUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == 'approved') {
      updates['promotionApprovedAt'] = FieldValue.serverTimestamp();
      updates['promotionReviewRequired'] = false;
    }
    if (status == 'active') {
      updates['promotionActivatedAt'] = FieldValue.serverTimestamp();
      updates['promotionStartsAt'] =
          current['promotionStartsAt'] ?? FieldValue.serverTimestamp();
      updates['promotionExpiresAt'] =
          current['promotionExpiresAt'] ??
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 7)));
      updates['featured'] = true;
      updates['priorityScore'] = 'high';
    }
    if (status == 'expired') {
      updates['promotionExpiredAt'] = FieldValue.serverTimestamp();
      updates['featured'] = false;
      updates['featuredAuction'] = false;
      updates['priorityScore'] = 'normal';
    }
    if (status == 'rejected') {
      updates['promotionRejectedAt'] = FieldValue.serverTimestamp();
      updates['promotionReviewRequired'] = false;
    }
    if (status == 'pending_review') {
      updates['promotionReviewRequired'] = true;
      updates['promotionReviewAt'] = FieldValue.serverTimestamp();
    }

    final String promoAction = status == 'approved'
        ? 'approve_promotion'
        : status == 'rejected'
            ? 'reject_promotion'
            : status == 'active'
                ? 'activate_promotion'
                : status == 'expired'
                    ? 'deactivate_promotion'
                    : 'promotion_$status';
    final String firebaseUid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    debugPrint('[ADMIN_ACTION] action=$promoAction');
    debugPrint('[ADMIN_ACTION] firebaseUid=$firebaseUid');
    debugPrint('[ADMIN_ACTION] docPath=listings/${widget.listingId}');
    debugPrint('[ADMIN_ACTION] payload=$updates');

    await _db.collection('listings').doc(widget.listingId).set({
      ...updates,
    }, SetOptions(merge: true));

    final sellerId = _s(
      current['sellerId'],
      fallback: _s(
        current['ownerId'],
        fallback: _s(current['userId'], fallback: ''),
      ),
    );
    if (sellerId != '-' && sellerId.isNotEmpty && amount > 0) {
      try {
        await _writeRevenueLedger(
          entryType: 'promotion_$status',
          sellerId: sellerId,
          amount: amount,
          revenueCategory: promoType,
          status: status,
          notes: note.trim().isEmpty ? 'Promotion $status' : note.trim(),
          markApproved: status == 'approved' || status == 'active',
        );
      } catch (error) {
        _diag(
          'non_critical_revenue_ledger_failure action=promotion_$status target=listings/${widget.listingId} error=${_safeError(error)}',
        );
      }

      final listingName = _s(
        current['itemName'],
        fallback: _s(current['product'], fallback: 'Listing'),
      );
      final userFacingStatus = status == 'pending_review'
          ? 'under review'
          : status;
      try {
        await _notifyUser(
          userId: sellerId,
          type: 'promotion_$status',
          title: 'Promotion update',
          body: note.trim().isEmpty
              ? 'Promotion for $listingName is now $userFacingStatus.'
              : 'Promotion for $listingName is now $userFacingStatus. Reason: $note',
          metadata: {
            'status': status,
            'note': note.trim(),
            'promotionType': promoType,
            'amount': amount,
          },
        );
      } catch (error) {
        _diag(
          'non_critical_notify_failure action=promotion_$status target=listings/${widget.listingId} error=${_safeError(error)}',
        );
      }
    }

    try {
      await _logAction(
        actionType: 'promotion_$status',
        notes: note.trim(),
        previousStatus: _status(current),
        newStatus: _status(current),
        previousAuctionStatus: _auctionStatus(current),
        newAuctionStatus: _auctionStatus(current),
        previousPromotionStatus: previousPromo,
        newPromotionStatus: status,
      );
    } catch (error) {
      _diag(
        'non_critical_log_failure action=promotion_$status target=listings/${widget.listingId} error=${_safeError(error)}',
      );
    }
    debugPrint('[ADMIN_ACTION] errorCode=');
    debugPrint('[ADMIN_ACTION] errorMessage=');
    debugPrint('[ADMIN_ACTION] success=true');
  }

  Future<String?> _askNotes(
    String title, {
    bool required = false,
    String hint = 'Add admin note',
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? localError;
        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                errorText: localError,
              ),
            ),
            actions: [
              if (!required)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: const Text('Skip'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final note = controller.text.trim();
                  if (required && note.isEmpty) {
                    setLocalState(() {
                      localError = 'Reason is required';
                    });
                    return;
                  }
                  Navigator.pop(ctx, note);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return value;
  }

  String _s(dynamic value, {String fallback = '-'}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _n(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _s(data[key], fallback: '');
      if (value.isNotEmpty) return value;
    }
    final media = data['mediaMetadata'];
    if (media is Map) {
      for (final key in keys) {
        final value = (media[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      final verification = media['verificationVideo'];
      if (verification is Map) {
        final url = (verification['url'] ?? '').toString().trim();
        if (url.isNotEmpty && url.toLowerCase() != 'null') return url;
      }
      final trust = media['verificationTrustPhoto'];
      if (trust is Map) {
        final url = (trust['url'] ?? '').toString().trim();
        if (url.isNotEmpty && url.toLowerCase() != 'null') return url;
      }
    }
    return '';
  }

  List<String> _extractImageUrls(Map<String, dynamic> data) {
    final urls = <String>[];
    void addUrl(dynamic value) {
      final url = (value ?? '').toString().trim();
      if (url.isEmpty || url.toLowerCase() == 'null') return;
      if (!url.startsWith('http')) return;
      if (!urls.contains(url)) urls.add(url);
    }

    addUrl(data['imageUrl']);
    addUrl(data['photoUrl']);
    addUrl(data['trustPhotoUrl']);
    addUrl(data['verificationTrustPhotoUrl']);

    final imageUrls = data['imageUrls'];
    if (imageUrls is List) {
      for (final item in imageUrls) {
        addUrl(item);
      }
    }

    final images = data['images'];
    if (images is List) {
      for (final item in images) {
        addUrl(item);
      }
    }

    final media = data['mediaMetadata'];
    if (media is Map) {
      final mediaImageUrls = media['imageUrls'];
      if (mediaImageUrls is List) {
        for (final item in mediaImageUrls) {
          addUrl(item);
        }
      }
      final trust = media['verificationTrustPhoto'];
      if (trust is Map) addUrl(trust['url']);
    }

    return urls;
  }

  Future<Map<String, dynamic>?> _loadSellerProfile(String sellerUid) async {
    final uid = sellerUid.trim();
    if (uid.isEmpty || uid == '-') return null;
    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  String _safeLabel(dynamic value, {String fallback = 'Not available'}) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty ||
        text == '-' ||
        text == '--' ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'unavailable') {
      return fallback;
    }
    return text;
  }

  String _titleCase(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return 'Unknown';
    return cleaned
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) return part;
          return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  String _humanizeCategory(Map<String, dynamic> data) {
    final parts = <String>[];
    final category = _s(data['categoryLabel'], fallback: _s(data['category']));
    final sub = _s(data['subcategoryLabel'], fallback: _s(data['subcategory']));
    final variety = _s(data['variety']);
    for (final value in [category, sub, variety]) {
      final normalized = value.trim();
      if (normalized.isEmpty || normalized == '-' || normalized == '--') {
        continue;
      }
      parts.add(_titleCase(normalized));
    }
    if (parts.isEmpty) return 'Uncategorized';
    return parts.join(' > ');
  }

  String _formatDateTime(dynamic value) {
    DateTime? dt;
    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is DateTime) {
      dt = value;
    } else if (value is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) dt = parsed;
    }
    if (dt == null) return 'Not available';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = dt.toLocal();
    final m = months[local.month - 1];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day} $m ${local.year}, $hour:$minute $suffix';
  }

  String _formatMoney(num value) {
    final fixed = value.toStringAsFixed(0);
    return 'Rs $fixed';
  }

  String _moderationChipText(Map<String, dynamic> data) {
    final status = _status(data);
    if (status == 'approved' || status == 'active' || data['isApproved'] == true) {
      return 'Approved';
    }
    if (status == 'rejected') return 'Rejected';
    if (status.contains('review') || status.contains('pending')) {
      return 'Pending Review';
    }
    return _titleCase(status.isEmpty ? 'pending' : status);
  }

  String _auctionChipText(String raw) {
    final status = raw.toLowerCase().trim();
    if (status == 'live') return 'Auction Live';
    if (status == 'paused') return 'Auction Paused';
    if (status == 'cancelled') return 'Auction Cancelled';
    if (status == 'completed' || status == 'ended') return 'Auction Closed';
    if (status == '-' || status.isEmpty) return 'Auction Pending';
    return _titleCase(status);
  }

  String _promotionChipText(String raw) {
    final status = raw.toLowerCase().trim();
    if (status == 'active') return 'Promotion Active';
    if (status == 'approved') return 'Promotion Approved';
    if (status == 'pending_review' || status.contains('review')) {
      return 'Payment Review';
    }
    if (status == 'rejected') return 'Promotion Rejected';
    if (status == 'expired') return 'Promotion Inactive';
    if (status == '-' || status.isEmpty || status == 'none') {
      return 'Promotion None';
    }
    return _titleCase(status);
  }

  String _outcomeChipText(String raw) {
    final status = raw.toLowerCase().trim();
    if (status == 'successful') return 'Outcome Successful';
    if (status == 'failed') return 'Outcome Failed';
    if (status.isEmpty || status == '-') return 'Outcome Pending';
    if (status == 'pending_contact') return 'Outcome Pending';
    return _titleCase(status);
  }

  String _auctionDisabledHint({
    required String action,
    required bool canStartAuction,
    required bool canPauseAuction,
    required bool canResumeAuction,
    required bool canCancelAuction,
    required bool canExtendAuction,
    required String auctionLower,
  }) {
    if (action == 'start' && !canStartAuction) {
      if (auctionLower == 'live') return 'Already live.';
      if (auctionLower == 'cancelled' || auctionLower == 'completed') {
        return 'Not available after cancellation or completion.';
      }
      return 'Unavailable in current listing state.';
    }
    if (action == 'pause' && !canPauseAuction) {
      return 'Available after auction starts.';
    }
    if (action == 'resume' && !canResumeAuction) {
      return 'Available only when auction is paused.';
    }
    if (action == 'cancel' && !canCancelAuction) {
      return 'Not available after auction is closed.';
    }
    if (action == 'extend' && !canExtendAuction) {
      return 'Available when auction is live or paused.';
    }
    return '';
  }

  Future<bool> _confirmDangerAction({
    required String title,
    required String body,
    String irreversibleText = 'This action may not be reversible.',
    String confirmLabel = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: 8),
            Text(
              irreversibleText,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }

  Widget _kv(String label, String value, {bool subtle = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: subtle ? Colors.white70 : Colors.white,
                fontWeight: subtle ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionWithHint(
    String label,
    Color color, {
    required String actionKey,
    required VoidCallback onTap,
    required bool enabled,
    String helperText = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _action(
          label,
          color,
          actionKey: actionKey,
          onTap: onTap,
          enabled: enabled,
        ),
        if (!enabled && helperText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              helperText,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Future<void> _showFullDetails(Map<String, dynamic> data) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF102845),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Full Listing Snapshot',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _kv('Created', _formatDateTime(data['createdAt']), subtle: true),
                _kv('Updated', _formatDateTime(data['updatedAt']), subtle: true),
                _kv(
                  'Description',
                  _safeLabel(data['description'], fallback: 'No description added.'),
                  subtle: true,
                ),
                _kv(
                  'Market Average',
                  _n(data['marketAverage']) > 0 || _n(data['market_average']) > 0
                      ? _formatMoney(
                          _n(data['marketAverage']) > 0
                              ? _n(data['marketAverage'])
                              : _n(data['market_average']),
                        )
                      : 'Market data not available',
                  subtle: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Listing Operations',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            Text(
              'Admin Listing Detail',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('listings').doc(widget.listingId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Could not load listing right now. / لسٹنگ اس وقت لوڈ نہیں ہو سکی۔',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!(snapshot.data?.exists ?? false)) {
            return const Center(
              child: Text(
                'Listing not found. / لسٹنگ موجود نہیں۔',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            );
          }
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final price = _n(data['price']);
          final qty = _n(data['quantity']) > 0
              ? _n(data['quantity'])
              : _n(data['weight']);
          final unit = _s(
            data['unit'],
            fallback: _s(data['unitType'], fallback: 'unit'),
          );
          final marketAvg = _n(data['marketAverage']) > 0
              ? _n(data['marketAverage'])
              : _n(data['market_average']);
          final deviation = marketAvg > 0
              ? ((price - marketAvg) / marketAvg) * 100
              : 0;
          final imageUrls = _extractImageUrls(data);
          final trustPhotoUrl = _firstText(data, const [
            'verificationTrustPhotoUrl',
            'trustPhotoUrl',
            'photoUrl',
            'imageUrl',
          ]);
          final videoUrl = _firstText(data, const [
            'videoUrl',
            'verificationVideoUrl',
            'videoURL',
            'mediaVideoUrl',
          ]);
          final audioUrl = _firstText(data, const [
            'audioUrl',
            'voiceUrl',
            'audioURL',
          ]);

          final statusText = _s(data['status']);
          final auctionText = _s(data['auctionStatus']);
          final promoText = _s(data['promotionStatus'], fallback: 'none');
          final sellerUid = _s(
            data['sellerId'],
            fallback: _s(data['ownerId'], fallback: _s(data['userId'], fallback: '')),
          );
          final winnerId = _s(
            data['winnerId'],
            fallback: _s(data['buyerId'], fallback: '--'),
          );
          final acceptedBidId = _s(data['acceptedBidId'], fallback: '--');
          final dealOutcomeStatus = _s(
            data['dealOutcomeStatus'],
            fallback: 'pending_contact',
          );
          final statusLower = statusText.toLowerCase();
          final auctionLower = auctionText.toLowerCase();
          final bool isApproved = data['isApproved'] == true;
          final canApprove =
              !(isApproved &&
                  (statusLower == 'active' ||
                      statusLower == 'approved' ||
                      auctionLower == 'live'));
          final canStartAuction =
              statusLower != 'rejected' &&
              auctionLower != 'live' &&
              auctionLower != 'cancelled' &&
              auctionLower != 'completed';
          final canPauseAuction = auctionLower == 'live';
          final canResumeAuction = auctionLower == 'paused';
          final canCancelAuction =
              auctionLower != 'cancelled' && auctionLower != 'completed';
          final canExtendAuction =
              auctionLower == 'live' || auctionLower == 'paused';

          _diag(
            'media_resolve listing=${widget.listingId} images=${imageUrls.length} trustPhoto=${trustPhotoUrl.isNotEmpty} video=${videoUrl.isNotEmpty} audio=${audioUrl.isNotEmpty}',
          );

          final itemName = _safeLabel(
            _s(data['itemName'], fallback: _s(data['product'], fallback: 'Listing')),
            fallback: 'Listing',
          );
          final itemNameUr = _safeLabel(
            _s(data['itemNameUr'], fallback: _s(data['productUr'], fallback: '')),
            fallback: '',
          );
          final location = [
            _safeLabel(data['city'], fallback: ''),
            _safeLabel(data['district'], fallback: ''),
            _safeLabel(data['province'], fallback: ''),
          ].where((e) => e.isNotEmpty).join(', ');
          final conditionNote = _safeLabel(
            _s(data['quality'], fallback: _s(data['conditionNote'], fallback: _s(data['condition']))),
            fallback: 'Not provided',
          );
          final qtyValue = qty > 0
              ? '${qty.toStringAsFixed(0)} ${_safeLabel(unit, fallback: 'units')}'
              : 'Not available';
          final rateValue = price > 0 ? _formatMoney(price) : 'Not available';
          final estValue = (qty > 0 && price > 0)
              ? _formatMoney(qty * price)
              : 'Not available';

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
            children: [
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _sectionTitle(
                            'Admin Listing Detail',
                            'Listing Operations',
                          ),
                        ),
                        _statusBadge(
                          _moderationChipText(data),
                          _statusColor(statusText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      itemName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (itemNameUr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          itemNameUr,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _kv('Listing ID', widget.listingId, subtle: true),
                    _kv('Category', _humanizeCategory(data), subtle: true),
                    _kv('Quantity', qtyValue),
                    _kv('Rate', rateValue),
                    _kv('Estimated Value', estValue),
                    _kv(
                      'Location',
                      location.isEmpty ? 'Not available' : location,
                      subtle: true,
                    ),
                    _kv('Condition', conditionNote, subtle: true),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusBadge(
                          _moderationChipText(data),
                          _statusColor(statusText),
                        ),
                        _statusBadge(
                          _auctionChipText(auctionText),
                          _auctionColor(auctionText),
                        ),
                        _statusBadge(
                          _promotionChipText(promoText),
                          _promoColor(promoText),
                        ),
                        _statusBadge(
                          _outcomeChipText(dealOutcomeStatus),
                          _statusColor(dealOutcomeStatus),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv('Winner', _safeLabel(winnerId, fallback: 'Not decided'), subtle: true),
                    _kv(
                      'Accepted Bid',
                      _safeLabel(acceptedBidId, fallback: 'Not available'),
                      subtle: true,
                    ),
                    _kv(
                      'Market Data',
                      marketAvg > 0
                          ? '${_formatMoney(marketAvg)} | Delta ${deviation.toStringAsFixed(1)}%'
                          : 'Market data not available',
                      subtle: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _loadSellerProfile(sellerUid),
                  builder: (context, sellerSnap) {
                    final seller = sellerSnap.data ?? <String, dynamic>{};
                    final sellerName = _safeLabel(
                      _s(
                        seller['fullName'],
                        fallback: _s(
                          seller['name'],
                          fallback: _s(data['sellerName'], fallback: ''),
                        ),
                      ),
                      fallback: 'Unknown user',
                    );
                    final sellerPhone = _safeLabel(
                      _s(
                        seller['phone'],
                        fallback: _s(data['sellerPhone'], fallback: ''),
                      ),
                      fallback: 'Not available',
                    );
                    final sellerCity = _safeLabel(
                      _s(
                        seller['city'],
                        fallback: _s(data['city'], fallback: ''),
                      ),
                      fallback: '',
                    );
                    final sellerDistrict = _safeLabel(
                      _s(
                        seller['district'],
                        fallback: _s(data['district'], fallback: ''),
                      ),
                      fallback: '',
                    );
                    final sellerProvince = _safeLabel(
                      _s(
                        seller['province'],
                        fallback: _s(data['province'], fallback: ''),
                      ),
                      fallback: '',
                    );
                    final sellerLocation = [
                      sellerCity,
                      sellerDistrict,
                      sellerProvince,
                    ].where((e) => e.isNotEmpty).join(', ');
                    final verified = seller['isVerified'] == true ||
                        seller['verified'] == true;
                    final approved = seller['isApproved'] == true ||
                        seller['approvalStatus'] == 'approved';
                    final role = _safeLabel(
                      _s(
                        seller['role'],
                        fallback: _s(seller['userType'], fallback: 'seller'),
                      ),
                      fallback: 'seller',
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('Seller Identity', 'Primary account details'),
                        const SizedBox(height: 10),
                        _kv('Seller', sellerName),
                        _kv('Phone', sellerPhone),
                        _kv(
                          'Location',
                          sellerLocation.isEmpty ? 'Not available' : sellerLocation,
                          subtle: true,
                        ),
                        _kv('Verification', verified ? 'Verified' : 'Not verified', subtle: true),
                        _kv('Approval', approved ? 'Approved' : 'Not approved', subtle: true),
                        _kv('Role', role, subtle: true),
                        _kv('UID', _safeLabel(sellerUid, fallback: 'Not available'), subtle: true),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Moderation Actions', 'Primary moderation controls'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _action(
                          'Approve Listing',
                          Colors.green,
                          actionKey: 'approve_listing',
                          enabled: canApprove,
                          onTap: () => _runAction(
                            actionKey: 'approve_listing',
                            failedMessage:
                                'Could not approve listing. Please retry.',
                            failureAction: 'approve_listing',
                            targetId: widget.listingId,
                            action: _approveListing,
                            successMessage: 'Listing approved successfully',
                          ),
                        ),
                        _action(
                          'Reject Listing',
                          Colors.redAccent,
                          actionKey: 'reject_listing',
                          onTap: () async {
                            final ok = await _confirmDangerAction(
                              title: 'Reject Listing?',
                              body:
                                  'This listing will be marked rejected and removed from approval flow.',
                              irreversibleText:
                                  'Reversal is operationally sensitive and should be avoided.',
                              confirmLabel: 'Reject',
                            );
                            if (!ok) return;
                            final notes = await _askNotes(
                              'Reject listing note',
                              required: true,
                              hint: 'Policy reason for rejection',
                            );
                            if (notes == null || notes.trim().isEmpty) return;
                            await _runAction(
                              actionKey: 'reject_listing',
                              failedMessage:
                                  'Could not reject listing. Please retry.',
                              failureAction: 'reject_listing',
                              targetId: widget.listingId,
                              action: () => _rejectListing(notes),
                              successMessage: 'Listing rejected',
                            );
                          },
                        ),
                        _action(
                          'Request Changes',
                          Colors.orange,
                          actionKey: 'request_changes',
                          onTap: () async {
                            final notes = await _askNotes(
                              'Request changes note',
                              required: true,
                              hint: 'Tell seller what to update',
                            );
                            if (notes == null || notes.trim().isEmpty) return;
                            await _runAction(
                              actionKey: 'request_changes',
                              failedMessage:
                                  'Could not request changes. Please retry.',
                              failureAction: 'request_changes',
                              targetId: widget.listingId,
                              action: () => _requestChanges(notes),
                              successMessage: 'Changes requested',
                            );
                          },
                        ),
                        _action(
                          'View Full Details',
                          Colors.blueGrey,
                          actionKey: 'view_full_details',
                          onTap: () => _showFullDetails(data),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Auction Control', 'Auction state and operations'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusBadge(_auctionChipText(auctionText), _auctionColor(auctionText)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _actionWithHint(
                          'Start Auction',
                          Colors.blue,
                          actionKey: 'start_auction',
                          enabled: canStartAuction,
                          helperText: _auctionDisabledHint(
                            action: 'start',
                            canStartAuction: canStartAuction,
                            canPauseAuction: canPauseAuction,
                            canResumeAuction: canResumeAuction,
                            canCancelAuction: canCancelAuction,
                            canExtendAuction: canExtendAuction,
                            auctionLower: auctionLower,
                          ),
                          onTap: () => _runAction(
                            actionKey: 'start_auction',
                            failedMessage: 'Could not start auction. Please retry.',
                            failureAction: 'start_auction',
                            targetId: widget.listingId,
                            action: _startAuction,
                            successMessage: 'Auction started',
                          ),
                        ),
                        _actionWithHint(
                          'Pause Auction',
                          Colors.amber,
                          actionKey: 'pause_auction',
                          enabled: canPauseAuction,
                          helperText: _auctionDisabledHint(
                            action: 'pause',
                            canStartAuction: canStartAuction,
                            canPauseAuction: canPauseAuction,
                            canResumeAuction: canResumeAuction,
                            canCancelAuction: canCancelAuction,
                            canExtendAuction: canExtendAuction,
                            auctionLower: auctionLower,
                          ),
                          onTap: () => _runAction(
                            actionKey: 'pause_auction',
                            failedMessage: 'Could not pause auction. Please retry.',
                            failureAction: 'pause_auction',
                            targetId: widget.listingId,
                            action: _pauseAuction,
                            successMessage: 'Auction paused',
                          ),
                        ),
                        _actionWithHint(
                          'Resume Auction',
                          Colors.teal,
                          actionKey: 'resume_auction',
                          enabled: canResumeAuction,
                          helperText: _auctionDisabledHint(
                            action: 'resume',
                            canStartAuction: canStartAuction,
                            canPauseAuction: canPauseAuction,
                            canResumeAuction: canResumeAuction,
                            canCancelAuction: canCancelAuction,
                            canExtendAuction: canExtendAuction,
                            auctionLower: auctionLower,
                          ),
                          onTap: () => _runAction(
                            actionKey: 'resume_auction',
                            failedMessage: 'Could not resume auction. Please retry.',
                            failureAction: 'resume_auction',
                            targetId: widget.listingId,
                            action: _resumeAuction,
                            successMessage: 'Auction resumed',
                          ),
                        ),
                        _actionWithHint(
                          'Extend +2h',
                          Colors.indigo,
                          actionKey: 'extend_auction',
                          enabled: canExtendAuction,
                          helperText: _auctionDisabledHint(
                            action: 'extend',
                            canStartAuction: canStartAuction,
                            canPauseAuction: canPauseAuction,
                            canResumeAuction: canResumeAuction,
                            canCancelAuction: canCancelAuction,
                            canExtendAuction: canExtendAuction,
                            auctionLower: auctionLower,
                          ),
                          onTap: () => _runAction(
                            actionKey: 'extend_auction',
                            failedMessage: 'Could not extend auction. Please retry.',
                            failureAction: 'extend_auction',
                            targetId: widget.listingId,
                            action: _extendAuction,
                            successMessage: 'Auction extended by 2 hours',
                          ),
                        ),
                        _actionWithHint(
                          'Cancel Auction',
                          Colors.redAccent,
                          actionKey: 'cancel_auction',
                          enabled: canCancelAuction,
                          helperText: _auctionDisabledHint(
                            action: 'cancel',
                            canStartAuction: canStartAuction,
                            canPauseAuction: canPauseAuction,
                            canResumeAuction: canResumeAuction,
                            canCancelAuction: canCancelAuction,
                            canExtendAuction: canExtendAuction,
                            auctionLower: auctionLower,
                          ),
                          onTap: () => _runAction(
                            actionKey: 'cancel_auction',
                            failedMessage: 'Could not cancel auction. Please retry.',
                            failureAction: 'cancel_auction',
                            targetId: widget.listingId,
                            action: () async {
                              final ok = await _confirmDangerAction(
                                title: 'Cancel Auction?',
                                body:
                                    'Auction participation will stop and this listing will no longer accept bids.',
                                confirmLabel: 'Cancel Auction',
                              );
                              if (!ok) return;
                              final note = await _askNotes(
                                'Cancel auction reason',
                                required: true,
                                hint: 'Policy or operational reason',
                              );
                              if (note == null) return;
                              await _cancelAuction(note);
                            },
                            successMessage: 'Auction cancelled',
                          ),
                        ),
                        _action(
                          'Finalize Auction',
                          Colors.deepPurple,
                          actionKey: 'finalize_auction',
                          onTap: () async {
                            final ok = await _confirmDangerAction(
                              title: 'Finalize Auction?',
                              body:
                                  'Finalization settles the auction result and should be done only when all checks are complete.',
                              confirmLabel: 'Finalize',
                            );
                            if (!ok) return;
                            await _runAction(
                              actionKey: 'finalize_auction',
                              failedMessage:
                                  'Could not finalize auction. Please retry.',
                              failureAction: 'finalize_auction',
                              targetId: widget.listingId,
                              action: _finalizeAuctionNow,
                              successMessage: 'Auction finalized',
                            );
                          },
                        ),
                        _action(
                          'Outcome: Successful',
                          Colors.green.shade700,
                          actionKey: 'outcome_successful',
                          onTap: () async {
                            final ok = await _confirmDangerAction(
                              title: 'Set Outcome Successful?',
                              body:
                                  'Use this only when the deal has been completed and payment/fulfillment is verified.',
                              confirmLabel: 'Set Successful',
                            );
                            if (!ok) return;
                            await _runAction(
                              actionKey: 'outcome_successful',
                              failedMessage:
                                  'Could not update outcome. Please retry.',
                              failureAction: 'update_deal_outcome_successful',
                              targetId: widget.listingId,
                              action: () => _markDealOutcomeAdmin('successful'),
                              successMessage: 'Outcome set to successful',
                            );
                          },
                        ),
                        _action(
                          'Outcome: Failed',
                          Colors.brown,
                          actionKey: 'outcome_failed',
                          onTap: () async {
                            final ok = await _confirmDangerAction(
                              title: 'Set Outcome Failed?',
                              body:
                                  'This marks the deal as failed and can impact seller and buyer trust records.',
                              confirmLabel: 'Set Failed',
                            );
                            if (!ok) return;
                            await _runAction(
                              actionKey: 'outcome_failed',
                              failedMessage:
                                  'Could not update outcome. Please retry.',
                              failureAction: 'update_deal_outcome_failed',
                              targetId: widget.listingId,
                              action: () => _markDealOutcomeAdmin('failed'),
                              successMessage: 'Outcome set to failed',
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Promotion Control', 'Promotion payment and activation'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _action(
                          'Payment Under Review',
                          Colors.orange,
                          actionKey: 'promo_under_review',
                          onTap: () => _runAction(
                            actionKey: 'promo_under_review',
                            failedMessage:
                                'Could not mark payment under review. Please retry.',
                            failureAction: 'promotion_payment_under_review',
                            targetId: widget.listingId,
                            action: () async {
                              final note = await _askNotes(
                                'Request better promotion proof',
                                required: true,
                                hint: 'Receipt mismatch or missing details',
                              );
                              if (note == null) return;
                              await _setPromotionStatus(
                                'pending_review',
                                note: note,
                              );
                            },
                            successMessage: 'Promotion marked under review',
                          ),
                        ),
                        _action(
                          'Approve Promotion',
                          Colors.green,
                          actionKey: 'promo_approved',
                          onTap: () => _runAction(
                            actionKey: 'promo_approved',
                            failedMessage:
                                'Could not approve promotion. Please retry.',
                            failureAction: 'approve_promotion',
                            targetId: widget.listingId,
                            action: () => _setPromotionStatus('approved'),
                            successMessage: 'Promotion approved',
                          ),
                        ),
                        _action(
                          'Reject Promotion',
                          Colors.red,
                          actionKey: 'promo_rejected',
                          onTap: () => _runAction(
                            actionKey: 'promo_rejected',
                            failedMessage:
                                'Could not reject promotion. Please retry.',
                            failureAction: 'reject_promotion',
                            targetId: widget.listingId,
                            action: () async {
                              final note = await _askNotes(
                                'Reject promotion reason',
                                required: true,
                                hint: 'Invalid or incomplete payment proof',
                              );
                              if (note == null) return;
                              await _setPromotionStatus('rejected', note: note);
                            },
                            successMessage: 'Promotion rejected',
                          ),
                        ),
                        _action(
                          'Activate Promotion',
                          Colors.blue,
                          actionKey: 'promo_active',
                          onTap: () => _runAction(
                            actionKey: 'promo_active',
                            failedMessage:
                                'Could not activate promotion. Please retry.',
                            failureAction: 'activate_promotion',
                            targetId: widget.listingId,
                            action: () => _setPromotionStatus('active'),
                            successMessage: 'Promotion activated',
                          ),
                        ),
                        _action(
                          'Deactivate Promotion',
                          Colors.grey,
                          actionKey: 'promo_expired',
                          onTap: () => _runAction(
                            actionKey: 'promo_expired',
                            failedMessage:
                                'Could not deactivate promotion. Please retry.',
                            failureAction: 'deactivate_promotion',
                            targetId: widget.listingId,
                            action: () => _setPromotionStatus('expired'),
                            successMessage: 'Promotion deactivated',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Payment Ref: ${_safeLabel(_s(data['promotionPaymentReference'], fallback: _s(data['paymentReference'])), fallback: 'Not available')}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Requested At: ${_formatDateTime(data['promotionRequestedAt'])}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Status: ${_promotionChipText(promoText)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Media / Evidence', 'Listing proof assets'),
                    const SizedBox(height: 10),
                    Text(
                      'Photos: ${imageUrls.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    if (imageUrls.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Text(
                          'No photos provided.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else if (imageUrls.length == 1)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrls.first,
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 220,
                            color: Colors.black26,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imageUrls.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrls[index],
                              width: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 120,
                                    color: Colors.black26,
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.white70,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    _kv(
                      'Trust Photo',
                      trustPhotoUrl.isNotEmpty ? 'Provided' : 'Not provided',
                      subtle: true,
                    ),
                    _kv(
                      'Video',
                      videoUrl.isNotEmpty ? 'Provided' : 'Not provided',
                      subtle: true,
                    ),
                    _kv(
                      'Audio',
                      audioUrl.isNotEmpty ? 'Provided' : 'Not provided',
                      subtle: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _db
                      .collection('listings')
                      .doc(widget.listingId)
                      .collection('bids')
                      .orderBy('timestamp', descending: true)
                      .limit(20)
                      .snapshots(),
                  builder: (context, bidSnap) {
                    final bids =
                        bidSnap.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    if (bids.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Bids / Auction Activity',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No bids yet',
                            style: TextStyle(color: Colors.white70),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Bidding activity will appear here once buyers start placing bids.',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bids',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...bids.map((doc) {
                          final bid = doc.data();
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${_formatMoney(_n(bid['bidAmount']))}  |  ${_safeLabel(_s(bid['buyerName'], fallback: _s(bid['buyerId'])), fallback: 'Unknown buyer')}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Status: ${_titleCase(_s(bid['status'], fallback: 'pending'))} | ${_formatDateTime(bid['timestamp'])}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _statusColor(String value) {
    final v = value.toLowerCase();
    if (v == 'active' || v == 'approved' || v == 'live') {
      return const Color(0xFF2FCB8F);
    }
    if (v == 'rejected' || v == 'cancelled') return Colors.redAccent;
    if (v == 'pending' || v.contains('review')) return Colors.orangeAccent;
    return Colors.blueGrey;
  }

  Color _auctionColor(String value) {
    final v = value.toLowerCase();
    if (v == 'live') return const Color(0xFF2FCB8F);
    if (v == 'paused') return Colors.orangeAccent;
    if (v == 'cancelled' || v == 'ended') return Colors.redAccent;
    return Colors.blueGrey;
  }

  Color _promoColor(String value) {
    final v = value.toLowerCase();
    if (v == 'active' || v == 'approved') return const Color(0xFF2FCB8F);
    if (v == 'rejected' || v == 'expired') return Colors.redAccent;
    if (v.contains('pending') || v.contains('review')) {
      return Colors.orangeAccent;
    }
    return Colors.blueGrey;
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.95)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _action(
    String label,
    Color color, {
    required String actionKey,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final isLoading = _isActionLoading(actionKey);
    return ElevatedButton(
      onPressed: (isLoading || !enabled) ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(120, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        disabledBackgroundColor: color.withValues(alpha: 0.45),
      ),
      child: isLoading
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_panelColor, Color(0xFF163357)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
