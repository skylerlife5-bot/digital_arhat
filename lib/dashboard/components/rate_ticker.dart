import 'package:flutter/material.dart';
import '../../services/market_rate_service.dart';

class RateTicker extends StatelessWidget {
  const RateTicker({super.key});

  /// �S& Initial data aur Stream ko combine karne ka behtareen tareeqa
  /// Taaki app start hote hi purana data dikhaye aur background mein AI fetch kare
  Stream<List<MarketRate>> _combinedStream(MarketRateService service) async* {
    // 1. Foran pichli cache ya default rates dikhao
    yield service.getLatestRates(); 
    
    // 2. Phir live updates (Gemini AI + Random fluctuations) shuru karo
    yield* service.getLiveRateStream();
  }

  @override
  Widget build(BuildContext context) {
    // Singleton instance access
    final rateService = MarketRateService();

    return Container(
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: StreamBuilder<List<MarketRate>>(
        stream: _combinedStream(rateService),
        builder: (context, snapshot) {
          // Jab tak AI pehli baar data na bhej de
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                  ),
                  SizedBox(width: 10),
                  Text(
                    "AI Fetching Live Mandi Rates...",
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }

          final rates = snapshot.data!;

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: rates.length,
            itemBuilder: (context, index) {
              final rate = rates[index];
              final bool isUp = rate.trend == "up";

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Crop Name (Golden/Amber color for emphasis)
                    Text(
                      rate.cropName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 13,
                        color: Color(0xFFB8860B), // Dark Golden Rod
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Price
                    Text(
                      "Rs. ${rate.currentPrice}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Arrow Icon
                    Icon(
                      isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: isUp ? Colors.green : Colors.red,
                      size: 28,
                    ),
                    // Percentage/Change
                    Text(
                      rate.change.abs().toStringAsFixed(1),
                      style: TextStyle(
                        color: isUp ? Colors.green : Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 15),
                    // Divider between items
                    VerticalDivider(
                      color: Colors.grey.withValues(alpha: 0.2),
                      indent: 12,
                      endIndent: 12,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
