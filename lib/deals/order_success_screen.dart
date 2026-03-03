import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/widgets/ethical_verse_banner.dart';
import '../routes.dart';

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F1),
      appBar: AppBar(
        title: Text(
          'Order Kamyab',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EthicalVerseBanner(maxItems: 2),
              const SizedBox(height: 14),
              const Icon(Icons.check_circle, size: 76, color: Colors.green),
              const SizedBox(height: 12),
              Text(
                'Alhamdulillah! Aap ka order kamyabi se submit ho gaya hai.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Imandaar tijarat aur durust naap tol mein barkat hai.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  Routes.roleRouter,
                  (route) => false,
                ),
                child: Text(
                  'Dashboard par wapas jayein',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}