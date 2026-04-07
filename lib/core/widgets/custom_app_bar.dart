import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../assets.dart';
import '../../services/session_service.dart';
import '../../theme/app_colors.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    this.title = 'Digital Arhat',
    this.titleWidget,
    this.centerTitle = true,
    this.backgroundColor,
    this.foregroundColor = AppColors.primaryText,
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
    const Color sheetBg = Color(0xFF0A3D2E);
    const Color sheetText = Color(0xFFF3F0E6);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  leading: const Icon(
                    Icons.settings,
                    color: sheetText,
                  ),
                  title: Text(
                    'Settings',
                    style: GoogleFonts.merriweather(
                      color: sheetText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  leading: const Icon(
                    Icons.logout,
                    color: AppColors.urgencyRed,
                  ),
                  title: Text(
                    'Logout',
                    style: GoogleFonts.inter(
                      color: AppColors.urgencyRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final bool? shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) {
                        return AlertDialog(
                          backgroundColor: sheetBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Text(
                            'لاگ آؤٹ',
                            style: GoogleFonts.merriweather(
                              color: sheetText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          content: Text(
                            'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟',
                            style: GoogleFonts.inter(
                              color: sheetText,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: Text(
                                'نہیں',
                                style: GoogleFonts.inter(color: sheetText),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: Text(
                                'ہاں',
                                style: GoogleFonts.inter(
                                  color: AppColors.urgencyRed,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                    if (shouldLogout != true) return;
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
      title:
          titleWidget ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                AppAssets.logoPath,
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
