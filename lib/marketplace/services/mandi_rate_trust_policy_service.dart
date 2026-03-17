import '../models/live_mandi_rate.dart';

class AuctionMandiReference {
  const AuctionMandiReference({
    required this.officialMedian,
    required this.humanCorroboratedMedian,
    required this.lowConfidenceMedian,
    required this.referenceReason,
  });

  final double? officialMedian;
  final double? humanCorroboratedMedian;
  final double? lowConfidenceMedian;
  final String referenceReason;
}

class MandiRateTrustPolicyService {
  const MandiRateTrustPolicyService();

  int priorityRank(LiveMandiRate rate) {
    final vStatus = rate.verificationStatus.trim().toLowerCase();
    if (_isOfficial(rate) &&
        (vStatus == 'official verified' || vStatus == 'official_verified')) {
      return 1;
    }
    if (_isOfficial(rate) &&
        (vStatus == 'cross-checked' || vStatus == 'cross_checked')) {
      return 2;
    }

    if (_isVerifiedHuman(rate) && _hasStrongHumanCorroboration(rate)) return 3;
    if (rate.isTrustedLocalContributor && _hasStrongHumanCorroboration(rate)) return 4;
    if (!_isOfficial(rate) && !rate.isRejectedContribution) return 5;
    return 6;
  }

  bool canPromoteOnHome(
    LiveMandiRate rate, {
    required bool hasStrongOfficialEquivalent,
  }) {
    if (rate.isRejectedContribution) return false;

    final rank = priorityRank(rate);
    if (rank <= 2) return true;

    if (rate.needsReview) return false;
    if (!rate.acceptedBySystem && !rate.acceptedByAdmin) return false;

    if (hasStrongOfficialEquivalent) {
      return rank <= 4 &&
          (rate.confidenceScore >= 0.82 || (rate.trustScore ?? 0) >= 0.84);
    }

    return rank <= 4 &&
        rate.confidenceScore >= 0.72 &&
        (rate.reviewStatus == 'accepted' ||
            rate.verificationStatus == 'Cross-Checked');
  }

  AuctionMandiReference buildAuctionReference(List<LiveMandiRate> rates) {
    final official = rates.where(_isOfficial).map((r) => r.price).where((p) => p > 0).toList(growable: false);
    final humanCorroborated = rates
        .where((r) => !_isOfficial(r) && _hasStrongHumanCorroboration(r))
        .map((r) => r.price)
        .where((p) => p > 0)
        .toList(growable: false);
    final lowConfidence = rates
        .where((r) => !_isOfficial(r) && (r.isLimitedConfidenceHuman || r.needsReview))
        .map((r) => r.price)
        .where((p) => p > 0)
        .toList(growable: false);

    return AuctionMandiReference(
      officialMedian: _median(official),
      humanCorroboratedMedian: _median(humanCorroborated),
      lowConfidenceMedian: _median(lowConfidence),
      referenceReason:
          'official_first_with_human_gap_fill; low_confidence_kept_separate',
    );
  }

  bool _isOfficial(LiveMandiRate rate) {
    return rate.contributorType.isEmpty ||
        rate.contributorType == 'official' ||
        rate.sourceType == 'official_aggregator' ||
        rate.sourceType == 'official_market_committee' ||
        rate.sourceType == 'official_commissioner';
  }

  bool _isVerifiedHuman(LiveMandiRate rate) {
    return rate.isVerifiedHumanContributor;
  }

  bool _hasStrongHumanCorroboration(LiveMandiRate rate) {
    return rate.corroborationCount >= 2 &&
        (rate.confidenceScore >= 0.7 || (rate.trustScore ?? 0) >= 0.72);
  }

  double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
