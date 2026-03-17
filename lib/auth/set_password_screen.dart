import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../routes.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  String _pin = "";
  bool _isLoading = false;

  void _onKeyTap(String value) {
    if (_pin.length < 6) {
      setState(() => _pin += value);
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  // --- �x:�️ Logic: Save PIN ---
  Future<void> _savePinAndFinish() async {
    if (_pin.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text("6 hindson ka PIN set karein")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // PIN update in Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'pin': _pin,
          'is_setup_complete': true,
        });

        // �S& FIX: Async Gap Check
        if (!mounted) return;

        Navigator.pushNamedAndRemoveUntil(
          context, 
          Routes.verificationPending, 
          (route) => false
        );
      }
    } catch (e) {
      // �S& FIX: Async Gap Check for Error handling
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text("Error: ${e.toString()}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 50),
            const Icon(Icons.lock_outline, color: Color(0xFFFFD700), size: 60)
                .animate().shake(),
            const SizedBox(height: 20),
            const Text(
              "اپ� ا خف�Rہ پ�  (PIN) س�Rٹ کر�Rں",
              style: TextStyle(color: Color(0xFFFFD700), fontSize: 26, fontFamily: 'Jameel Noori'),
            ),
            const Text(
              "6-Digit Secure PIN for your account",
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // PIN Display Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _pin.length ? const Color(0xFFFFD700) : Colors.white10,
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.5), // �S& Updated standard
                      width: 1,
                    ),
                  ),
                );
              }),
            ),

            const Spacer(),

            // Custom Number Pad
            _buildNumPad(),

            const SizedBox(height: 20),
            
            // Finish Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _savePinAndFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Color(0xFF011A0A))
                    : const Text("�&حف��ظ کر�Rں / Save & Finish", 
                        style: TextStyle(color: Color(0xFF011A0A), fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildNumPad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.5,
        ),
        itemCount: 12,
        itemBuilder: (context, index) {
          if (index == 9) {
            // Khali space ki jagah clear button bhi de sakte hain
            return IconButton(
              onPressed: () => setState(() => _pin = ""),
              icon: const Icon(Icons.refresh, color: Colors.white38),
            );
          }
          if (index == 10) return _buildNumButton("0");
          if (index == 11) {
            return IconButton(
              onPressed: _onDelete,
              icon: const Icon(Icons.backspace_outlined, color: Colors.white70),
            );
          }
          return _buildNumButton("${index + 1}");
        },
      ),
    );
  }

  Widget _buildNumButton(String text) {
    return InkWell(
      onTap: () => _onKeyTap(text),
      borderRadius: BorderRadius.circular(50),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
