import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerSupportHelper {
  static const String supportNumber = '+923024090114';

  static String resolveUserName([String? fallbackName]) {
    final current = FirebaseAuth.instance.currentUser;
    final byArg = (fallbackName ?? '').trim();
    if (byArg.isNotEmpty) return byArg;

    final displayName = (current?.displayName ?? '').trim();
    if (displayName.isNotEmpty) return displayName;

    return 'User';
  }

  static Future<void> openWhatsAppSupport(
    BuildContext context, {
    String? userName,
  }) async {
    final resolvedName = resolveUserName(userName);
    final message =
        'Asalam-o-Alaikum Digital Arhat Support, mujhe $resolvedName ki taraf se madad chahiye.';

    final waUri = Uri.parse(
      'https://wa.me/${supportNumber.replaceAll('+', '')}?text=${Uri.encodeComponent(message)}',
    );

    final opened = await launchUrl(waUri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('WhatsApp open nahi ho saka.')),
      );
    }
  }
}

class CustomerSupportFab extends StatelessWidget {
  const CustomerSupportFab({
    super.key,
    this.userName,
    this.mini = true,
  });

  final String? userName;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'support_fab_${mini ? 'mini' : 'full'}',
      mini: mini,
      backgroundColor: const Color(0xFF25D366),
      onPressed: () => CustomerSupportHelper.openWhatsAppSupport(
        context,
        userName: userName,
      ),
      child: const Icon(Icons.support_agent, color: Colors.white),
    );
  }
}

class CustomerSupportIconAction extends StatelessWidget {
  const CustomerSupportIconAction({
    super.key,
    this.userName,
    this.color,
  });

  final String? userName;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Support',
      onPressed: () => CustomerSupportHelper.openWhatsAppSupport(
        context,
        userName: userName,
      ),
      icon: Icon(Icons.support_agent, color: color ?? Colors.white70),
    );
  }
}

