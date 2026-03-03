import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_colors.dart';

class UserApproval extends StatelessWidget {
  const UserApproval({super.key});

  // �S& User Status Handler with Rejection Logic
  Future<void> _handleUserStatus(BuildContext context, String userId, bool approve) async {
    String? rejectionReason;

    if (!approve) {
      // Rejection ke liye reason mangna zaroori hai
      rejectionReason = await _showRejectionDialog(context);
      if (rejectionReason == null) return; // Agar cancel kiya
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'verificationStatus': approve ? 'verified' : 'rejected',
        'rejectionReason': approve ? null : rejectionReason,
        'trustScore': approve ? 100 : 0, // Pehla aitemad reward
        'verifiedAt': approve ? FieldValue.serverTimestamp() : null,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
            content: Text(approve ? "User Verified! Mubarak ho." : "User Reject kar diya gaya."),
            backgroundColor: approve ? AppColors.primaryGreen : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF7),
      appBar: AppBar(
        title: const Text("User Verification Portal", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildInfoBanner(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('verificationStatus', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var userDoc = snapshot.data!.docs[index];
                    var userData = userDoc.data() as Map<String, dynamic>;

                    return _buildUserApprovalCard(context, userData, userDoc.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // �S& User Card UI
  Widget _buildUserApprovalCard(BuildContext context, Map<String, dynamic> userData, String userId) {
    final String? cnicFrontUrl = (userData['cnicFrontUrl'] ?? userData['cnicImageUrl'])?.toString();
    final String? cnicBackUrl = (userData['cnicBackUrl'] ?? userData['cnicImageUrl'])?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.1),
          child: Text(userData['name']?[0] ?? "U", 
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
        ),
        title: Text(userData['name'] ?? "Unknown User", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Role: ${userData['role']?.toString().toUpperCase() ?? 'N/A'}", 
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                _infoRow(Icons.privacy_tip, "Contact:", 'Hidden (In-App only)'),
                _infoRow(Icons.location_on, "Address:", userData['address'] ?? 'Pata Mojood Nahi'),
                const SizedBox(height: 15),
                const Text("CNIC Front aur Back Tasveer:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildCnicPreviewCard(
                        context,
                        label: 'Front Side',
                        imageUrl: cnicFrontUrl,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildCnicPreviewCard(
                        context,
                        label: 'Back Side',
                        imageUrl: cnicBackUrl,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton("Reject", Colors.red, () => _handleUserStatus(context, userId, false)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _actionButton("Approve", AppColors.primaryGreen, () => _handleUserStatus(context, userId, true)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 5),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.amber[50],
      child: const Row(
        children: [
          Icon(Icons.gpp_maybe, color: Colors.orange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Dhyan se CNIC verify karein. Galat approval platform ki safety ko khatre mein daal sakti hai.",
              style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text("Sab Users Verified Hain!", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCnicPreviewCard(
    BuildContext context, {
    required String label,
    required String? imageUrl,
  }) {
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: hasImage ? () => _showFullScreenImage(context, imageUrl) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: hasImage
                ? Image.network(
                    imageUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                  )
                : Container(
                    height: 150,
                    color: Colors.grey[100],
                    child: const Center(child: Text("Image Missing")),
                  ),
          ),
        ),
      ],
    );
  }

  // �S& Rejection Dialog to ask for reason
  Future<String?> _showRejectionDialog(BuildContext context) async {
    TextEditingController reasonController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rejection ka Sabab?"),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: "e.g. Image clear nahi hai / Invalid CNIC"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Confirm Reject"),
          ),
        ],
      ),
    );
  }

  // �S& View Image Full Screen
  void _showFullScreenImage(BuildContext context, String? url) {
    if (url == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: const CloseButton(color: Colors.white)),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}
