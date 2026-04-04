import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Manages buyer discipline: completion reports, strikes, completion rate.
///
/// Design rules:
///   - Reports go to [_kReportsCol] collection, status = 'pending'.
///   - Strikes are only applied after admin approves a report.
///   - Duplicate reports (same listingId + buyerId) are blocked.
///   - One event → at most one strike (abuse prevention via [strikeApplied] flag).
class BuyerDisciplineService {
  const BuyerDisciplineService._();

  static const String _kReportsCol = 'auction_completion_reports';
  static const String _kUsersCol = 'users';

  // ─── Strike thresholds ──────────────────────────────────────────────────────

  /// Strike 1 = warning only (no restriction). Strike 2 = 48h restriction.
  /// Strike 3+ = 30-day ban.
  static Duration _restrictionForStrike(int newStrikeCount) {
    if (newStrikeCount == 2) return const Duration(hours: 48);
    if (newStrikeCount >= 3) return const Duration(days: 30);
    return Duration.zero; // strike 1 = warning, no restriction
  }

  // ─── Submit report ──────────────────────────────────────────────────────────

  /// Seller submits a report that a winning buyer did not complete the deal.
  ///
  /// Returns the new [reportId] on success, or throws on error.
  /// Duplicate check: one report per [listingId]+[buyerId] pair.
  static Future<String> submitCompletionReport({
    required String listingId,
    required String buyerId,
    required String sellerId,
    required String bidId,
    required String reason,
    String note = '',
    FirebaseFirestore? firestore,
  }) async {
    assert(listingId.isNotEmpty, 'listingId required');
    assert(buyerId.isNotEmpty, 'buyerId required');
    assert(sellerId.isNotEmpty, 'sellerId required');

    final db = firestore ?? FirebaseFirestore.instance;

    // Abuse prevention: block duplicate reports for same listing+buyer.
    final existing = await db
        .collection(_kReportsCol)
        .where('listingId', isEqualTo: listingId)
        .where('buyerId', isEqualTo: buyerId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      debugPrint(
        '[BuyerDiscipline] duplicate_blocked listingId=$listingId buyerId=$buyerId',
      );
      throw Exception(
        'A report for this listing and buyer already exists. '
        'اس لسٹنگ اور خریدار پر پہلے سے رپورٹ موجود ہے۔',
      );
    }

    final ref = await db.collection(_kReportsCol).add(<String, dynamic>{
      'listingId': listingId,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'bidId': bidId,
      'reason': reason,
      'note': note.trim(),
      'status': 'pending',
      'strikeApplied': false,
      'createdAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewedBy': null,
    });

    debugPrint(
      '[BuyerDiscipline] report_submitted reportId=${ref.id} listingId=$listingId buyerId=$buyerId',
    );
    return ref.id;
  }

  // ─── Admin review ────────────────────────────────────────────────────────────

  /// Admin approves or rejects a pending report.
  ///
  /// [approved] = true  → applies a strike, updates completion rate.
  /// [approved] = false → marks rejected, no action on buyer.
  static Future<void> reviewReport({
    required String reportId,
    required bool approved,
    required String reviewedBy,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final reportRef = db.collection(_kReportsCol).doc(reportId);
    final reportSnap = await reportRef.get();

    if (!reportSnap.exists) {
      throw Exception('Report not found / رپورٹ نہیں ملی');
    }

    final data = reportSnap.data()!;
    final currentStatus = (data['status'] ?? '').toString();

    if (currentStatus != 'pending') {
      throw Exception(
        'Report already reviewed / رپورٹ پہلے ہی جائزہ لی جا چکی ہے',
      );
    }

    final newStatus = approved ? 'approved' : 'rejected';

    await reportRef.update(<String, dynamic>{
      'status': newStatus,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': reviewedBy,
    });

    if (approved) {
      final buyerId = (data['buyerId'] ?? '').toString();
      final reason = (data['reason'] ?? 'deal_failed').toString();
      if (buyerId.isNotEmpty) {
        await _applyStrikeFromReport(
          db: db,
          reportRef: reportRef,
          buyerId: buyerId,
          reason: reason,
        );
      }
    }

    debugPrint(
      '[BuyerDiscipline] review_done reportId=$reportId approved=$approved',
    );
  }

  // ─── Internal: apply strike ───────────────────────────────────────────────

  static Future<void> _applyStrikeFromReport({
    required FirebaseFirestore db,
    required DocumentReference<Map<String, dynamic>> reportRef,
    required String buyerId,
    required String reason,
  }) async {
    // Idempotent: check strikeApplied flag again inside transaction.
    await db.runTransaction<void>((txn) async {
      final reportSnap = await txn.get(reportRef);
      if (reportSnap.data()?['strikeApplied'] == true) {
        debugPrint('[BuyerDiscipline] strike_already_applied buyerId=$buyerId');
        return;
      }

      final userRef = db.collection(_kUsersCol).doc(buyerId);
      final userSnap = await txn.get(userRef);
      final userData = userSnap.data() ?? <String, dynamic>{};

      final int prevStrikes = _toInt(userData['strikeCount']);
      final int newStrikes = prevStrikes + 1;

      final int wonCount = _toInt(userData['auctionsWonCount']);
      final int prevFailed = _toInt(userData['auctionsFailedCount']);
      final int newFailed = prevFailed + 1;
      final int completedCount = _toInt(userData['auctionsCompletedCount']);

      final int rate = wonCount > 0
          ? ((completedCount / wonCount) * 100).round().clamp(0, 100)
          : 0;

      final Duration restriction = _restrictionForStrike(newStrikes);
      final DateTime? restrictUntil = restriction > Duration.zero
          ? DateTime.now().toUtc().add(restriction)
          : null;

      // Build strike history entry.
      final List<dynamic> history =
          List<dynamic>.from(userData['strikeHistory'] as List? ?? <dynamic>[]);
      history.add(<String, dynamic>{
        'reason': reason,
        'strikeNumber': newStrikes,
        'appliedAt': Timestamp.now(),
        'reportRef': reportRef.id,
      });

      final Map<String, dynamic> userUpdates = <String, dynamic>{
        'strikeCount': newStrikes,
        'lastStrikeAt': FieldValue.serverTimestamp(),
        'lastStrikeReason': reason,
        'strikeHistory': history,
        'auctionsFailedCount': newFailed,
        'completionRate': rate,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (restrictUntil != null) {
        userUpdates['bidRestrictionUntil'] =
            Timestamp.fromDate(restrictUntil);
        userUpdates['bidBlockedUntil'] =
            Timestamp.fromDate(restrictUntil); // mirrors existing field
      }

      if (newStrikes >= 3) {
        userUpdates['bidBlocked'] = true;
      }

      txn
        ..update(userRef, userUpdates)
        ..update(
          reportRef,
          <String, dynamic>{'strikeApplied': true},
        );

      debugPrint(
        '[BuyerDiscipline] strike_applied buyerId=$buyerId '
        'newStrikes=$newStrikes restriction=${restriction.inHours}h',
      );
    });
  }

  // ─── Public helpers ───────────────────────────────────────────────────────

  /// Recalculates [completionRate] from current counts and saves it.
  /// Call this when an auction is won or a deal is completed externally.
  static Future<void> recalcCompletionRate({
    required String buyerId,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final userRef = db.collection(_kUsersCol).doc(buyerId);

    await db.runTransaction<void>((txn) async {
      final snap = await txn.get(userRef);
      final data = snap.data() ?? <String, dynamic>{};
      final int won = _toInt(data['auctionsWonCount']);
      final int completed = _toInt(data['auctionsCompletedCount']);
      final int rate =
          won > 0 ? ((completed / won) * 100).round().clamp(0, 100) : 0;
      txn.update(userRef, <String, dynamic>{
        'completionRate': rate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Returns a human-friendly trust label for a buyer.
  ///
  /// [won]       = auctionsWonCount
  /// [rate]      = completionRate (0-100)
  /// [strikes]   = strikeCount
  static String trustLabel({
    required int won,
    required int rate,
    required int strikes,
  }) {
    if (strikes >= 3) return 'Restricted';
    if (won == 0) return 'New Buyer';
    if (rate >= 85 && won >= 5) return 'Serious Buyer';
    return 'Active Buyer';
  }

  // ─── Tiny helpers ─────────────────────────────────────────────────────────

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
