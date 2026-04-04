import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../config/promotion_payment_config.dart';
import '../../core/seasonal_bakra_mandi_config.dart';
import '../../routes.dart';
import '../../services/admin_action_service.dart';
import '../../services/auth_service.dart';
import '../../services/layer2_market_intelligence_service.dart';
import '../../services/phase1_notification_engine.dart';
import '../../services/session_service.dart';
import 'admin_listing_detail_screen.dart';

class _AdminUiException implements Exception {
  const _AdminUiException(this.message);

  final String message;
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF0B1F3A);
  static const Color _panelColor = Color(0xFF122B4A);
  static const Color _gold = Color(0xFFFFD700);
  static const Color _green = Color(0xFF2FCB8F);
  static const Color _blue = Color(0xFF4B86F8);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AdminActionService _adminActions = AdminActionService();
  final AuthService _authService = AuthService();
  final Layer2MarketIntelligenceService _layer2MarketService =
      Layer2MarketIntelligenceService();
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();
  late final TabController _tabs;
  final Set<String> _loadingActions = <String>{};
  final Set<String> _hiddenModerationIds = <String>{};
  final Map<String, String> _auctionStatusOverrides = <String, String>{};
  late Future<AdminMarketInsightsResult> _adminInsightsFuture;
  bool _adminBootRouteLogged = false;
  bool _adminBootRenderableLogged = false;
  bool _bakraMandiEnabled = SeasonalBakraMandiConfig.showBakraMandi;
  StreamSubscription<bool>? _bakraToggleSubscription;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _adminBoot('routeEntered=true');
    _adminBootRouteLogged = true;
    _adminBoot('loadingWidget=AdminDashboardShell');
    _adminInsightsFuture = _loadAdminInsightsSafely(source: 'initState');
    unawaited(_hydrateBakraToggle());
    _listenBakraToggle();
  }

  void _adminBoot(String message) {
    debugPrint('[ADMIN_BOOT] $message');
  }

  Future<AdminMarketInsightsResult> _loadAdminInsightsSafely({
    required String source,
  }) async {
    _adminBoot('serviceStart=$source');
    try {
      final result = await _layer2MarketService.buildAdminMarketInsights();
      _adminBoot('fallbackUsed=false');
      return result;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        _adminBoot('serviceError=permission-denied source=$source');
      } else {
        _adminBoot('serviceError=${error.code} source=$source');
      }
      _adminBoot('fallbackUsed=true');
      return const AdminMarketInsightsResult(
        topRisingCrops: <String>[],
        topFallingCrops: <String>[],
        highDemandCategories: <String>[],
      );
    } catch (_) {
      _adminBoot('serviceError=unknown source=$source');
      _adminBoot('fallbackUsed=true');
      return const AdminMarketInsightsResult(
        topRisingCrops: <String>[],
        topFallingCrops: <String>[],
        highDemandCategories: <String>[],
      );
    }
  }

  Future<void> _hydrateBakraToggle() async {
    final persisted = await SeasonalBakraMandiConfig.loadRuntimeVisibility();
    if (!mounted) return;
    setState(() {
      _bakraMandiEnabled = persisted;
    });
  }

  void _listenBakraToggle() {
    _bakraToggleSubscription?.cancel();
    _bakraToggleSubscription = SeasonalBakraMandiConfig.visibilityStream()
        .listen((value) {
          if (!mounted) return;
          setState(() {
            _bakraMandiEnabled = value;
          });
        });
  }

  void _refreshAdminInsights() {
    setState(() {
      _adminInsightsFuture = _loadAdminInsightsSafely(
        source: 'manual_refresh',
      );
    });
  }

  @override
  void dispose() {
    _bakraToggleSubscription?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  String _s(dynamic v, {String fallback = '-'}) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  bool _b(dynamic v) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString()) ?? 0;
  }

  void _diag(String message) {
    debugPrint('[AdminDashboard] $message');
  }

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _s(data[key], fallback: '');
      if (value.isNotEmpty) return value;
    }
    final media = data['mediaMetadata'];
    if (media is Map) {
      for (final key in keys) {
        final value = _s(media[key], fallback: '');
        if (value.isNotEmpty) return value;
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

  String _videoUrl(Map<String, dynamic> data) {
    final direct = _firstText(data, const [
      'videoUrl',
      'verificationVideoUrl',
      'videoURL',
      'mediaVideoUrl',
    ]);
    if (direct.isNotEmpty) return direct;
    final media = data['mediaMetadata'];
    if (media is Map) {
      final verification = media['verificationVideo'];
      if (verification is Map) {
        final nested = _s(verification['url'], fallback: '');
        if (nested.isNotEmpty) return nested;
      }
    }
    return '';
  }

  String _audioUrl(Map<String, dynamic> data) {
    final direct = _firstText(data, const ['audioUrl', 'voiceUrl', 'audioURL']);
    if (direct.isNotEmpty) return direct;
    final media = data['mediaMetadata'];
    if (media is Map) {
      final nested = _s(media['audioUrl'], fallback: '');
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  String _promo(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'promotion_pending_payment') return 'pending_review';
    if (s == 'payment_under_review') return 'pending_review';
    if (s == 'pending_payment') return 'pending_review';
    return s.isEmpty ? 'none' : s;
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _promoStatusForMetrics(Map<String, dynamic> data) {
    final status = _promo(_s(data['promotionStatus'], fallback: 'none'));
    if (status == 'active') {
      final expiresAt = _toDate(data['promotionExpiresAt']);
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        return 'expired';
      }
    }
    return status;
  }

  bool _needsModeration(Map<String, dynamic> d) {
    final status = _s(d['status']).toLowerCase();
    return !_b(d['isApproved']) ||
        status == 'pending' ||
        status == 'review' ||
        status == 'under_review' ||
        status == 'pending_verification';
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

  String _formatAdminDateTime(dynamic value) {
    final DateTime? dt = _toDate(value);
    if (dt == null) {
      final String raw = (value ?? '').toString().trim();
      return raw.isEmpty ? 'Not available' : raw;
    }
    final DateTime local = dt.toLocal();
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    final String h = local.hour.toString().padLeft(2, '0');
    final String min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$m-$d $h:$min';
  }

  String _displayField(dynamic value, {String fallback = 'Not available'}) {
    final String text = (value ?? '').toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }
    return text;
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

  Future<void> _traceFailure({
    required String action,
    required String targetCollection,
    required String targetId,
    required Object error,
    String? previousStatus,
    String? intendedStatus,
    String notes = '',
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    await _db.collection('admin_action_logs').add({
      'entityType': targetCollection == 'users' ? 'user' : 'listing',
      'entityId': targetId,
      'actionType': action,
      'actionBy': admin?.uid ?? 'admin',
      'actionByEmail': admin?.email ?? '',
      'actionByName': admin?.displayName ?? '',
      'actionAt': FieldValue.serverTimestamp(),
      'notes': notes,
      'targetCollection': targetCollection,
      'targetDocId': targetId,
      'previousStatus': previousStatus,
      'intendedStatus': intendedStatus,
      'error': _safeError(error),
      'result': 'failed',
    });
  }

  Future<Map<String, dynamic>> _loadListing(String id) async {
    final snap = await _db.collection('listings').doc(id).get();
    if (!snap.exists) {
      throw const _AdminUiException('Listing not found');
    }
    return snap.data() ?? <String, dynamic>{};
  }

  Future<String?> _askAdminNote(
    String title, {
    String hint = 'Add admin note',
    bool required = false,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? localError;
        return StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: hint,
                    errorText: localError,
                  ),
                ),
              ],
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
                      localError = 'Admin note is required';
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

  Future<void> _notifyUser({
    required String userId,
    required String type,
    required String title,
    required String body,
    required String titleUr,
    required String bodyUr,
    String? listingId,
    Map<String, dynamic>? metadata,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedListingId = (listingId ?? '').trim();
    final normalizedType = type.trim().toUpperCase();
    if (normalizedUserId.isEmpty || normalizedListingId.isEmpty) {
      debugPrint(
        '[NotifWrite] skipped_invalid_payload type=$normalizedType toUid=$normalizedUserId listingId=$normalizedListingId',
      );
      return;
    }

    final bool isRuleSupported = Phase1NotificationType.all.contains(
      normalizedType,
    );
    if (!isRuleSupported) {
      debugPrint(
        '[NotifWrite] skipped_unsupported_type type=$normalizedType toUid=$normalizedUserId listingId=$normalizedListingId',
      );
      return;
    }

    final roleHint = (metadata?['targetRole'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final targetRole = roleHint.isEmpty ? 'seller' : roleHint;
    await _phase1Notifications.createOnce(
      userId: normalizedUserId,
      type: normalizedType,
      listingId: normalizedListingId,
      titleEn: title,
      bodyEn: body,
      titleUr: titleUr,
      bodyUr: bodyUr,
      targetRole: targetRole,
    );
  }

  Future<void> _writeRevenueLedger({
    required String entryType,
    required String listingId,
    required String sellerId,
    required double amount,
    required String revenueCategory,
    required String status,
    required String notes,
    bool markApproved = false,
  }) async {
    await _db.collection('revenue_ledger').add({
      'entryType': entryType,
      'sourceListingId': listingId,
      'sellerId': sellerId,
      'amount': amount,
      'revenueCategory': revenueCategory,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'approvedAt': markApproved ? FieldValue.serverTimestamp() : null,
      'notes': notes,
    });
  }

  Future<void> _log(
    String entityType,
    String entityId,
    String action, {
    String notes = '',
    String? previousStatus,
    String? newStatus,
    String? previousAuctionStatus,
    String? newAuctionStatus,
    String? previousPromotionStatus,
    String? newPromotionStatus,
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    final uid = admin?.uid ?? 'admin';
    final ts = FieldValue.serverTimestamp();
    final target = entityType == 'user' ? 'users' : 'listings';
    await _db.collection('admin_action_logs').add({
      'entityType': entityType,
      'entityId': entityId,
      'actionType': action,
      'actionBy': uid,
      'actionByEmail': admin?.email ?? '',
      'actionByName': admin?.displayName ?? '',
      'actionAt': ts,
      'notes': notes,
      'reason': notes,
      'targetCollection': target,
      'targetDocId': entityId,
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
    await _db.collection(target).doc(entityId).set({
      'lastAdminAction': {
        'actionType': action,
        'actionBy': uid,
        'actionAt': ts,
        'notes': notes,
      },
      'updatedAt': ts,
    }, SetOptions(merge: true));
  }

  bool _isActionLoading(String key) => _loadingActions.contains(key);

  Future<void> _runAction({
    required String key,
    required String failedMessage,
    required String failureAction,
    required String targetCollection,
    required String targetId,
    String? previousStatus,
    String? intendedStatus,
    required Future<void> Function() work,
    String? successMessage,
    VoidCallback? onSuccess,
  }) async {
    if (_isActionLoading(key)) return;
    final String firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    debugPrint('[ADMIN_ACTION] action=$failureAction');
    debugPrint('[ADMIN_ACTION] firebaseUid=$firebaseUid');
    debugPrint('[ADMIN_ACTION] docPath=$targetCollection/$targetId');
    debugPrint('[ADMIN_ACTION] payload={"actionKey":"$key"}');
    _diag(
      'action_tap action=$failureAction target=$targetCollection/$targetId',
    );
    setState(() => _loadingActions.add(key));
    try {
      final bool hasSession = await _authService.ensureFirebaseSessionForAdminWrite(
        flowLabel: 'admin_dashboard_$failureAction',
      );
      if (!hasSession) {
        throw const _AdminUiException(
          'Admin Firebase session is not active or lacks admin role. Please sign in again.',
        );
      }
      await work();
      debugPrint('[ADMIN_ACTION] errorCode=');
      debugPrint('[ADMIN_ACTION] errorMessage=');
      debugPrint('[ADMIN_ACTION] success=true');
      if (!mounted) return;
      onSuccess?.call();
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
        'action_failure action=$failureAction target=$targetCollection/$targetId error=${_safeError(error)}',
      );
      try {
        await _traceFailure(
          action: failureAction,
          targetCollection: targetCollection,
          targetId: targetId,
          error: error,
          previousStatus: previousStatus,
          intendedStatus: intendedStatus,
        );
      } catch (_) {
        _diag(
          'action_failure_log_write_failed action=$failureAction target=$targetCollection/$targetId',
        );
      }
      if (!mounted) return;
      final String failureText = _buildActionErrorMessage(
        failedMessage,
        error,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureText)),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingActions.remove(key));
      }
    }
  }

  Future<void> _approve(String id, {String note = ''}) async {
    final current = await _loadListing(id);
    _diag(
      'approve_listing start listing=$id status=${_status(current)} approved=${_b(current['isApproved'])}',
    );
    final status = _status(current);
    if (_b(current['isApproved']) && (status == 'active' || status == 'live')) {
      throw const _AdminUiException('Listing is already approved');
    }
    _diag(
      'approve_listing request_start listing=$id function=approveListingAdmin',
    );
    await _adminActions.approveListingAdminWithNote(listingId: id, note: note);
    final updated = await _db.collection('listings').doc(id).get();
    final um = updated.data() ?? <String, dynamic>{};
    final sellerUid = _s(um['sellerId'], fallback: '');
    if (sellerUid.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerUid,
        type: Phase1NotificationType.listingApproved,
        listingId: id,
        targetRole: 'seller',
      );
    }
    _diag(
      'approve_listing doc listing=$id isApproved=${um['isApproved']} status=${um['status']} listingStatus=${um['listingStatus']} auctionStatus=${um['auctionStatus']}',
    );
    _diag('approve_listing success listing=$id');
  }

  Future<void> _reject(String id, {required String note}) async {
    final current = await _loadListing(id);
    final status = _status(current);
    if (status == 'rejected') {
      throw const _AdminUiException('Listing is already rejected');
    }
    if (note.trim().isEmpty) {
      throw const _AdminUiException('Admin note is required to reject listing');
    }
    _diag(
      'reject_listing request_start listing=$id function=rejectListingAdmin',
    );
    await _adminActions.rejectListingAdmin(listingId: id, note: note);
    final updated = await _db.collection('listings').doc(id).get();
    final um = updated.data() ?? <String, dynamic>{};
    final sellerUid = _s(um['sellerId'], fallback: '');
    if (sellerUid.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerUid,
        type: Phase1NotificationType.listingRejected,
        listingId: id,
        targetRole: 'seller',
      );
    }
    _diag('reject_listing success listing=$id previousStatus=$status');
  }

  Future<void> _changes(String id, {required String note}) async {
    final current = await _loadListing(id);
    final status = _status(current);
    if (note.trim().isEmpty) {
      throw const _AdminUiException(
        'Admin note is required to request changes',
      );
    }
    _diag(
      'request_changes request_start listing=$id function=requestListingChangesAdmin',
    );
    await _adminActions.requestListingChangesAdmin(listingId: id, note: note);
    _diag('request_changes success listing=$id previousStatus=$status');
  }

  Future<void> _startAuction(String id, {String note = ''}) async {
    final current = await _loadListing(id);
    _diag(
      'start_auction tap listing=$id status=${_status(current)} auction=${_auctionStatus(current)}',
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
    _diag('start_auction request_start listing=$id function=startAuctionAdmin');
    await _adminActions.startAuctionAdmin(listingId: id, note: note);
    final updated = await _db.collection('listings').doc(id).get();
    final um = updated.data() ?? <String, dynamic>{};
    _diag(
      'start_auction doc listing=$id isApproved=${um['isApproved']} status=${um['status']} listingStatus=${um['listingStatus']} auctionStatus=${um['auctionStatus']}',
    );
    _diag('start_auction success listing=$id');
  }

  Future<void> _setAuction(String id, String status, {String note = ''}) async {
    final current = await _loadListing(id);
    final auction = _auctionStatus(current);
    if (status == 'paused' && auction != 'live') {
      throw _AdminUiException('Cannot pause auction while status is $auction');
    }
    if (status == 'live' && auction != 'paused') {
      throw _AdminUiException('Cannot resume auction while status is $auction');
    }
    if (status == 'cancelled' &&
        (auction == 'completed' || auction == 'cancelled')) {
      throw _AdminUiException('Cannot cancel auction while status is $auction');
    }
    if (status == 'paused') {
      _diag(
        'pause_auction request_start listing=$id function=pauseAuctionAdmin',
      );
      await _adminActions.pauseAuctionAdmin(listingId: id, note: note);
    }
    if (status == 'live') {
      _diag(
        'resume_auction request_start listing=$id function=resumeAuctionAdmin',
      );
      await _adminActions.resumeAuctionAdmin(listingId: id, note: note);
    }
    if (status == 'cancelled') {
      if (note.trim().isEmpty) {
        throw const _AdminUiException(
          'Admin note is required to cancel auction',
        );
      }
      _diag(
        'cancel_auction request_start listing=$id function=cancelAuctionAdmin',
      );
      await _adminActions.cancelAuctionAdmin(listingId: id, note: note);
    }
    _diag('${status}_auction success listing=$id previousAuction=$auction');
  }

  Future<void> _extend(String id, {String note = ''}) async {
    final current = await _loadListing(id);
    final auction = _auctionStatus(current);
    if (auction != 'live' && auction != 'paused') {
      throw _AdminUiException(
        'Can only extend live or paused auction, current: $auction',
      );
    }
    _diag(
      'extend_auction request_start listing=$id function=extendAuctionAdmin extensionHours=2',
    );
    await _adminActions.extendAuctionAdmin(
      listingId: id,
      extensionHours: 2,
      note: note,
    );
    _diag('extend_auction success listing=$id previousAuction=$auction');
  }

  Future<void> _promoStatus(
    String id,
    String status, {
    String note = '',
  }) async {
    final current = await _loadListing(id);
    final currentPromo = _promoStatusForMetrics(current);
    final promoType = _s(
      current['promotionType'],
      fallback: _b(current['featuredAuction'])
          ? 'featured_auction'
          : 'featured_listing',
    ).toLowerCase();
    final amount = _n(current['featuredCost']);
    if (status == currentPromo) {
      throw _AdminUiException('Promotion is already $status');
    }
    if (status == 'active' && currentPromo != 'approved') {
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
    final now = Timestamp.now();
    final updates = <String, dynamic>{
      'promotionStatus': status,
      'promotionType': promoType,
      'promotionReview': {
        'status': status,
        'reason': note.trim(),
        'updatedAt': now,
      },
      'promotionDecisionNote': note.trim(),
      'moderationReason': note.trim(),
      'promotionLastActionAt': now,
      'lastFinanceAction': {
        'actionType': 'promotion_$status',
        'note': note.trim(),
        'by': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        'at': now,
      },
    };
    if (status == 'pending_review') {
      updates['promotionReviewRequired'] = true;
      updates['promotionReviewAt'] = now;
    }
    if (status == 'approved') {
      updates['promotionReviewRequired'] = false;
      updates['promotionApprovedAt'] = now;
    }
    if (status == 'active') {
      updates['featured'] = true;
      updates['priorityScore'] = 'high';
      updates['promotionActivatedAt'] = now;
      updates['promotionStartsAt'] = (current['promotionStartsAt'] ?? now);
      updates['promotionExpiresAt'] =
          current['promotionExpiresAt'] ??
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 7)));
    }
    if (status == 'expired') {
      updates['featured'] = false;
      updates['featuredAuction'] = false;
      updates['priorityScore'] = 'normal';
      updates['promotionExpiredAt'] = now;
    }
    if (status == 'rejected') {
      updates['promotionRejectedAt'] = now;
      updates['promotionReviewRequired'] = false;
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
    debugPrint('[ADMIN_ACTION] docPath=listings/$id');
    debugPrint('[ADMIN_ACTION] payload=$updates');
    await _db
        .collection('listings')
        .doc(id)
        .set(updates, SetOptions(merge: true));

    final sellerId = _s(
      current['sellerId'],
      fallback: _s(
        current['ownerId'],
        fallback: _s(current['userId'], fallback: ''),
      ),
    );
    if (sellerId.isNotEmpty && sellerId != '-' && amount > 0) {
      final bool approvedEvent = status == 'approved' || status == 'active';
      try {
        await _writeRevenueLedger(
          entryType: 'promotion_$status',
          listingId: id,
          sellerId: sellerId,
          amount: amount,
          revenueCategory: promoType,
          status: status,
          notes: note.trim().isEmpty ? 'Promotion $status' : note.trim(),
          markApproved: approvedEvent,
        );
      } catch (error) {
        _diag(
          'non_critical_revenue_ledger_failure action=promotion_$status target=listings/$id error=${_safeError(error)}',
        );
      }
    }

    try {
      await _log(
        'listing',
        id,
        'promotion_$status',
        previousStatus: _status(current),
        newStatus: _status(current),
        previousAuctionStatus: _auctionStatus(current),
        newAuctionStatus: _auctionStatus(current),
        previousPromotionStatus: currentPromo,
        newPromotionStatus: status,
        notes: note.trim(),
      );
    } catch (error) {
      _diag(
        'non_critical_log_failure action=promotion_$status target=listings/$id error=${_safeError(error)}',
      );
    }

    if (sellerId.isNotEmpty && sellerId != '-') {
      final title = _s(
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
              ? 'Promotion for $title is now $userFacingStatus.'
              : 'Promotion for $title is now $userFacingStatus. Reason: $note',
          titleUr: 'پروموشن اپڈیٹ',
          bodyUr: note.trim().isEmpty
              ? '$title کی پروموشن اسٹیٹس اب $userFacingStatus ہے۔'
              : '$title کی پروموشن اسٹیٹس اب $userFacingStatus ہے۔ وجہ: $note',
          listingId: id,
          metadata: {'status': status, 'note': note.trim()},
        );
      } catch (error) {
        _diag(
          'non_critical_notify_failure action=promotion_$status target=listings/$id error=${_safeError(error)}',
        );
      }
    }
    debugPrint('[ADMIN_ACTION] errorCode=');
    debugPrint('[ADMIN_ACTION] errorMessage=');
    debugPrint('[ADMIN_ACTION] success=true');
  }

  Future<void> _userFlags(
    String id, {
    bool? trusted,
    bool? suspended,
    bool? restricted,
    String note = '',
  }) async {
    final userSnap = await _db.collection('users').doc(id).get();
    if (!userSnap.exists) {
      throw const _AdminUiException('User not found');
    }
    final before = userSnap.data() ?? <String, dynamic>{};
    final updates = <String, dynamic>{};
    if (trusted != null) updates['trustedSeller'] = trusted;
    if (suspended != null) updates['isSuspended'] = suspended;
    if (restricted != null) updates['listingRestricted'] = restricted;
    final String firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    debugPrint('[ADMIN_ACTION] action=update_user_risk_flags');
    debugPrint('[ADMIN_ACTION] firebaseUid=$firebaseUid');
    debugPrint('[ADMIN_ACTION] docPath=users/$id');
    debugPrint('[ADMIN_ACTION] payload=$updates');
    await _db.collection('users').doc(id).set(updates, SetOptions(merge: true));
    try {
      await _log(
        'user',
        id,
        'update_user_risk_flags',
        notes:
            'before=${before.toString()} after=${updates.toString()} note=$note',
      );
    } catch (error) {
      _diag(
        'non_critical_log_failure action=update_user_risk_flags target=users/$id error=${_safeError(error)}',
      );
    }

    if (suspended != null) {
      try {
        await _notifyUser(
          userId: id,
          type: suspended ? 'account_suspended' : 'account_reactivated',
          title: suspended ? 'Account suspended' : 'Account reactivated',
          body: suspended
              ? (note.trim().isEmpty
                    ? 'Your account has been suspended by admin.'
                    : 'Your account has been suspended: $note')
              : 'Your account has been reactivated by admin.',
          titleUr: suspended ? 'اکاؤنٹ معطل' : 'اکاؤنٹ بحال',
          bodyUr: suspended
              ? (note.trim().isEmpty
                    ? 'ایڈمن نے آپ کا اکاؤنٹ معطل کر دیا ہے۔'
                    : 'آپ کا اکاؤنٹ معطل کر دیا گیا: $note')
              : 'ایڈمن نے آپ کا اکاؤنٹ دوبارہ بحال کر دیا ہے۔',
          metadata: {
            'note': note,
            'action': suspended ? 'suspend_user' : 'reactivate_user',
          },
        );
      } catch (error) {
        _diag(
          'non_critical_notify_failure action=${suspended ? 'suspend_user' : 'reactivate_user'} target=users/$id error=${_safeError(error)}',
        );
      }
    }
    if (restricted != null) {
      try {
        await _notifyUser(
          userId: id,
          type: restricted
              ? 'listing_restricted'
              : 'listing_restriction_removed',
          title: restricted
              ? 'Listing restricted'
              : 'Listing restriction removed',
          body: restricted
              ? (note.trim().isEmpty
                    ? 'Your listing privileges were restricted by admin.'
                    : 'Your listing privileges were restricted: $note')
              : 'Your listing privileges are now restored.',
          titleUr: restricted ? 'لسٹنگ محدود' : 'لسٹنگ بحال',
          bodyUr: restricted
              ? (note.trim().isEmpty
                    ? 'ایڈمن نے آپ کی لسٹنگ کی سہولت محدود کر دی ہے۔'
                    : 'آپ کی لسٹنگ کی سہولت محدود کی گئی: $note')
              : 'آپ کی لسٹنگ کی سہولت دوبارہ بحال کر دی گئی ہے۔',
          metadata: {
            'note': note,
            'action': restricted ? 'restrict_user' : 'allow_user_listings',
          },
        );
      } catch (error) {
        _diag(
          'non_critical_notify_failure action=${restricted ? 'restrict_user' : 'allow_user_listings'} target=users/$id error=${_safeError(error)}',
        );
      }
    }
  }

  String _sellerVerificationStatus(Map<String, dynamic> data) {
    final raw = _s(data['verificationStatus'], fallback: '').toLowerCase();
    if (raw == 'approved' || raw == 'verified') return 'approved';
    if (raw == 'rejected') return 'rejected';
    return 'pending';
  }

  Future<void> _setSellerVerificationStatus(
    String userId, {
    required String status,
    String rejectionReason = '',
  }) async {
    final normalized = status.trim().toLowerCase();
    if (normalized != 'approved' &&
        normalized != 'rejected' &&
        normalized != 'pending') {
      throw const _AdminUiException('Invalid verification status');
    }

    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    final now = FieldValue.serverTimestamp();
    final updates = <String, dynamic>{
      'verificationStatus': normalized,
      'isApproved': normalized == 'approved',
      'reviewedAt': now,
      'reviewedBy': adminUid,
      'rejectionReason': normalized == 'rejected' ? rejectionReason.trim() : null,
      'verifiedAt': normalized == 'approved' ? now : null,
      'reviewRequired': normalized != 'approved',
      'updatedAt': now,
    };

    final String firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    debugPrint('[ADMIN_ACTION] action=seller_verification_$normalized');
    debugPrint('[ADMIN_ACTION] firebaseUid=$firebaseUid');
    debugPrint('[ADMIN_ACTION] docPath=users/$userId');
    debugPrint('[ADMIN_ACTION] payload=$updates');

    await _db.collection('users').doc(userId).set(updates, SetOptions(merge: true));
    try {
      await _log(
        'user',
        userId,
        'seller_verification_$normalized',
        previousStatus: null,
        newStatus: normalized,
        notes: rejectionReason.trim(),
      );
    } catch (error) {
      _diag(
        'non_critical_log_failure action=seller_verification_$normalized target=users/$userId error=${_safeError(error)}',
      );
    }
  }

  Future<void> _viewSellerActivity(String userId) async {
    final listingSnap = await _db
        .collection('listings')
        .where('sellerId', isEqualTo: userId)
        .limit(200)
        .get();
    if (!mounted) return;
    final docs = listingSnap.docs;
    final int total = docs.length;
    final int live = docs.where((d) => _status(d.data()) == 'active').length;
    final int rejected = docs
        .where((d) => _status(d.data()) == 'rejected')
        .length;
    final int review = docs.where((d) => _needsModeration(d.data())).length;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seller Activity'),
        content: Text(
          'Total Listings: $total\nLive: $live\nUnder Review: $review\nRejected: $rejected',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await SessionService.logoutToLogin(context);
  }

  void _refreshView() {
    setState(() {
      // Trigger stream rebuild without mutating business state.
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, roleSnap) {
        final role = _s(
          roleSnap.data?.data()?['role'],
          fallback: _s(roleSnap.data?.data()?['userRole']),
        ).toLowerCase();
        if (!roleSnap.hasData && !roleSnap.hasError) {
          _adminBoot('loadingWidget=AdminRoleGate');
        }
        if (roleSnap.hasError) {
          _adminBoot('serviceError=permission-denied source=role_users_stream');
          _adminBoot('fallbackUsed=true');
        }
        if (roleSnap.hasData && role != 'admin') {
          _adminBoot('dashboardRenderable=false');
          return const Scaffold(body: Center(child: Text('Access denied')));
        }

        if (!_adminBootRouteLogged) {
          _adminBoot('routeEntered=true');
          _adminBootRouteLogged = true;
        }
        if (!_adminBootRenderableLogged) {
          _adminBoot('dashboardRenderable=true');
          _adminBootRenderableLogged = true;
        }

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            titleSpacing: 12,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Digital Arhat',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                Text(
                  'Admin Command Center',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _refreshView,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                onPressed: _logout,
                tooltip: 'Logout',
                icon: const Icon(Icons.logout_rounded, color: _gold),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _gold.withValues(alpha: 0.2),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: _gold,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'Dashboard'),
                Tab(text: 'Moderation'),
                Tab(text: 'Auctions'),
                Tab(text: 'Revenue'),
                Tab(text: 'Users'),
                Tab(text: 'Risk/Ops'),
              ],
            ),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bg, const Color(0xFF0C2745), _bg],
              ),
            ),
            child: TabBarView(
              controller: _tabs,
              children: [
                _dashboard(),
                _moderation(),
                _auctions(),
                _revenue(),
                _users(),
                _riskOps(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dashboard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('listings').snapshots(),
      builder: (context, snap) {
        final docs =
            snap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        int pendingModeration = 0;
        int pendingPromoReview = 0;
        int liveListings = 0;
        int liveAuctions = 0;
        int activeFeaturedListings = 0;
        int activeFeaturedAuctions = 0;
        int rejectedCount = 0;
        int changeRequestedCount = 0;
        double promotionRevenue = 0;

        for (final doc in docs) {
          final d = doc.data();
          final status = _status(d);
          final auctionStatus = _auctionStatus(d);
          final saleType = _s(d['saleType'], fallback: 'auction').toLowerCase();
          final promo = _promoStatusForMetrics(d);
          final reviewState = _s(d['adminReviewStatus']).toLowerCase();

          if (_needsModeration(d)) pendingModeration++;
          if (promo == 'pending_review') pendingPromoReview++;

          if (saleType == 'auction') {
            if (auctionStatus == 'live') liveAuctions++;
          } else {
            if (status == 'active' || status == 'live') liveListings++;
          }

          if (promo == 'active' &&
              _b(d['featured']) &&
              !_b(d['featuredAuction'])) {
            activeFeaturedListings++;
          }
          if (promo == 'active' &&
              (_b(d['featuredAuction']) ||
                  (saleType == 'auction' && _b(d['featured'])))) {
            activeFeaturedAuctions++;
          }

          if (promo == 'approved' || promo == 'active') {
            promotionRevenue += _n(d['featuredCost']);
          }

          if (status == 'rejected' || reviewState == 'rejected') {
            rejectedCount++;
          }
          if (reviewState == 'changes_requested') changeRequestedCount++;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('users').snapshots(),
          builder: (context, userSnap) {
            final usersTotal = userSnap.data?.docs.length ?? 0;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('listings')
                  .where('status', isEqualTo: 'delivered_pending_release')
                  .limit(200)
                  .snapshots(),
              builder: (context, payoutSnap) {
                final pendingSettlements = payoutSnap.data?.docs.length ?? 0;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                  children: [
                    _panel(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.insights_rounded,
                              color: _gold,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Platform Fees',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Featured Listing: Rs ${PromotionPaymentConfig.featuredListingFee}  |  Featured Auction: Rs ${PromotionPaymentConfig.featuredAuctionFee}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        'Operations Snapshot',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricCard(
                          'Moderation Queue',
                          '$pendingModeration',
                          _gold,
                          Icons.fact_check_rounded,
                        ),
                        _metricCard(
                          'Live Listings',
                          '$liveListings',
                          _green,
                          Icons.storefront_rounded,
                        ),
                        _metricCard(
                          'Live Auctions',
                          '$liveAuctions',
                          _blue,
                          Icons.gavel_rounded,
                        ),
                        _metricCard(
                          'Promotion Review',
                          '$pendingPromoReview',
                          Colors.orangeAccent,
                          Icons.receipt_long_rounded,
                        ),
                        _metricCard(
                          'Featured Listings',
                          '$activeFeaturedListings',
                          _green,
                          Icons.workspace_premium_rounded,
                        ),
                        _metricCard(
                          'Featured Auctions',
                          '$activeFeaturedAuctions',
                          _blue,
                          Icons.local_fire_department_rounded,
                        ),
                        _metricCard(
                          'Promotion Revenue',
                          'Rs ${promotionRevenue.toStringAsFixed(0)}',
                          _gold,
                          Icons.payments_rounded,
                        ),
                        _metricCard(
                          'Users Total',
                          '$usersTotal',
                          Colors.cyanAccent,
                          Icons.groups_rounded,
                        ),
                        _metricCard(
                          'Pending Settlements',
                          '$pendingSettlements',
                          Colors.deepOrangeAccent,
                          Icons.account_balance_wallet_rounded,
                        ),
                        _metricCard(
                          'Rejected',
                          '$rejectedCount',
                          Colors.redAccent,
                          Icons.cancel_rounded,
                        ),
                        _metricCard(
                          'Changes Requested',
                          '$changeRequestedCount',
                          Colors.amberAccent,
                          Icons.edit_note_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<AdminMarketInsightsResult>(
                      future: _adminInsightsFuture,
                      builder: (context, insightSnap) {
                        if (insightSnap.connectionState ==
                            ConnectionState.waiting) {
                          _adminBoot('loadingWidget=AdminMarketInsightsPanel');
                          return _panel(
                            child: Row(
                              children: const [
                                SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Loading market insights...',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          );
                        }
                        if (insightSnap.hasError) {
                          _adminBoot(
                            'serviceError=permission-denied source=insights_futurebuilder',
                          );
                          _adminBoot('fallbackUsed=true');
                          return _panel(
                            child: const Text(
                              'Market insights unavailable',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        }
                        final insights = insightSnap.data;
                        if (insights == null) {
                          _adminBoot('fallbackUsed=true');
                          return _panel(
                            child: const Text(
                              'Market insights unavailable',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        }

                        final lines = <String>[
                          ...insights.topRisingCrops,
                          ...insights.topFallingCrops,
                          ...insights.highDemandCategories,
                        ];

                        return _panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Admin Market Insight',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _refreshAdminInsights,
                                    icon: const Icon(
                                      Icons.refresh,
                                      color: _gold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (lines.isEmpty)
                                const Text(
                                  'No strong market movement detected in last 24h.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ...lines
                                  .take(6)
                                  .map(
                                    (line) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '- $line',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _moderation() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .orderBy('createdAt', descending: true)
          .limit(120)
          .snapshots(),
      builder: (context, snap) {
        final docs =
            (snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where(
                  (doc) =>
                      _needsModeration(doc.data()) &&
                      !_hiddenModerationIds.contains(doc.id),
                )
                .toList(growable: false);
        if (docs.isEmpty) {
          return _emptyState(
            'No pending moderation items',
            'New listings needing review will appear here.',
            Icons.fact_check_rounded,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final d = doc.data();
            final currentStatus = _status(d);
            final currentAuctionStatus = _auctionStatus(d);
            final isApproved = _b(d['isApproved']);
            final market = _n(d['marketAverage']) > 0
                ? _n(d['marketAverage'])
                : _n(d['market_average']);
            final rate = _n(d['price']);
            final delta = market > 0 ? ((rate - market) / market) * 100 : 0;
            final imageCount = _extractImageUrls(d).length;
            final hasPhoto = imageCount > 0;
            final hasVideo = _videoUrl(d).isNotEmpty;
            final hasAudio = _audioUrl(d).isNotEmpty;
            final canApprove =
                !(isApproved &&
                    (currentStatus == 'active' ||
                        currentStatus == 'approved' ||
                        currentAuctionStatus == 'live'));
            final canStartAuction =
                currentStatus != 'rejected' &&
                currentAuctionStatus != 'live' &&
                currentAuctionStatus != 'cancelled' &&
                currentAuctionStatus != 'completed';
            return _panel(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s(d['itemName'], fallback: _s(d['product'])),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_s(d['categoryLabel'], fallback: _s(d['category']))} > ${_s(d['subcategoryLabel'], fallback: _s(d['subcategory']))} > ${_s(d['variety'])}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _statusBadge('Pending Review', Colors.orangeAccent),
                      if (!hasPhoto || !hasVideo)
                        _statusBadge('Low Evidence', Colors.amber),
                    ],
                  ),
                  Text(
                    'Seller: ${_s(d['sellerName'], fallback: _s(d['sellerId']))}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Location: ${_s(d['city'], fallback: _s(d['district'], fallback: _s(d['location'])))}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Qty: ${_n(d['quantity']).toStringAsFixed(0)} ${_s(d['unit'], fallback: _s(d['unitType']))} | Rate: Rs ${rate.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Photo: ${hasPhoto ? 'yes' : 'no'} | Video: ${hasVideo ? 'yes' : 'no'} | Audio: ${hasAudio ? 'yes' : 'no'} | Images: $imageCount',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    market > 0
                        ? 'Market avg Rs ${market.toStringAsFixed(0)} | Delta ${delta.toStringAsFixed(1)}%'
                        : 'Market avg unavailable',
                    style: TextStyle(
                      color: market > 0 && delta.abs() > 20
                          ? Colors.redAccent
                          : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _button(
                        'Approve Listing',
                        Colors.green,
                        () => _runAction(
                          key: 'approve_${doc.id}',
                          failedMessage:
                              'Could not approve listing. Please retry.',
                          failureAction: 'approve_listing',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _approve(doc.id),
                          successMessage: 'Listing approved successfully',
                          onSuccess: () {
                            setState(() => _hiddenModerationIds.add(doc.id));
                          },
                        ),
                        actionKey: 'approve_${doc.id}',
                        enabled: canApprove,
                      ),
                      _button('Reject Listing', Colors.red, () async {
                        final note = await _askAdminNote('Reject listing note');
                        if (note == null || note.trim().isEmpty) return;
                        await _runAction(
                          key: 'reject_${doc.id}',
                          failedMessage:
                              'Could not reject listing. Please retry.',
                          failureAction: 'reject_listing',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _reject(doc.id, note: note),
                          successMessage: 'Listing rejected',
                          onSuccess: () {
                            setState(() => _hiddenModerationIds.add(doc.id));
                          },
                        );
                      }, actionKey: 'reject_${doc.id}'),
                      _button(
                        'Request Changes',
                        Colors.orange,
                        () async {
                          final note = await _askAdminNote(
                            'Request changes note',
                          );
                          if (note == null || note.trim().isEmpty) return;
                          await _runAction(
                            key: 'changes_${doc.id}',
                            failedMessage:
                                'Could not request changes. Please retry.',
                            failureAction: 'request_changes',
                            targetCollection: 'listings',
                            targetId: doc.id,
                            work: () => _changes(doc.id, note: note),
                            successMessage: 'Changes requested',
                            onSuccess: () {
                              setState(() => _hiddenModerationIds.add(doc.id));
                            },
                          );
                        },
                        actionKey: 'changes_${doc.id}',
                      ),
                      _button(
                        'View Full Details',
                        Colors.blueGrey,
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AdminListingDetailScreen(listingId: doc.id),
                          ),
                        ),
                      ),
                      _button(
                        'Start Auction',
                        Colors.blue,
                        () => _runAction(
                          key: 'start_${doc.id}',
                          failedMessage:
                              'Could not start auction. Please retry.',
                          failureAction: 'start_auction',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _startAuction(doc.id),
                          successMessage: 'Auction started',
                          onSuccess: () {
                            setState(() {
                              _hiddenModerationIds.add(doc.id);
                              _auctionStatusOverrides[doc.id] = 'live';
                            });
                          },
                        ),
                        actionKey: 'start_${doc.id}',
                        enabled: canStartAuction,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _auctions() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .orderBy('updatedAt', descending: true)
          .limit(120)
          .snapshots(),
      builder: (context, snap) {
        final docs =
            (snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where(
                  (doc) =>
                      _s(
                        doc.data()['saleType'],
                        fallback: 'auction',
                      ).toLowerCase() ==
                      'auction',
                )
                .toList(growable: false);
        if (docs.isEmpty) {
          return _emptyState(
            'No live auctions to manage',
            'Auctions will appear here when listings are auction-enabled.',
            Icons.gavel_rounded,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: docs.map((doc) {
            final d = doc.data();
            final auctionStatus =
                _auctionStatusOverrides[doc.id] ??
                _s(d['auctionStatus'], fallback: _s(d['status']));
            final statusLower = auctionStatus.toLowerCase();
            final canStart =
                statusLower != 'live' &&
                statusLower != 'cancelled' &&
                statusLower != 'completed' &&
                _status(d) != 'rejected';
            final canPause = statusLower == 'live';
            final canResume = statusLower == 'paused';
            final canCancel =
                statusLower != 'cancelled' && statusLower != 'completed';
            final canExtend = statusLower == 'live' || statusLower == 'paused';
            return _panel(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s(d['itemName'], fallback: _s(d['product'])),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Seller: ${_s(d['sellerName'], fallback: _s(d['sellerId']))}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Highest bid: Rs ${_n(d['highestBid']).toStringAsFixed(0)} | Bids: ${_n(d['totalBids']).toInt()}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Status: ${auctionStatus.toUpperCase()}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  _statusBadge(
                    auctionStatus.toUpperCase(),
                    auctionStatus == 'live'
                        ? _green
                        : auctionStatus == 'paused'
                        ? Colors.amber
                        : Colors.redAccent,
                  ),
                  Text(
                    'Winning bidder: ${_s(d['winnerName'], fallback: _s(d['winnerId']))}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _button(
                        'Start Auction',
                        Colors.blue,
                        () => _runAction(
                          key: 'start_${doc.id}',
                          failedMessage:
                              'Could not start auction. Please retry.',
                          failureAction: 'start_auction',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _startAuction(doc.id),
                          successMessage: 'Auction started',
                          onSuccess: () {
                            setState(
                              () => _auctionStatusOverrides[doc.id] = 'live',
                            );
                          },
                        ),
                        actionKey: 'start_${doc.id}',
                        enabled: canStart,
                      ),
                      _button(
                        'Pause Auction',
                        Colors.orange,
                        () => _runAction(
                          key: 'pause_${doc.id}',
                          failedMessage:
                              'Could not pause auction. Please retry.',
                          failureAction: 'pause_auction',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _setAuction(doc.id, 'paused'),
                          successMessage: 'Auction paused',
                          onSuccess: () {
                            setState(
                              () => _auctionStatusOverrides[doc.id] = 'paused',
                            );
                          },
                        ),
                        actionKey: 'pause_${doc.id}',
                        enabled: canPause,
                      ),
                      _button(
                        'Resume Auction',
                        Colors.teal,
                        () => _runAction(
                          key: 'resume_${doc.id}',
                          failedMessage:
                              'Could not resume auction. Please retry.',
                          failureAction: 'resume_auction',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _setAuction(doc.id, 'live'),
                          successMessage: 'Auction resumed',
                          onSuccess: () {
                            setState(
                              () => _auctionStatusOverrides[doc.id] = 'live',
                            );
                          },
                        ),
                        actionKey: 'resume_${doc.id}',
                        enabled: canResume,
                      ),
                      _button(
                        'Cancel Auction',
                        Colors.red,
                        () => _runAction(
                          key: 'cancel_${doc.id}',
                          failedMessage:
                              'Could not cancel auction. Please retry.',
                          failureAction: 'cancel_auction',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () async {
                            final note = await _askAdminNote(
                              'Cancel auction reason',
                              hint: 'Policy or operational reason',
                              required: true,
                            );
                            if (note == null) {
                              throw const _AdminUiException('Action cancelled');
                            }
                            await _setAuction(doc.id, 'cancelled', note: note);
                          },
                          successMessage: 'Auction cancelled',
                          onSuccess: () {
                            setState(
                              () =>
                                  _auctionStatusOverrides[doc.id] = 'cancelled',
                            );
                          },
                        ),
                        actionKey: 'cancel_${doc.id}',
                        enabled: canCancel,
                      ),
                      _button(
                        'Extend +2h',
                        Colors.indigo,
                        () => _runAction(
                          key: 'extend_${doc.id}',
                          failedMessage:
                              'Could not extend auction. Please retry.',
                          failureAction: 'extend_auction',
                          targetCollection: 'listings',
                          targetId: doc.id,
                          work: () => _extend(doc.id),
                          successMessage: 'Auction extended by 2 hours',
                        ),
                        actionKey: 'extend_${doc.id}',
                        enabled: canExtend,
                      ),
                      _button(
                        'View Bids',
                        Colors.blueGrey,
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AdminListingDetailScreen(listingId: doc.id),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _revenue() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .orderBy('updatedAt', descending: true)
          .limit(140)
          .snapshots(),
      builder: (context, snap) {
        final docs =
            (snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where(
                  (doc) =>
                      _promo(
                            _s(doc.data()['promotionStatus'], fallback: 'none'),
                          ) !=
                          'none' ||
                      _b(doc.data()['featured']) ||
                      _b(doc.data()['featuredAuction']),
                )
                .toList(growable: false);
        if (docs.isEmpty) {
          return _emptyState(
            'No promotion payments awaiting review',
            'Promotion requests and payment states appear here.',
            Icons.payments_rounded,
          );
        }
        int pendingReviews = 0;
        int approved = 0;
        int rejected = 0;
        int active = 0;
        double revenue = 0;
        for (final doc in docs) {
          final data = doc.data();
          final status = _promoStatusForMetrics(data);
          if (status == 'pending_review') {
            pendingReviews++;
          }
          if (status == 'approved') approved++;
          if (status == 'rejected') rejected++;
          if (status == 'active') active++;
          if (status == 'approved' || status == 'active') {
            revenue += _n(data['featuredCost']);
          }
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('revenue_ledger')
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots(),
          builder: (context, ledgerSnap) {
            double featuredListingRevenue = 0;
            double featuredAuctionRevenue = 0;
            double todayRevenue = 0;
            double weekRevenue = 0;
            double monthRevenue = 0;
            final now = DateTime.now();
            final docs =
                ledgerSnap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in docs) {
              final d = doc.data();
              final status = _s(d['status'], fallback: '').toLowerCase();
              if (status != 'approved' && status != 'active') continue;
              final amount = _n(d['amount']);
              final category = _s(
                d['revenueCategory'],
                fallback: '',
              ).toLowerCase();
              final createdAt = _toDate(d['createdAt']);
              if (category == 'featured_auction') {
                featuredAuctionRevenue += amount;
              } else {
                featuredListingRevenue += amount;
              }
              if (createdAt == null) continue;
              if (createdAt.year == now.year &&
                  createdAt.month == now.month &&
                  createdAt.day == now.day) {
                todayRevenue += amount;
              }
              if (!createdAt.isBefore(now.subtract(const Duration(days: 7)))) {
                weekRevenue += amount;
              }
              if (createdAt.year == now.year && createdAt.month == now.month) {
                monthRevenue += amount;
              }
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricCard(
                      'Promo Revenue',
                      'Rs ${revenue.toStringAsFixed(0)}',
                      _gold,
                      Icons.payments_rounded,
                    ),
                    _metricCard(
                      'Featured Listing Revenue',
                      'Rs ${featuredListingRevenue.toStringAsFixed(0)}',
                      Colors.lightGreenAccent,
                      Icons.workspace_premium_rounded,
                    ),
                    _metricCard(
                      'Featured Auction Revenue',
                      'Rs ${featuredAuctionRevenue.toStringAsFixed(0)}',
                      Colors.orangeAccent,
                      Icons.local_fire_department_rounded,
                    ),
                    _metricCard(
                      'Pending Reviews',
                      '$pendingReviews',
                      Colors.orangeAccent,
                      Icons.receipt_long_rounded,
                    ),
                    _metricCard(
                      'Approved',
                      '$approved',
                      _green,
                      Icons.verified_rounded,
                    ),
                    _metricCard(
                      'Rejected',
                      '$rejected',
                      Colors.redAccent,
                      Icons.cancel_rounded,
                    ),
                    _metricCard(
                      'Active Promotions',
                      '$active',
                      _blue,
                      Icons.workspace_premium_rounded,
                    ),
                    _metricCard(
                      'Today Revenue',
                      'Rs ${todayRevenue.toStringAsFixed(0)}',
                      Colors.cyanAccent,
                      Icons.today_rounded,
                    ),
                    _metricCard(
                      'Week Revenue',
                      'Rs ${weekRevenue.toStringAsFixed(0)}',
                      Colors.tealAccent,
                      Icons.calendar_view_week_rounded,
                    ),
                    _metricCard(
                      'Month Revenue',
                      'Rs ${monthRevenue.toStringAsFixed(0)}',
                      Colors.amberAccent,
                      Icons.calendar_month_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...docs.map((doc) {
                  final d = doc.data();
                  final status = _promoStatusForMetrics(d);
                  final promoType = _b(d['featuredAuction'])
                      ? 'featured_auction'
                      : (_b(d['featured']) ? 'featured_listing' : 'none');
                  return _panel(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _s(d['itemName'], fallback: _s(d['product'])),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Seller: ${_s(d['sellerName'], fallback: _s(d['sellerId']))}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Promotion type: $promoType',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        _statusBadge(
                          status,
                          status == 'active'
                              ? _green
                              : status == 'rejected'
                              ? Colors.redAccent
                              : Colors.orangeAccent,
                        ),
                        Text(
                          'Amount: Rs ${_n(d['featuredCost']).toStringAsFixed(0)} | Status: $status',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Requested At: ${_formatAdminDateTime(d['promotionRequestedAt'] ?? d['createdAt'])}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Payment Ref: ${_displayField(d['promotionPaymentReference'] ?? d['paymentReference'])}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Proof: ${_displayField(d['promotionProofUrl'] ?? d['paymentReceiptUrl'])}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _button(
                              'Mark Payment Under Review',
                              Colors.orange,
                              () => _runAction(
                                key: 'promo_review_${doc.id}',
                                failedMessage:
                                    'Could not mark payment under review. Please retry.',
                                failureAction: 'promotion_payment_under_review',
                                targetCollection: 'listings',
                                targetId: doc.id,
                                work: () async {
                                  final note = await _askAdminNote(
                                    'Request better promotion proof',
                                    hint: 'Receipt mismatch or missing details',
                                    required: true,
                                  );
                                  if (note == null) {
                                    throw const _AdminUiException(
                                      'Action cancelled',
                                    );
                                  }
                                  await _promoStatus(
                                    doc.id,
                                    'pending_review',
                                    note: note,
                                  );
                                },
                                successMessage: 'Payment marked under review',
                              ),
                              actionKey: 'promo_review_${doc.id}',
                            ),
                            _button(
                              'Approve Promotion',
                              Colors.green,
                              () => _runAction(
                                key: 'promo_approved_${doc.id}',
                                failedMessage:
                                    'Could not approve promotion. Please retry.',
                                failureAction: 'approve_promotion',
                                targetCollection: 'listings',
                                targetId: doc.id,
                                work: () => _promoStatus(doc.id, 'approved'),
                                successMessage: 'Promotion approved',
                              ),
                              actionKey: 'promo_approved_${doc.id}',
                            ),
                            _button(
                              'Reject Promotion',
                              Colors.red,
                              () => _runAction(
                                key: 'promo_rejected_${doc.id}',
                                failedMessage:
                                    'Could not reject promotion. Please retry.',
                                failureAction: 'reject_promotion',
                                targetCollection: 'listings',
                                targetId: doc.id,
                                work: () async {
                                  final note = await _askAdminNote(
                                    'Reject promotion reason',
                                    hint: 'Invalid or incomplete payment proof',
                                    required: true,
                                  );
                                  if (note == null) {
                                    throw const _AdminUiException(
                                      'Action cancelled',
                                    );
                                  }
                                  await _promoStatus(
                                    doc.id,
                                    'rejected',
                                    note: note,
                                  );
                                },
                                successMessage: 'Promotion rejected',
                              ),
                              actionKey: 'promo_rejected_${doc.id}',
                            ),
                            _button(
                              'Activate Promotion',
                              Colors.blue,
                              () => _runAction(
                                key: 'promo_active_${doc.id}',
                                failedMessage:
                                    'Could not activate promotion. Please retry.',
                                failureAction: 'activate_promotion',
                                targetCollection: 'listings',
                                targetId: doc.id,
                                work: () => _promoStatus(doc.id, 'active'),
                                successMessage: 'Promotion activated',
                              ),
                              actionKey: 'promo_active_${doc.id}',
                            ),
                            _button(
                              'Deactivate Promotion',
                              Colors.grey,
                              () => _runAction(
                                key: 'promo_expired_${doc.id}',
                                failedMessage:
                                    'Could not deactivate promotion. Please retry.',
                                failureAction: 'deactivate_promotion',
                                targetCollection: 'listings',
                                targetId: doc.id,
                                work: () => _promoStatus(doc.id, 'expired'),
                                successMessage: 'Promotion deactivated',
                              ),
                              actionKey: 'promo_expired_${doc.id}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _users() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').snapshots(),
      builder: (context, snap) {
        final docs =
            snap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final totalUsers = docs.length;
        final totalSellers = docs.where((u) {
          final role = _s(
            u.data()['role'],
            fallback: _s(u.data()['userRole']),
          ).toLowerCase();
          return role == 'seller' || role == 'arhat';
        }).length;
        final totalBuyers = docs.where((u) {
          final role = _s(
            u.data()['role'],
            fallback: _s(u.data()['userRole']),
          ).toLowerCase();
          return role == 'buyer';
        }).length;
        final suspendedUsers = docs
            .where((u) => _b(u.data()['isSuspended']))
            .length;
        final trustedSellers = docs
            .where((u) => _b(u.data()['trustedSeller']))
            .length;
        final restrictedUsers = docs
            .where((u) => _b(u.data()['listingRestricted']))
            .length;
        final sellers = docs
            .where((u) {
              final role = _s(
                u.data()['role'],
                fallback: _s(u.data()['userRole']),
              ).toLowerCase();
              return role == 'seller' || role == 'arhat';
            })
            .toList(growable: false);
        if (sellers.isEmpty) {
          return _emptyState(
            'No users need action',
            'Seller moderation and account controls appear here.',
            Icons.groups_rounded,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricCard(
                  'Total Users',
                  '$totalUsers',
                  _gold,
                  Icons.groups_rounded,
                ),
                _metricCard(
                  'Total Sellers',
                  '$totalSellers',
                  _green,
                  Icons.storefront_rounded,
                ),
                _metricCard(
                  'Total Buyers',
                  '$totalBuyers',
                  _blue,
                  Icons.shopping_basket_rounded,
                ),
                _metricCard(
                  'Suspended Users',
                  '$suspendedUsers',
                  Colors.redAccent,
                  Icons.block_rounded,
                ),
                _metricCard(
                  'Trusted Sellers',
                  '$trustedSellers',
                  Colors.greenAccent,
                  Icons.verified_user_rounded,
                ),
                _metricCard(
                  'Restricted Users',
                  '$restrictedUsers',
                  Colors.orangeAccent,
                  Icons.warning_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...sellers.take(80).map((doc) {
              final d = doc.data();
              final verificationStatus = _sellerVerificationStatus(d);
              final rejectionReason = _s(d['rejectionReason'], fallback: '');
              return _panel(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s(
                        d['name'],
                        fallback: _s(d['fullName'], fallback: doc.id),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Trusted: ${_b(d['trustedSeller'])} | Suspended: ${_b(d['isSuspended'])} | Restricted: ${_b(d['listingRestricted'])} | Verification: $verificationStatus',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (verificationStatus == 'pending')
                          _statusBadge('Pending Review', Colors.amber),
                        if (verificationStatus == 'approved')
                          _statusBadge('Approved', Colors.lightGreenAccent),
                        if (verificationStatus == 'rejected')
                          _statusBadge('Rejected', Colors.redAccent),
                        if (_b(d['trustedSeller']))
                          _statusBadge('Trusted', _green),
                        if (_b(d['isSuspended']))
                          _statusBadge('Suspended', Colors.redAccent),
                        if (_b(d['listingRestricted']))
                          _statusBadge('Restricted', Colors.orangeAccent),
                      ],
                    ),
                    if (verificationStatus == 'rejected' &&
                        rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Rejection reason: $rejectionReason',
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _button(
                          'Approve Seller',
                          Colors.green,
                          () => _runAction(
                            key: 'verify_approved_${doc.id}',
                            failedMessage:
                                'Could not approve seller. Please retry.',
                            failureAction: 'seller_verification_approved',
                            targetCollection: 'users',
                            targetId: doc.id,
                            intendedStatus: 'approved',
                            work: () => _setSellerVerificationStatus(
                              doc.id,
                              status: 'approved',
                            ),
                            successMessage: 'Seller approved',
                          ),
                          actionKey: 'verify_approved_${doc.id}',
                        ),
                        _button(
                          'Reject Seller',
                          Colors.red,
                          () => _runAction(
                            key: 'verify_rejected_${doc.id}',
                            failedMessage:
                                'Could not reject seller. Please retry.',
                            failureAction: 'seller_verification_rejected',
                            targetCollection: 'users',
                            targetId: doc.id,
                            intendedStatus: 'rejected',
                            work: () async {
                              final note = await _askAdminNote(
                                'Reject seller reason',
                                hint: 'Required reason for rejection',
                                required: true,
                              );
                              if (note == null) {
                                throw const _AdminUiException(
                                  'Action cancelled',
                                );
                              }
                              await _setSellerVerificationStatus(
                                doc.id,
                                status: 'rejected',
                                rejectionReason: note,
                              );
                            },
                            successMessage: 'Seller rejected',
                          ),
                          actionKey: 'verify_rejected_${doc.id}',
                        ),
                        _button(
                          'Mark Pending',
                          Colors.amber,
                          () => _runAction(
                            key: 'verify_pending_${doc.id}',
                            failedMessage:
                                'Could not mark pending. Please retry.',
                            failureAction: 'seller_verification_pending',
                            targetCollection: 'users',
                            targetId: doc.id,
                            intendedStatus: 'pending',
                            work: () => _setSellerVerificationStatus(
                              doc.id,
                              status: 'pending',
                            ),
                            successMessage: 'Seller marked pending review',
                          ),
                          actionKey: 'verify_pending_${doc.id}',
                        ),
                        _button(
                          'Mark Trusted',
                          Colors.green,
                          () => _runAction(
                            key: 'trusted_${doc.id}',
                            failedMessage:
                                'Could not mark user as trusted. Please retry.',
                            failureAction: 'mark_trusted',
                            targetCollection: 'users',
                            targetId: doc.id,
                            work: () => _userFlags(doc.id, trusted: true),
                            successMessage: 'Seller marked trusted',
                          ),
                          actionKey: 'trusted_${doc.id}',
                        ),
                        _button(
                          'Suspend User',
                          Colors.red,
                          () => _runAction(
                            key: 'suspend_${doc.id}',
                            failedMessage:
                                'Could not suspend user. Please retry.',
                            failureAction: 'suspend_user',
                            targetCollection: 'users',
                            targetId: doc.id,
                            work: () async {
                              final note = await _askAdminNote(
                                'Suspend seller reason',
                                hint: 'Required reason for suspension',
                                required: true,
                              );
                              if (note == null) {
                                throw const _AdminUiException(
                                  'Action cancelled',
                                );
                              }
                              await _userFlags(
                                doc.id,
                                suspended: true,
                                note: note,
                              );
                            },
                            successMessage: 'User suspended',
                          ),
                          actionKey: 'suspend_${doc.id}',
                        ),
                        _button(
                          'Reactivate User',
                          Colors.teal,
                          () => _runAction(
                            key: 'reactivate_${doc.id}',
                            failedMessage:
                                'Could not reactivate user. Please retry.',
                            failureAction: 'reactivate_user',
                            targetCollection: 'users',
                            targetId: doc.id,
                            work: () => _userFlags(doc.id, suspended: false),
                            successMessage: 'User reactivated',
                          ),
                          actionKey: 'reactivate_${doc.id}',
                        ),
                        _button(
                          'Restrict User',
                          Colors.orange,
                          () => _runAction(
                            key: 'restrict_${doc.id}',
                            failedMessage:
                                'Could not restrict user. Please retry.',
                            failureAction: 'restrict_user',
                            targetCollection: 'users',
                            targetId: doc.id,
                            work: () async {
                              final note = await _askAdminNote(
                                'Restrict seller listings reason',
                                hint: 'Required reason for listing restriction',
                                required: true,
                              );
                              if (note == null) {
                                throw const _AdminUiException(
                                  'Action cancelled',
                                );
                              }
                              await _userFlags(
                                doc.id,
                                restricted: true,
                                note: note,
                              );
                            },
                            successMessage: 'Listings restricted',
                          ),
                          actionKey: 'restrict_${doc.id}',
                        ),
                        _button(
                          'Allow Listings',
                          Colors.blueGrey,
                          () => _runAction(
                            key: 'allow_${doc.id}',
                            failedMessage:
                                'Could not remove restriction. Please retry.',
                            failureAction: 'allow_user_listings',
                            targetCollection: 'users',
                            targetId: doc.id,
                            work: () => _userFlags(doc.id, restricted: false),
                            successMessage: 'Listings enabled',
                          ),
                          actionKey: 'allow_${doc.id}',
                        ),
                        _button(
                          'View Seller Activity',
                          Colors.indigo,
                          () => _viewSellerActivity(doc.id),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _riskOps() {
    return Column(
      children: [
        // ── Seasonal Bakra Mandi toggle ──────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF122B4A), Color(0xFF163357)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (_bakraMandiEnabled ? _green : Colors.white12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: _bakraMandiEnabled ? Colors.white : Colors.white54,
                size: 20,
              ),
            ),
            title: const Text(
              'Bakra Mandi (Seasonal)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              _bakraMandiEnabled
                  ? 'Live — visible to all buyers'
                  : 'Hidden — not shown to buyers',
              style: TextStyle(
                color: _bakraMandiEnabled ? _green : Colors.white38,
                fontSize: 12,
              ),
            ),
            value: _bakraMandiEnabled,
            activeThumbColor: _green,
            onChanged: (v) async {
              final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
              await SeasonalBakraMandiConfig.setRuntimeVisibility(
                enabled: v,
                actorUid: adminUid,
              );
              if (!mounted) return;
              setState(() {
                _bakraMandiEnabled = v;
              });
            },
          ),
        ),
        const SizedBox(height: 4),
        // ── Completion Reports navigation ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            onTap: () => Navigator.of(context).pushNamed(
              Routes.adminCompletionReports,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.report_problem_outlined,
                    color: Color(0xFFFFD700),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Completion Reports',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Review seller reports on failed deals',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // ── Alerts & Risk stream ─────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('admin_alerts')
                .orderBy('timestamp', descending: true)
                .limit(160)
                .snapshots(),
            builder: (context, alertSnap) {
              final alerts =
                  alertSnap.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              debugPrint('[NotifReadAdmin] count=${alerts.length}');
              return _riskAlerts(alerts);
            },
          ),
        ),
      ],
    );
  }

  Widget _riskAlerts(List<QueryDocumentSnapshot<Map<String, dynamic>>> alerts) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .orderBy('createdAt', descending: true)
          .limit(120)
          .snapshots(),
      builder: (context, listingSnap) {
        // delegate to the original inner logic
        return _riskAlertsInner(alerts, listingSnap);
      },
    );
  }

  Widget _riskAlertsInner(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> alerts,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> listingSnap,
  ) {
    final listings =
        listingSnap.data?.docs ??
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    if (alerts.isEmpty && listings.isEmpty) {
      return _emptyState(
        'No active risk alerts',
        'Admin alerts and high-risk items will appear here automatically.',
        Icons.shield_outlined,
      );
    }

    final suspiciousListings = alerts.where((doc) {
      final d = doc.data();
      final type = _s(d['type'], fallback: '').toLowerCase();
      return type.contains('listing') || type.contains('price');
    }).length;

    final suspiciousBids = alerts.where((doc) {
      final d = doc.data();
      final type = _s(d['type'], fallback: '').toLowerCase();
      return type.contains('bid') || _n(d['aiBidRiskScore']) > 0;
    }).length;

    final fraudAlerts = alerts.where((doc) {
      final d = doc.data();
      final type = _s(d['type'], fallback: '').toLowerCase();
      final message = _s(d['message'], fallback: '').toLowerCase();
      return type.contains('fraud') || message.contains('fraud');
    }).length;

    final listingHighRisk = listings.where((doc) {
      final d = doc.data();
      return _n(d['aiRiskScore']) >= 70 || _n(d['riskScore']) >= 70;
    }).length;

    final alertHighRisk = alerts.where((doc) {
      final d = doc.data();
      return _n(d['aiBidRiskScore']) >= 70 || _n(d['riskScore']) >= 70;
    }).length;

    final highRiskItems = listingHighRisk + alertHighRisk;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricCard(
              'Suspicious Listings',
              '$suspiciousListings',
              Colors.orangeAccent,
              Icons.store_mall_directory_rounded,
            ),
            _metricCard(
              'Suspicious Bids',
              '$suspiciousBids',
              Colors.deepOrangeAccent,
              Icons.gavel_rounded,
            ),
            _metricCard(
              'Fraud Alerts',
              '$fraudAlerts',
              Colors.redAccent,
              Icons.warning_amber_rounded,
            ),
            _metricCard(
              'High Risk Items',
              '$highRiskItems',
              _gold,
              Icons.shield_rounded,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (alerts.isEmpty)
          _panel(
            child: const Text(
              'No admin alerts found yet. Suspicious bid/listing alerts will appear here.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          ...alerts.take(80).map((doc) {
            final d = doc.data();
            final alertType = _s(d['type'], fallback: 'alert').toUpperCase();
            final reason = _s(d['reason'], fallback: _s(d['message']));
            final listingId = _s(d['listingId'], fallback: '-');
            final bidId = _s(d['bidId'], fallback: '-');
            final riskScore = _n(d['riskScore']) > 0
                ? _n(d['riskScore'])
                : _n(d['aiBidRiskScore']);

            return _panel(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusBadge(alertType, Colors.orangeAccent),
                      if (riskScore > 0)
                        _chip(
                          'Risk ${riskScore.toStringAsFixed(0)}',
                          riskScore >= 70 ? Colors.redAccent : Colors.amber,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reason,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Listing: $listingId | Bid: $bidId',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_panelColor, const Color(0xFF163357)],
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

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
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

  Widget _metricCard(String label, String value, Color color, IconData icon) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String title, String helper, IconData icon) {
    return Center(
      child: _panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _gold, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(helper, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _button(
    String text,
    Color color,
    VoidCallback onTap, {
    String? actionKey,
    bool enabled = true,
  }) {
    final isLoading = actionKey != null && _isActionLoading(actionKey);
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
          : Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
