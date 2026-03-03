import 'package:flutter/material.dart';
import 'buyer_home_screen.dart';

class BuyerDashboard extends StatefulWidget {
  final Map<String, dynamic> userData; 
  const BuyerDashboard({super.key, required this.userData});

  @override
  State<BuyerDashboard> createState() => _BuyerDashboardState();
}

class _BuyerDashboardState extends State<BuyerDashboard> {
  @override
  Widget build(BuildContext context) {
    return BuyerHomeScreen(userData: widget.userData);
  }
}
