import 'package:flutter/material.dart';

import '../../services/realtime_agri_rates_service.dart';

class AgriRatesGoldCard extends StatelessWidget {
  const AgriRatesGoldCard({
    super.key,
    required this.ratesStream,
  });

  final Stream<List<AgriRatePoint>> ratesStream;

  static const Color _deepGreen = Color(0xFF004D40);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFF2C4), Color(0xFFFFD54F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: StreamBuilder<List<AgriRatePoint>>(
        stream: ratesStream,
        builder: (context, snapshot) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.show_chart, color: _deepGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Real-time Agri Rates',
                      style: TextStyle(
                        color: _deepGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 82,
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: const <Widget>[
                    _RateItemRow(
                      commodityLabel: 'Gandum (Wheat)',
                      valueLabel: 'Rs. 4,500',
                    ),
                    SizedBox(height: 8),
                    _RateItemRow(
                      commodityLabel: 'Kapaas (Cotton)',
                      valueLabel: 'Rs. 8,200',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RateItemRow extends StatelessWidget {
  const _RateItemRow({
    required this.commodityLabel,
    required this.valueLabel,
  });

  final String commodityLabel;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              commodityLabel,
              style: const TextStyle(
                color: Color(0xFF004D40),
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              valueLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF004D40),
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

