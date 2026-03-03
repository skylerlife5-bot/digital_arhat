import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import '../../core/constants.dart';

class MandiTickerWidget extends StatelessWidget {
  const MandiTickerWidget({
    super.key,
    this.selectedType,
  });

  final MandiType? selectedType;

  static const List<String> _newsItems = [
    'Mandi Update: Aaj gandum aur chawal ke rate barhnay ka imkan hai.',
    'Zaruri Ittallat: Malumat sahi bharen taake koi masla na ho.',
    'Digital Arhat: Aap ka bharosa, hamari pehchan.',
  ];

  @override
  Widget build(BuildContext context) {
    final text = _newsItems.join('   |   ');

    return Container(
      height: 35.0,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.newspaper, color: Color(0xFF0D47A1), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 35.0,
              child: Marquee(
                text: text,
                scrollAxis: Axis.horizontal,
                blankSpace: 28,
                velocity: 35,
                pauseAfterRound: const Duration(milliseconds: 800),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

