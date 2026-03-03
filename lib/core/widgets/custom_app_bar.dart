import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/session_service.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    this.title = 'Digital Arhat',
    this.titleWidget,
    this.centerTitle = true,
    this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.actions = const <Widget>[],
    this.showSettings = true,
    this.onLogout,
  });

  final String title;
  final Widget? titleWidget;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color foregroundColor;
  final List<Widget> actions;
  final bool showSettings;
  final Future<void> Function(BuildContext context)? onLogout;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _openSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F2C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.settings, color: Colors.white70),
                  title: Text(
                    'Settings',
                    style: GoogleFonts.merriweather(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text(
                    'Logout',
                    style: GoogleFonts.inter(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (onLogout != null) {
                      await onLogout!(context);
                    } else {
                      await SessionService.logoutToLogin(context);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: centerTitle,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      title: titleWidget ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo.png',
                height: 34,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.merriweather(
                  fontWeight: FontWeight.w700,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
      actions: [
        ...actions,
        if (showSettings)
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
    );
  }
}

