import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Android için bildirim kanalı oluştur
    const androidChannel = AndroidNotificationChannel(
      'vehicle_tracking_channel',
      'Araç Takibi',
      description: 'Araç durağa yaklaştığında bildirim gönderir',
      importance: Importance.max, // ✅ HIGH yerine MAX
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _isInitialized = true;
    debugPrint('✅ NotificationService başlatıldı');
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Bildirime tıklandı: ${response.payload}');
  }

  // ✅ İzin durumunu kontrol et ve logla
  Future<bool> checkPermission() async {
    final status = await Permission.notification.status;
    debugPrint('🔔 Bildirim izni durumu: $status');

    if (status.isGranted) {
      debugPrint('✅ Bildirim izni VAR');
      return true;
    } else if (status.isDenied) {
      debugPrint('❌ Bildirim izni YOK - İsteniyor...');
      final result = await Permission.notification.request();
      final granted = result.isGranted;
      debugPrint(granted ? '✅ İzin VERİLDİ' : '❌ İzin REDDEDİLDİ');
      return granted;
    } else if (status.isPermanentlyDenied) {
      debugPrint('⛔ Bildirim izni KALICI REDDEDİLDİ - Ayarlardan açılmalı!');
      return false;
    }
    return false;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint('📢 showNotification çağrıldı: $title');

    if (!_isInitialized) {
      debugPrint('⚠️ NotificationService henüz başlatılmamış, başlatılıyor...');
      await initialize();
    }

    // ✅ Önce izni kontrol et
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      debugPrint('❌ Bildirim İZİN YOK! Bildirim gönderilemiyor.');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'vehicle_tracking_channel',
      'Araç Takibi',
      channelDescription: 'Araç durağa yaklaştığında bildirim gönderir',
      importance: Importance.max, // ✅ MAX
      priority: Priority.max, // ✅ MAX
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      ticker: title,
      // ✅ Uygulama önplanda bile göster
      visibility: NotificationVisibility.public,
      fullScreenIntent: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000;
      debugPrint('📢 Bildirim ID: $id gönderiliyor...');

      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      debugPrint('✅ Bildirim BAŞARIYLA gönderildi! ID: $id');
      debugPrint('   Başlık: $title');
      debugPrint('   İçerik: $body');
    } catch (e) {
      debugPrint('❌ Bildirim gönderme HATASI: $e');
    }
  }

  // ✅ TEST bildirimi - Çalışıp çalışmadığını anında test et
  Future<void> sendTestNotification() async {
    debugPrint('🧪 TEST BİLDİRİMİ GÖNDERİLİYOR...');
    await showNotification(
      title: '🚌 Test Bildirimi',
      body: 'Bildirim sistemi çalışıyor! Araç takibi aktif.',
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    debugPrint('🗑️ Tüm bildirimler iptal edildi');
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
