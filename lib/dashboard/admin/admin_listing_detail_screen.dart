import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/admin_action_service.dart';
import '../../services/auction_lifecycle_service.dart';

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
    _diag('action_tap action=$failureAction target=listings/$targetId');
    setState(() => _loadingActions.add(actionKey));
    try {
      await action();
      if (!mounted) return;
      if (successMessage != null && successMessage.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failedMessage)));
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
    await _db.collection('notifications').add({
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'routeName': 'buyer_listing_detail',
      'routeParams': {'listingId': widget.listingId},
      'listingId': widget.listingId,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
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
      await _writeRevenueLedger(
        entryType: 'promotion_$status',
        sellerId: sellerId,
        amount: amount,
        revenueCategory: promoType,
        status: status,
        notes: note.trim().isEmpty ? 'Promotion $status' : note.trim(),
        markApproved: status == 'approved' || status == 'active',
      );

      final listingName = _s(
        current['itemName'],
        fallback: _s(current['product'], fallback: 'Listing'),
      );
      final userFacingStatus = status == 'pending_review'
          ? 'under review'
          : status;
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
    }

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

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
            children: [
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s(
                        data['itemName'],
                        fallback: _s(data['product'], fallback: 'Listing'),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Listing ID: ${widget.listingId}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Category: ${_s(data['categoryLabel'], fallback: _s(data['category']))} > ${_s(data['subcategoryLabel'], fallback: _s(data['subcategory']))} > ${_s(data['variety'])}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Qty: ${qty.toStringAsFixed(0)} $unit   Rate: Rs ${price.toStringAsFixed(0)}   Value: Rs ${(qty * price).toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Location: ${_s(data['province'])}, ${_s(data['district'])}, ${_s(data['tehsil'])}, ${_s(data['city'], fallback: _s(data['village'], fallback: _s(data['location'])))}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusBadge(statusText, _statusColor(statusText)),
                        _statusBadge(
                          'Auction: $auctionText',
                          _auctionColor(auctionText),
                        ),
                        _statusBadge(
                          'Promotion: $promoText',
                          _promoColor(promoText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Seller: ${_s(data['sellerName'], fallback: _s(data['sellerId']))}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Winner: $winnerId',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Accepted Bid: $acceptedBidId',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Deal Outcome: $dealOutcomeStatus',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      marketAvg > 0
                          ? 'Market Avg: Rs ${marketAvg.toStringAsFixed(0)} | Delta: ${deviation.toStringAsFixed(1)}%'
                          : 'Market Avg: unavailable',
                      style: TextStyle(
                        color: marketAvg > 0 && deviation.abs() > 20
                            ? Colors.redAccent
                            : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _s(data['description']),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Wrap(
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
                      Colors.red,
                      actionKey: 'reject_listing',
                      onTap: () async {
                        final notes = await _askNotes('Reject listing note');
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
                        final notes = await _askNotes('Request changes note');
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
                      'Start Auction',
                      Colors.blue,
                      actionKey: 'start_auction',
                      enabled: canStartAuction,
                      onTap: () => _runAction(
                        actionKey: 'start_auction',
                        failedMessage: 'Could not start auction. Please retry.',
                        failureAction: 'start_auction',
                        targetId: widget.listingId,
                        action: _startAuction,
                        successMessage: 'Auction started',
                      ),
                    ),
                    _action(
                      'Pause Auction',
                      Colors.amber,
                      actionKey: 'pause_auction',
                      enabled: canPauseAuction,
                      onTap: () => _runAction(
                        actionKey: 'pause_auction',
                        failedMessage: 'Could not pause auction. Please retry.',
                        failureAction: 'pause_auction',
                        targetId: widget.listingId,
                        action: _pauseAuction,
                        successMessage: 'Auction paused',
                      ),
                    ),
                    _action(
                      'Resume Auction',
                      Colors.teal,
                      actionKey: 'resume_auction',
                      enabled: canResumeAuction,
                      onTap: () => _runAction(
                        actionKey: 'resume_auction',
                        failedMessage:
                            'Could not resume auction. Please retry.',
                        failureAction: 'resume_auction',
                        targetId: widget.listingId,
                        action: _resumeAuction,
                        successMessage: 'Auction resumed',
                      ),
                    ),
                    _action(
                      'Cancel Auction',
                      Colors.redAccent,
                      actionKey: 'cancel_auction',
                      enabled: canCancelAuction,
                      onTap: () => _runAction(
                        actionKey: 'cancel_auction',
                        failedMessage:
                            'Could not cancel auction. Please retry.',
                        failureAction: 'cancel_auction',
                        targetId: widget.listingId,
                        action: () async {
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
                      'Extend +2h',
                      Colors.indigo,
                      actionKey: 'extend_auction',
                      enabled: canExtendAuction,
                      onTap: () => _runAction(
                        actionKey: 'extend_auction',
                        failedMessage:
                            'Could not extend auction. Please retry.',
                        failureAction: 'extend_auction',
                        targetId: widget.listingId,
                        action: _extendAuction,
                        successMessage: 'Auction extended by 2 hours',
                      ),
                    ),
                    _action(
                      'Finalize Auction',
                      Colors.deepPurple,
                      actionKey: 'finalize_auction',
                      onTap: () => _runAction(
                        actionKey: 'finalize_auction',
                        failedMessage:
                            'Could not finalize auction. Please retry.',
                        failureAction: 'finalize_auction',
                        targetId: widget.listingId,
                        action: _finalizeAuctionNow,
                        successMessage: 'Auction finalized',
                      ),
                    ),
                    _action(
                      'Outcome: Successful',
                      Colors.green.shade700,
                      actionKey: 'outcome_successful',
                      onTap: () => _runAction(
                        actionKey: 'outcome_successful',
                        failedMessage:
                            'Could not update outcome. Please retry.',
                        failureAction: 'update_deal_outcome_successful',
                        targetId: widget.listingId,
                        action: () => _markDealOutcomeAdmin('successful'),
                        successMessage: 'Outcome set to successful',
                      ),
                    ),
                    _action(
                      'Outcome: Failed',
                      Colors.brown,
                      actionKey: 'outcome_failed',
                      onTap: () => _runAction(
                        actionKey: 'outcome_failed',
                        failedMessage:
                            'Could not update outcome. Please retry.',
                        failureAction: 'update_deal_outcome_failed',
                        targetId: widget.listingId,
                        action: () => _markDealOutcomeAdmin('failed'),
                        successMessage: 'Outcome set to failed',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Promotion Control',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                      'Payment Ref: ${_s(data['promotionPaymentReference'], fallback: _s(data['paymentReference']))}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Requested At: ${_s(data['promotionRequestedAt'])}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (imageUrls.isNotEmpty)
                _panel(
                  child: SizedBox(
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
                ),
              if (videoUrl.isNotEmpty || audioUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _panel(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (trustPhotoUrl.isNotEmpty)
                          _statusBadge(
                            'Trust photo available',
                            Colors.greenAccent,
                          ),
                        if (videoUrl.isNotEmpty)
                          _statusBadge('Video available', Colors.blueAccent),
                        if (audioUrl.isNotEmpty)
                          _statusBadge(
                            'Audio note available',
                            Colors.orangeAccent,
                          ),
                      ],
                    ),
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
                      return const Row(
                        children: [
                          Icon(
                            Icons.hourglass_empty_rounded,
                            color: Colors.white54,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'No bids yet.',
                            style: TextStyle(color: Colors.white70),
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
                              'Rs ${_n(bid['bidAmount']).toStringAsFixed(0)}  |  ${_s(bid['buyerName'], fallback: _s(bid['buyerId']))}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Status: ${_s(bid['status'])}',
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
