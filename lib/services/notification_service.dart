import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'phase1_notification_engine.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize({
    void Function(RemoteMessage message)? onNotificationTap,
    void Function(Map<String, dynamic> data)? onNotificationTapData,
  }) async {
    await _messaging.requestPermission();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        final payloadData = _parsePayload(response.payload);
        if (payloadData != null && onNotificationTapData != null) {
          onNotificationTapData(payloadData);
          return;
        }
        if (_latestForegroundMessage != null && onNotificationTap != null) {
          onNotificationTap(_latestForegroundMessage!);
        }
      },
    );

    const AndroidNotificationChannel engagementChannel =
        AndroidNotificationChannel(
      'engagement_alerts',
      'Engagement Alerts',
      description: 'Bid and marketplace engagement alerts',
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
    final String title = message.notification?.title ?? _titleForType(type);
    final String body = message.notification?.body ?? _bodyForType(type);

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
      payload: jsonEncode(
        _buildTapPayload(
          data: message.data,
          type: type,
          title: title,
          body: body,
        ),
      ),
    );
  }

  static Map<String, dynamic> _buildTapPayload({
    required Map<String, dynamic> data,
    required String type,
    required String title,
    required String body,
  }) {
    return <String, dynamic>{
      ...data,
      if ((data['type'] ?? '').toString().trim().isEmpty) 'type': type,
      if ((data['title'] ?? '').toString().trim().isEmpty) 'title': title,
      if ((data['body'] ?? '').toString().trim().isEmpty) 'body': body,
    };
  }

  static Map<String, dynamic>? _parsePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return null;
  }

  static String _titleForType(String type) {
    switch (type) {
      case Phase1NotificationType.listingApproved:
        return 'Listing Approved / لسٹنگ منظور ہوگئی';
      case Phase1NotificationType.newBidReceived:
        return 'New Bid / نئی بولی';
      case Phase1NotificationType.bidPlacedConfirmation:
        return 'Bid Placed / بولی لگ گئی';
      case Phase1NotificationType.outbid:
        return 'Outbid Alert / آپ کی بولی پیچھے رہ گئی';
      case Phase1NotificationType.bidAcceptedConfirmation:
        return 'Bid Accepted / بولی قبول کر لی گئی';
      case Phase1NotificationType.bidAccepted:
        return 'Bid Accepted / آپ کی بولی قبول ہوگئی';
      case Phase1NotificationType.auctionEndingSoon:
        return 'Auction Ending Soon / بولی جلد ختم ہو رہی ہے';
      case Phase1NotificationType.newRelevantListing:
        return 'New Listing Near You / آپ کے علاقے میں نئی لسٹنگ';
      default:
        return 'Digital Arhat Update / ڈیجیٹل آڑھت اپڈیٹ';
    }
  }

  static String _bodyForType(String type) {
    switch (type) {
      case Phase1NotificationType.listingApproved:
        return 'Your listing is now live. / آپ کی لسٹنگ اب لائیو ہے';
      case Phase1NotificationType.newBidReceived:
        return 'A buyer placed a new bid on your listing. / آپ کی لسٹنگ پر نئی بولی آئی ہے';
      case Phase1NotificationType.bidPlacedConfirmation:
        return 'Your bid has been submitted successfully. / آپ کی بولی کامیابی سے لگ گئی ہے';
      case Phase1NotificationType.outbid:
        return 'A higher bid has been placed. / کسی اور نے زیادہ بولی لگا دی ہے';
      case Phase1NotificationType.bidAcceptedConfirmation:
        return 'Contact has been unlocked. / رابطہ اَن لاک ہو گیا ہے';
      case Phase1NotificationType.bidAccepted:
        return 'Contact is now unlocked. / رابطہ اَن لاک ہو گیا ہے';
      case Phase1NotificationType.auctionEndingSoon:
        return 'This auction is about to close. / یہ بولی جلد بند ہونے والی ہے';
      case Phase1NotificationType.newRelevantListing:
        return 'A relevant listing is available in your area. / آپ کے علاقے میں نئی آفر آئی ہے';
      default:
        return 'New update available. / نیا اپڈیٹ دستیاب ہے';
    }
  }

  static Future<String?> getToken() async => await _messaging.getToken();

  static bool isDealAlert(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().toUpperCase();
    return Phase1NotificationType.all.contains(type);
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
      title: 'Bid Accepted / بولی قبول ہوگئی',
      body: 'Your bid was accepted. Contact is now unlocked. / آپ کی بولی قبول ہوگئی، رابطہ اَن لاک ہے',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'APPROVED_WINNER',
    );
  }
}
