import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth/auth_wrapper.dart';
import 'dashboard/buyer/buyer_dashboard.dart';
import 'dashboard/role_router.dart';
import 'firebase_options.dart';
import 'routes.dart';
import 'services/ai_generative_service.dart';
import 'services/analytics_service.dart';
import 'services/deep_link_service.dart';
import 'services/notification_service.dart';
import 'services/phase1_notification_engine.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _appCheckActivated = false;

Future<void> _logRuntimeFirebaseIdentity() async {
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final FirebaseOptions options = Firebase.app().options;
    debugPrint(
      '[FirebaseIdentity] package=${packageInfo.packageName} appName=${packageInfo.appName} '
      'version=${packageInfo.version} build=${packageInfo.buildNumber}',
    );
    debugPrint(
      '[FirebaseIdentity] appId=${options.appId} projectId=${options.projectId} '
      'messagingSenderId=${options.messagingSenderId} apiKeySuffix=${options.apiKey.length >= 6 ? options.apiKey.substring(options.apiKey.length - 6) : options.apiKey}',
    );
  } catch (e) {
    debugPrint('[FirebaseIdentity] runtime identity log failed: $e');
  }
}

Future<void> _activateAppCheckSafely() async {
  if (_appCheckActivated) {
    debugPrint('APP START AFTER APP CHECK (already activated)');
    debugPrint('[AppCheck] Activation skipped (already activated)');
    return;
  }

  // Allow forcing debug provider in special QA runs with
  // --dart-define=APP_CHECK_DEBUG=true.
  const forceDebugAppCheck = bool.fromEnvironment(
    'APP_CHECK_DEBUG',
    defaultValue: false,
  );
  // Use debug App Check provider for debug and profile builds (flutter run /
  // ADB installs). Only use Play Integrity for true Play Store release builds.
  // This prevents App Check token failures from compounding Phone Auth issues
  // in development environments where Play Integrity is unavailable.
  final useDebugProvider = kDebugMode || kProfileMode || forceDebugAppCheck;

  debugPrint(
    '[AppCheck] Branch selected: ${useDebugProvider ? 'DEBUG provider' : 'RELEASE Play Integrity provider'} '
    '(kDebugMode=$kDebugMode, APP_CHECK_DEBUG=$forceDebugAppCheck)',
  );
  debugPrint('[AppCheck] Activation starting');

  await FirebaseAppCheck.instance.activate(
    providerAndroid: useDebugProvider
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: useDebugProvider
        ? const AppleDebugProvider()
        : const AppleDeviceCheckProvider(),
  );
  debugPrint('[AppCheck] Activation succeeded');
  _appCheckActivated = true;
}

Future<void> main() async {
  debugPrint('APP START REACHED MAIN');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('APP START BEFORE FIREBASE INIT');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('APP START AFTER FIREBASE INIT');
  await _logRuntimeFirebaseIdentity();
  debugPrint('APP START BEFORE APP CHECK');
  await _activateAppCheckSafely();
  debugPrint('APP START AFTER APP CHECK');
  runApp(const DigitalArhatApp());
}

class InitializationService {
  static bool _started = false;
  static bool _completed = false;
  static bool _firebaseReady = false;

  static bool get isCompleted => _completed;
  static bool get isFirebaseReady => _firebaseReady;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      await Future.any<void>([
        _initializeAll(),
        Future<void>.delayed(
          const Duration(seconds: 12),
          () => throw TimeoutException('Startup timeout'),
        ),
      ]);
    } catch (_) {
    } finally {
      _completed = true;
    }
  }

  static Future<void> _initializeAll() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _firebaseReady = true;

    try {
      await _activateAppCheckSafely();
    } catch (_) {}

    await Future.any<void>([
      Future.wait<void>([
        _setupInteractedMessage(),
        NotificationService.initialize(
          onNotificationTap: _handleMessage,
          onNotificationTapData: _handleMessageData,
        ),
        DeepLinkService.initialize(
          onListingDeepLink: (listingId) async {
            await AnalyticsService().logJoinAttribution(
              source: 'WhatsApp Share',
              listingId: listingId,
            );
            _openListingDetails(listingId);
          },
        ),
      ]).then((_) {}),
      Future<void>.delayed(const Duration(seconds: 8)),
    ]);

    try {
      await MandiIntelligenceService().initialize().timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    } catch (_) {}
  }
}

Future<void> _setupInteractedMessage() async {
  try {
    final messaging = FirebaseMessaging.instance;
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }
  } catch (_) {}
}

void _handleMessage(RemoteMessage message) {
  _handleMessageData(message.data);
}

void _handleMessageData(Map<String, dynamic> messageData) {
  final listingId = messageData['listingId']?.toString() ?? '';
  final type = (messageData['type'] ?? '').toString().toUpperCase();
  final targetRole = (messageData['targetRole'] ?? '')
      .toString()
      .trim()
      .toLowerCase();

  unawaited(
    AnalyticsService().logJoinAttribution(
      source: 'Push Notification',
      listingId: listingId,
    ),
  );

  if (type == 'LISTING_DEEP_LINK' && listingId.isNotEmpty) {
    _openListingDetails(listingId);
    return;
  }

  if (type == 'BID_UPDATE' && listingId.isNotEmpty) {
    navigatorKey.currentState?.pushNamed(
      Routes.placeBid,
      arguments: {'docId': listingId},
    );
    return;
  }

  if (Phase1NotificationType.all.contains(type)) {
    if (targetRole == 'seller' ||
        type == Phase1NotificationType.listingApproved ||
        type == Phase1NotificationType.newBidReceived ||
        type == Phase1NotificationType.bidAcceptedConfirmation) {
      navigatorKey.currentState?.pushNamed(
        Routes.sellerDashboard,
        arguments: <String, dynamic>{
          if (listingId.isNotEmpty) 'listingId': listingId,
          'focus': 'bids',
        },
      );
      return;
    }

    if (listingId.isNotEmpty) {
      _openListingDetails(listingId);
      return;
    }

    navigatorKey.currentState?.pushNamed(
      Routes.buyerDashboard,
      arguments: const <String, dynamic>{},
    );
    return;
  }
}

void _openListingDetails(String listingId) {
  if (listingId.trim().isEmpty) return;
  navigatorKey.currentState?.pushNamed(
    Routes.listingDetails,
    arguments: <String, dynamic>{'listingId': listingId},
  );
}

class DigitalArhatApp extends StatelessWidget {
  const DigitalArhatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Arhat',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      routes: <String, WidgetBuilder>{...Routes.getRoutes()},
        initialRoute: Routes.authWrapper,
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(child: Text('Mandi Band Hai (Route Not Found)')),
        ),
      ),
    );
  }
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate();

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  bool _showVersionGuard = false;

  @override
  void initState() {
    super.initState();
    unawaited(_warmupInBackground());
  }

  Future<void> _warmupInBackground() async {
    await InitializationService.start();

    if (!mounted) return;

    if (!InitializationService.isFirebaseReady) {
      setState(() => _showVersionGuard = false);
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        setState(() => _showVersionGuard = true);
      }
    } catch (_) {
      setState(() => _showVersionGuard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!InitializationService.isCompleted) {
      return const AuthWrapper();
    }

    if (!InitializationService.isFirebaseReady) {
      return const BuyerDashboard(userData: <String, dynamic>{});
    }

    return _showVersionGuard
        ? const VersionGuard(child: _AuthSessionRoot())
        : const _AuthSessionRoot();
  }
}

class _AuthSessionRoot extends StatelessWidget {
  const _AuthSessionRoot();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ColoredBox(color: Colors.transparent);
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthWrapper();
        }
        return const RoleRouter();
      },
    );
  }
}

class VersionGuard extends StatefulWidget {
  final Widget child;
  const VersionGuard({super.key, required this.child});

  @override
  State<VersionGuard> createState() => _VersionGuardState();
}

class _VersionGuardState extends State<VersionGuard> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVersionLock());
  }

  Future<void> _checkVersionLock() async {
    try {
      if (!InitializationService.isCompleted) return;
      if (FirebaseAuth.instance.currentUser == null) return;

      final appInfo = await PackageInfo.fromPlatform();
      final configDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version_guard')
          .get();

      final minVersion = configDoc.data()?['min_app_version']?.toString() ?? '';
      if (minVersion.isNotEmpty &&
          _isLowerVersion(appInfo.version, minVersion)) {
        if (!mounted || _dialogShown) return;
        setState(() => _dialogShown = true);
        _showUpdateDialog(appInfo.version, minVersion);
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return;
      }
      return;
    } catch (_) {
      return;
    }
  }

  void _showUpdateDialog(String current, String min) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update Required'),
          content: Text(
            'A newer version ($min) is required. Current: $current',
          ),
          actions: [
            TextButton(onPressed: () {}, child: const Text('Go to Store')),
          ],
        ),
      ),
    );
  }

  bool _isLowerVersion(String current, String minimum) {
    List<int> parse(String input) => input
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final c = parse(current);
    final m = parse(minimum);

    for (int i = 0; i < 3; i++) {
      final cv = i < c.length ? c[i] : 0;
      final mv = i < m.length ? m[i] : 0;
      if (cv < mv) return true;
      if (cv > mv) return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
