import 'package:flutter/material.dart';
import '../../ai/trust_score_engine.dart';

class TrustBadgeWidget extends StatelessWidget {
  final String userId;
  
  const TrustBadgeWidget({
    super.key, 
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final engine = TrustScoreEngine();

    return FutureBuilder<int>(
      future: engine.calculateUserScore(userId),
      builder: (context, snapshot) {
        // Jab tak data load ho raha ho, chota loading indicator dikhayein
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 20, 
            width: 20, 
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)
          );
        }

        if (!snapshot.hasData) return const SizedBox.shrink();

        int score = snapshot.data!;
        String badgeLabel = engine.getTrustBadge(score);
        
        // �x}� Modern Color Logic
        Color badgeColor;
        IconData badgeIcon;

        if (score >= 85) {
          badgeColor = Colors.amber; // Gold Badge
          badgeIcon = Icons.verified_rounded;
        } else if (score >= 65) {
          badgeColor = Colors.blueGrey; // Silver Badge
          badgeIcon = Icons.shield_rounded;
        } else {
          badgeColor = Colors.blueAccent; // Bronze/Regular
          badgeIcon = Icons.stars_rounded;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            // �S& Fixed: using withValues instead of withOpacity
            color: badgeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 14, color: badgeColor),
              const SizedBox(width: 6),
              Text(
                "$badgeLabel ($score)",
                style: TextStyle(
                  color: badgeColor, 
                  fontSize: 11, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
