import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../models/stop_model.dart';
import '../models/route_model.dart';
import '../services/tts_service.dart';

/// Navigasyon aşamaları
enum NavigationPhase {
  walkingToStop, // Durağa yürüme
  waitingAtStop, // Durakta bekleme
  onBus, // Otobüste
  arrived, // Hedefe ulaşıldı
}

/// Navigasyon durumu
class NavigationState {
  final NavigationPhase phase;
  final double distanceToNextPoint;
  final String instruction;
  final String subInstruction;
  final int? minutesUntilBus;
  final int? stopsRemaining;
  final Stop? currentNearestStop;
  final bool busDetectedAutomatically;

  const NavigationState({
    required this.phase,
    required this.distanceToNextPoint,
    required this.instruction,
    this.subInstruction = '',
    this.minutesUntilBus,
    this.stopsRemaining,
    this.currentNearestStop,
    this.busDetectedAutomatically = false,
  });
}

/// Aktif navigasyon verisi
class ActiveTrip {
  final TransitRoute route;
  final Stop boardingStop;
  final Stop alightingStop;
  final String? nextDeparture;
  final List<Stop> routeStops;
  final String destinationName;

  const ActiveTrip({
    required this.route,
    required this.boardingStop,
    required this.alightingStop,
    required this.destinationName,
    this.nextDeparture,
    this.routeStops = const [],
  });
}

class NavigationService extends ChangeNotifier {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final TtsService _tts = TtsService();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<Position>? _positionStream;
  ActiveTrip? _activeTrip;
  NavigationState? _state;
  bool _isActive = false;
  bool _notificationsInitialized = false;

  // Otomatik biniş tespiti
  final List<double> _recentSpeeds = [];
  static const double _busSpeedThreshold = 1.4; // m/s (~5 km/h)
  // FIX: _walkSpeedThreshold kullanılmıyordu → kaldırıldı

  // Bildirim / anons takibi
  bool _sentApproachingNotification = false;
  bool _sentAlightingNotification = false;
  int _lastAnnouncedStopsRemaining = -1;
  int _lastAnnouncedDistBucket = -1;

  // Getters
  bool get isActive => _isActive;
  ActiveTrip? get activeTrip => _activeTrip;
  NavigationState? get state => _state;

  // ─────────────────────────────────────────────────────────
  // Bildirimleri başlat
  // ─────────────────────────────────────────────────────────

  Future<void> initNotifications() async {
    if (_notificationsInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    const androidChannel = AndroidNotificationChannel(
      'navigation_channel',
      'Navigasyon Bildirimleri',
      description: 'Otobüs yolculuğu sırasında iniş bildirimleri',
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    _notificationsInitialized = true;
    debugPrint('✅ Bildirimler başlatıldı');
  }

  // ─────────────────────────────────────────────────────────
  // Navigasyonu başlat
  // ─────────────────────────────────────────────────────────

  Future<void> startNavigation(ActiveTrip trip) async {
    await initNotifications();

    _activeTrip = trip;
    _isActive = true;
    _sentApproachingNotification = false;
    _sentAlightingNotification = false;
    _lastAnnouncedStopsRemaining = -1;
    _lastAnnouncedDistBucket = -1;
    _recentSpeeds.clear();

    _state = NavigationState(
      phase: NavigationPhase.walkingToStop,
      distanceToNextPoint: 0,
      instruction: '${trip.boardingStop.stopName} durağına gidin',
      subInstruction: 'Navigasyon başlatıldı',
    );

    notifyListeners();

    await _tts
        .speak('${trip.route.routeShortName} hattı için navigasyon başlatıldı. '
            '${trip.boardingStop.stopName} durağına yürüyün.');

    _startLocationTracking();
  }

  // ─────────────────────────────────────────────────────────
  // Navigasyonu durdur
  // ─────────────────────────────────────────────────────────

  Future<void> stopNavigation() async {
    _positionStream?.cancel();
    _positionStream = null;
    _isActive = false;
    _activeTrip = null;
    _state = null;
    notifyListeners();
    await _cancelAllNotifications();
    debugPrint('🛑 Navigasyon durduruldu');
  }

  // ─────────────────────────────────────────────────────────
  // Manuel "Otobüse Bindim"
  // ─────────────────────────────────────────────────────────

  Future<void> confirmBoarding() async {
    if (_activeTrip == null) return;
    await _onBoardingDetected(manual: true);
  }

  // ─────────────────────────────────────────────────────────
  // "Durağa Kendim Gidebilirim" → direkt bekleme adımına geç
  // ─────────────────────────────────────────────────────────

  Future<void> skipToWaitingAtStop() async {
    if (_activeTrip == null) return;
    final trip = _activeTrip!;

    _lastAnnouncedDistBucket = -1;

    // FIX: skip sonrası false alarm riskini önlemek için hız geçmişini temizle
    _recentSpeeds.clear();

    _state = NavigationState(
      phase: NavigationPhase.waitingAtStop,
      distanceToNextPoint: 0,
      instruction: 'Otobüsü Bekleyin',
      subInstruction:
          'Hat ${trip.route.routeShortName} — ${trip.boardingStop.stopName}',
      minutesUntilBus: _minutesUntilDeparture(trip.nextDeparture),
    );
    notifyListeners();

    await _tts
        .speak('${trip.boardingStop.stopName} durağında otobüsü bekleyin. '
            'Hat ${trip.route.routeShortName} bekleniyor.');
  }

  // ─────────────────────────────────────────────────────────
  // Konum takibi
  // ─────────────────────────────────────────────────────────

  void _startLocationTracking() {
    _positionStream?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _onLocationUpdate,
      onError: (e) => debugPrint('❌ Konum hatası: $e'),
    );
  }

  Future<void> _onLocationUpdate(Position position) async {
    if (!_isActive || _activeTrip == null) return;

    final trip = _activeTrip!;
    final phase = _state?.phase ?? NavigationPhase.walkingToStop;

    _recentSpeeds.add(position.speed);
    if (_recentSpeeds.length > 5) _recentSpeeds.removeAt(0);

    switch (phase) {
      case NavigationPhase.walkingToStop:
        await _updateWalkingPhase(position, trip);
      case NavigationPhase.waitingAtStop:
        await _updateWaitingPhase(position, trip);
      case NavigationPhase.onBus:
        await _updateOnBusPhase(position, trip);
      case NavigationPhase.arrived:
        break;
    }
  }

  // ─────────────────────────────────────────────────────────
  // Durağa yürüme aşaması
  // ─────────────────────────────────────────────────────────

  Future<void> _updateWalkingPhase(Position position, ActiveTrip trip) async {
    final distToStop = _distance(
      position.latitude,
      position.longitude,
      trip.boardingStop.latitude,
      trip.boardingStop.longitude,
    );

    // Durağa varıldı (20m eşiği)
    if (distToStop < 20) {
      _state = NavigationState(
        phase: NavigationPhase.waitingAtStop,
        distanceToNextPoint: distToStop,
        instruction: 'Durağa Ulaştınız!',
        subInstruction: '${trip.boardingStop.stopName} — Otobüsü bekleyin',
        minutesUntilBus: _minutesUntilDeparture(trip.nextDeparture),
      );
      notifyListeners();
      await _tts.speak(
          '${trip.boardingStop.stopName} durağındasınız. Otobüsü bekleyin.');
      return;
    }

    final bearingToStop = _bearing(
      position.latitude,
      position.longitude,
      trip.boardingStop.latitude,
      trip.boardingStop.longitude,
    );

    final String turnInstruction;
    if (position.heading >= 0) {
      turnInstruction =
          _relativeTurnInstruction(position.heading, bearingToStop);
    } else {
      turnInstruction = '${_bearingToDirection(bearingToStop)} git';
    }

    String instruction;
    String subInstruction;

    if (distToStop < 30) {
      instruction = 'Durak çok yakında';
      subInstruction =
          '${distToStop.toInt()} m — ${trip.boardingStop.stopName}';
    } else if (distToStop < 80) {
      instruction = turnInstruction;
      subInstruction = '${distToStop.toInt()} m ileride durak sizi bekliyor';
    } else {
      instruction = turnInstruction;
      subInstruction =
          '${distToStop.toInt()} m — ${trip.boardingStop.stopName}';
    }

    // Her 50m'de bir sesli talimat
    final roundedDist = (distToStop / 50).round() * 50;
    if (_lastAnnouncedDistBucket != roundedDist && distToStop > 20) {
      _lastAnnouncedDistBucket = roundedDist;
      await _tts.speak('$turnInstruction, ${distToStop.toInt()} metre.');
    }

    _state = NavigationState(
      phase: NavigationPhase.walkingToStop,
      distanceToNextPoint: distToStop,
      instruction: instruction,
      subInstruction: subInstruction,
    );
    notifyListeners();
  }

  String _relativeTurnInstruction(double userHeading, double targetBearing) {
    double diff = targetBearing - userHeading;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;

    if (diff.abs() <= 20) return 'Düz devam edin';
    if (diff > 20 && diff <= 60) return 'Hafif sağa dönün';
    if (diff > 60 && diff <= 120) return 'Sağa dönün';
    if (diff > 120) return 'Geri dönün (sağ)';
    if (diff < -20 && diff >= -60) return 'Hafif sola dönün';
    if (diff < -60 && diff >= -120) return 'Sola dönün';
    return 'Geri dönün (sol)';
  }

  // ─────────────────────────────────────────────────────────
  // Durakta bekleme aşaması
  // ─────────────────────────────────────────────────────────

  Future<void> _updateWaitingPhase(Position position, ActiveTrip trip) async {
    final minutesLeft = _minutesUntilDeparture(trip.nextDeparture);

    // Otomatik biniş tespiti
    final avgSpeed = _recentSpeeds.isNotEmpty
        ? _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length
        : 0.0;

    if (avgSpeed > _busSpeedThreshold && _recentSpeeds.length >= 3) {
      final distToStop = _distance(
        position.latitude,
        position.longitude,
        trip.boardingStop.latitude,
        trip.boardingStop.longitude,
      );
      if (distToStop > 30) {
        await _onBoardingDetected(manual: false);
        return;
      }
    }

    _state = NavigationState(
      phase: NavigationPhase.waitingAtStop,
      distanceToNextPoint: 0,
      instruction: 'Otobüsü Bekleyin',
      subInstruction: minutesLeft != null
          ? 'Hat ${trip.route.routeShortName} — $minutesLeft dk sonra'
          : 'Hat ${trip.route.routeShortName} bekleniyor',
      minutesUntilBus: minutesLeft,
    );
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────
  // Otobüste aşaması
  // ─────────────────────────────────────────────────────────

  Future<void> _updateOnBusPhase(Position position, ActiveTrip trip) async {
    if (trip.routeStops.isEmpty) {
      await _updateOnBusPhaseSimple(position, trip);
      return;
    }

    final alightingIdx = trip.routeStops
        .indexWhere((s) => s.stopId == trip.alightingStop.stopId);

    if (alightingIdx == -1) {
      await _updateOnBusPhaseSimple(position, trip);
      return;
    }

    int nearestIdx = 0;
    double nearestDist = double.infinity;
    for (var i = 0; i < trip.routeStops.length; i++) {
      final d = _distance(position.latitude, position.longitude,
          trip.routeStops[i].latitude, trip.routeStops[i].longitude);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }

    final stopsRemaining = alightingIdx - nearestIdx;
    final distToAlighting = _distance(
      position.latitude,
      position.longitude,
      trip.alightingStop.latitude,
      trip.alightingStop.longitude,
    );

    // 1 durak kaldı bildirimi
    if (stopsRemaining == 1 && !_sentApproachingNotification) {
      _sentApproachingNotification = true;
      await _sendNotification(
        title: '⚠️ Bir Sonraki Durak İniş Durağınız!',
        body: '${trip.alightingStop.stopName} durağında inin.',
        id: 1,
      );
      await _tts.speak('Dikkat! Bir sonraki durak iniş durağınız: '
          '${trip.alightingStop.stopName}. Hazırlanın.');
    }

    // 50m kaldı → inme zamanı
    if (distToAlighting < 50 && !_sentAlightingNotification) {
      _sentAlightingNotification = true;
      await _sendNotification(
        title: '🚨 İnin! Durağınız Geldi!',
        body: '${trip.alightingStop.stopName} — Şimdi inin!',
        id: 2,
      );
      await _tts.speak(
          'İnin! ${trip.alightingStop.stopName} durağındasınız. Şimdi inin!');
      _state = NavigationState(
        phase: NavigationPhase.arrived,
        distanceToNextPoint: 0,
        instruction: 'İnin! Durağınız Geldi!',
        subInstruction: trip.alightingStop.stopName,
        stopsRemaining: 0,
      );
      notifyListeners();
      return;
    }

    // Sesli uyarı — her durak değişiminde bir kez
    if (stopsRemaining != _lastAnnouncedStopsRemaining &&
        stopsRemaining > 0 &&
        stopsRemaining <= 3) {
      _lastAnnouncedStopsRemaining = stopsRemaining;
      await _tts.speak('$stopsRemaining durak kaldı.');
    }

    final String instruction;
    if (stopsRemaining <= 0) {
      instruction = 'İniş durağınıza yaklaşıyorsunuz';
    } else if (stopsRemaining == 1) {
      instruction = 'Sonraki durak iniş durağınız!';
    } else {
      instruction = '$stopsRemaining durak kaldı';
    }

    _state = NavigationState(
      phase: NavigationPhase.onBus,
      distanceToNextPoint: distToAlighting,
      instruction: instruction,
      subInstruction:
          'İniş: ${trip.alightingStop.stopName} (${distToAlighting.toInt()} m)',
      stopsRemaining: stopsRemaining > 0 ? stopsRemaining : 0,
    );
    notifyListeners();
  }

  Future<void> _updateOnBusPhaseSimple(
      Position position, ActiveTrip trip) async {
    final distToAlighting = _distance(
      position.latitude,
      position.longitude,
      trip.alightingStop.latitude,
      trip.alightingStop.longitude,
    );

    if (distToAlighting < 150 && !_sentApproachingNotification) {
      _sentApproachingNotification = true;
      await _sendNotification(
        title: '⚠️ İniş Durağına Yaklaşıyorsunuz!',
        body: '${trip.alightingStop.stopName} — 150m kaldı.',
        id: 1,
      );
      await _tts.speak(
          'Dikkat! ${trip.alightingStop.stopName} durağına yaklaşıyorsunuz. Hazırlanın.');
    }

    if (distToAlighting < 50 && !_sentAlightingNotification) {
      _sentAlightingNotification = true;
      await _sendNotification(
        title: '🚨 İnin! Durağınız Geldi!',
        body: '${trip.alightingStop.stopName}',
        id: 2,
      );
      await _tts.speak('İnin! ${trip.alightingStop.stopName} durağındasınız!');
      _state = NavigationState(
        phase: NavigationPhase.arrived,
        distanceToNextPoint: 0,
        instruction: 'İnin! Durağınız Geldi!',
        subInstruction: trip.alightingStop.stopName,
      );
      notifyListeners();
      return;
    }

    final distText = distToAlighting < 1000
        ? '${distToAlighting.toInt()} m'
        : '${(distToAlighting / 1000).toStringAsFixed(1)} km';

    _state = NavigationState(
      phase: NavigationPhase.onBus,
      distanceToNextPoint: distToAlighting,
      instruction: 'Yolculuğunuz devam ediyor',
      subInstruction: 'İniş: ${trip.alightingStop.stopName} — $distText',
    );
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────
  // Biniş tespit edildi
  // ─────────────────────────────────────────────────────────

  Future<void> _onBoardingDetected({required bool manual}) async {
    if (_activeTrip == null) return;
    final trip = _activeTrip!;

    _sentApproachingNotification = false;
    _sentAlightingNotification = false;
    _lastAnnouncedStopsRemaining = -1;

    _state = NavigationState(
      phase: NavigationPhase.onBus,
      distanceToNextPoint: 0,
      instruction: 'İyi Yolculuklar!',
      subInstruction: '${trip.alightingStop.stopName} durağında ineceksiniz',
      busDetectedAutomatically: !manual,
    );
    notifyListeners();

    final msg = manual
        ? '${trip.route.routeShortName} hattına bindiniz. '
            '${trip.alightingStop.stopName} durağında inmeniz gerekiyor. '
            'Durağınıza yaklaştığınızda sizi uyaracağım.'
        : 'Otobüse bindiğiniz tespit edildi. '
            '${trip.alightingStop.stopName} durağında inmeniz gerekiyor.';

    await _tts.speak(msg);

    await _sendNotification(
      title: 'Hat ${trip.route.routeShortName} — Yolculuk Başladı',
      body: '${trip.alightingStop.stopName} durağında ineceksiniz.',
      id: 0,
      ongoing: true,
    );
  }

  // ─────────────────────────────────────────────────────────
  // Yardımcı metodlar
  // ─────────────────────────────────────────────────────────

  Future<void> _sendNotification({
    required String title,
    required String body,
    required int id,
    bool ongoing = false,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'navigation_channel',
        'Navigasyon Bildirimleri',
        channelDescription: 'Otobüs yolculuğu bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: ongoing,
        autoCancel: !ongoing,
        icon: '@mipmap/ic_launcher',
      );

      await _notifications.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('⚠️ Bildirim gönderilemedi: $e');
    }
  }

  Future<void> _cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Kalkışa kaç dakika kaldı
  /// FIX: gece yarısı geçişi — negatif diff → null döndür (0 dk gösterilmez)
  int? _minutesUntilDeparture(String? timeStr) {
    if (timeStr == null) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length < 2) return null;
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      final now = DateTime.now();
      var departure = DateTime(now.year, now.month, now.day, hour, minute);
      // Gece yarısı geçişi: sefer geçmişse ertesi güne taşı
      if (departure.isBefore(now)) {
        departure = departure.add(const Duration(days: 1));
      }
      final diff = departure.difference(now);
      // 6 saatten fazla ise muhtemelen yanlış gün hesabı → null
      if (diff.inHours > 6) return null;
      return diff.inMinutes;
    } catch (_) {
      return null;
    }
  }

  double _distance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180;
    final y = sin(dLon) * cos(lat2 * pi / 180);
    final x = cos(lat1 * pi / 180) * sin(lat2 * pi / 180) -
        sin(lat1 * pi / 180) * cos(lat2 * pi / 180) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  String _bearingToDirection(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return 'Kuzeye';
    if (bearing < 67.5) return 'Kuzeydoğuya';
    if (bearing < 112.5) return 'Doğuya';
    if (bearing < 157.5) return 'Güneydoğuya';
    if (bearing < 202.5) return 'Güneye';
    if (bearing < 247.5) return 'Güneybatıya';
    if (bearing < 292.5) return 'Batıya';
    return 'Kuzeybatıya';
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}
