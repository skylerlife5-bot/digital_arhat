import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize({
    void Function(RemoteMessage message)? onNotificationTap,
  }) async {
    await _messaging.requestPermission();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (_) {
        if (_latestForegroundMessage != null && onNotificationTap != null) {
          onNotificationTap(_latestForegroundMessage!);
        }
      },
    );

    const AndroidNotificationChannel engagementChannel =
        AndroidNotificationChannel(
      'engagement_alerts',
      'Engagement Alerts',
      description: 'Escrow confirmations and mandi price alerts',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(engagementChannel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (onNotificationTap != null) {
        onNotificationTap(message);
      }
    });
  }

  static RemoteMessage? _latestForegroundMessage;

  static void _showLocalNotification(RemoteMessage message) {
    _latestForegroundMessage = message;

    final String type = (message.data['type'] ?? '').toString().toUpperCase();
    final bool isEscrow =
        type == 'ESCROW_CONFIRMED' || type == 'ESCROW_CONFIRMATION';
    final bool isPriceAlert = type == 'PRICE_ALERT';
    final bool isDealAlert =
      type == 'DEAL_ALERT' || type == 'DEAL_UPDATE' || type == 'ESCROW_ALERT';

    final title = message.notification?.title ??
        (isEscrow
            ? 'Escrow Confirmation'
        : (isPriceAlert
          ? 'Price Alert'
          : (isDealAlert ? 'Deal Alert' : 'Digital Arhat Update')));

    final body = message.notification?.body ??
        (isEscrow
            ? 'Paisy Escrow mein jama ho gaye hain. Maal rawana karen.'
            : (isPriceAlert
                ? 'Gandum ke rates Punjab mein barh gaye hain! Check karen.'
          : (isDealAlert
            ? 'Aap ki deal mein nayi progress hui hai. Tafseel dekhein.'
            : 'Naya update dastyab hai.')));

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'engagement_alerts',
      'Engagement Alerts',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );

    _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: type,
    );
  }

  static Future<String?> getToken() async => await _messaging.getToken();

  static bool isDealAlert(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().toUpperCase();
    return type == 'DEAL_ALERT' ||
        type == 'DEAL_UPDATE' ||
        type == 'ESCROW_ALERT' ||
        type == 'ESCROW_CONFIRMED' ||
        type == 'ESCROW_CONFIRMATION';
  }

  static Future<void> showApprovedWinnerNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'engagement_alerts',
      'Engagement Alerts',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Mubarak ho!',
      body:
          'Mubarak ho! Aap ki boli manzoor ho gayi hai. Payment kar ke apna maal hasil karein.',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'APPROVED_WINNER',
    );
  }
}
