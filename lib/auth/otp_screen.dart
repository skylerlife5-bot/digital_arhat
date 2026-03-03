import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../routes.dart';

class OtpScreen extends StatefulWidget {
  final String? verificationId;
  const OtpScreen({super.key, this.verificationId});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyOtp() async {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final String vId = args?['verificationId'] ?? widget.verificationId ?? '';
    final String roleFromUI = args?['role'] ?? 'buyer';
    final Map<String, dynamic> payloadFromSignup =
        (args?['userData'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    if (_otpController.text.length < 6 && !kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text("Pura code likhen")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (kIsWeb) {
        Navigator.pushNamedAndRemoveUntil(context, Routes.roleRouter, (route) => false);
        return;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: _otpController.text.trim(),
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        String finalRole = roleFromUI;
        String uid = userCredential.user!.uid;

        // �x� CHECK: Pehle se maujood role check karen
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        if (userDoc.exists) {
          String? existingRole = (userDoc.data() as Map<String, dynamic>)['role'];
          // �x: Agar user Admin ya Arhat hai, to uska role change mat karo
          if (existingRole == 'admin' || existingRole == 'arhat') {
            finalRole = existingRole!;
          }
        }

        // �x� Save/Update user data
        final mergedUserData = <String, dynamic>{
          ...payloadFromSignup,
          'uid': uid,
          'role': finalRole, 
          'phone': userCredential.user!.phoneNumber,
          'is_verified': true,
          'lastLogin': FieldValue.serverTimestamp(),
        };

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(mergedUserData, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, Routes.roleRouter, (route) => false);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text("Ghalat Code! Error: ${e.toString()}")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF012210),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.lock_clock_rounded, size: 80, color: Color(0xFFFFD700)),
            const SizedBox(height: 20),
            Text(
              "Code Tashdeeq Karen",
              style: GoogleFonts.playfairDisplay(
                fontSize: 28, 
                fontWeight: FontWeight.bold, 
                color: Colors.white
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "6-hindo ka code yahan likhen", 
              style: TextStyle(color: Colors.white70)
            ),
            const SizedBox(height: 40),
            if (!kIsWeb)
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                  color: Color(0xFFFFD700), 
                  fontSize: 32, 
                  letterSpacing: 10
                ),
                decoration: const InputDecoration(
                  counterText: "",
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFFD700))
                  ),
                ),
              ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)
                  ),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Color(0xFF012210))
                  : const Text(
                      kIsWeb ? "Skip for Web" : "Verify & Continue", 
                      style: TextStyle(
                        color: Color(0xFF012210), 
                        fontSize: 18, 
                        fontWeight: FontWeight.bold
                      )
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
