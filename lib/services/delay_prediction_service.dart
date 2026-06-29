import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/vehicle_location_model.dart';
import '../services/vehicle_service.dart';

/// Otobüs gecikme tahmini servisi
/// TensorFlow Lite kullanarak on-device ML
///
/// Girdiler:
/// - Saat (0-23)
/// - Gün (0-6, Pazartesi=0)
/// - Hava durumu (simülasyon)
/// - Trafik yoğunluğu (GPS verisi)
/// - Hat numarası
///
/// Çıktı:
/// - Gecikme (dakika): -5 ile +30 arası
class DelayPredictionService {
  static final DelayPredictionService _instance =
      DelayPredictionService._internal();
  factory DelayPredictionService() => _instance;
  DelayPredictionService._internal();

  Interpreter? _interpreter;
  bool _isInitialized = false;

  final VehicleService _vehicleService = VehicleService();

  // Model input/output shape
  static const int _inputSize = 5; // [hour, day, weather, traffic, route]
  static const int _outputSize = 1; // [delay_minutes]

  /// Modeli yükle
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🤖 TensorFlow Lite model yükleniyor...');

      // Model dosyasını yükle
      _interpreter = await Interpreter.fromAsset('models/delay_model.tflite');

      _isInitialized = true;
      debugPrint('✅ Gecikme tahmin modeli yüklendi');

      // Model bilgilerini logla
      debugPrint('   Input shape: ${_interpreter!.getInputTensor(0).shape}');
      debugPrint('   Output shape: ${_interpreter!.getOutputTensor(0).shape}');
    } catch (e) {
      debugPrint('⚠️ Model yüklenemedi, fallback algoritma kullanılacak: $e');
      // Model yoksa fallback algoritma kullanılacak
      _isInitialized = false;
    }
  }

  /// Gecikme tahmini yap
  ///
  /// Returns: Tahmin edilen gecikme (dakika)
  /// - Negatif değer = Erken
  /// - Pozitif değer = Geç
  /// - 0 = Zamanında
  Future<DelayPrediction> predictDelay({
    required String routeId,
    required String stopId,
    DateTime? time,
  }) async {
    time ??= DateTime.now();

    try {
      if (_isInitialized && _interpreter != null) {
        // ML Model ile tahmin
        return await _predictWithModel(routeId, stopId, time);
      } else {
        // Fallback algoritma
        return await _predictWithAlgorithm(routeId, stopId, time);
      }
    } catch (e) {
      debugPrint('❌ Tahmin hatası: $e');
      // Hata durumunda güvenli fallback
      return DelayPrediction(
        routeId: routeId,
        stopId: stopId,
        delayMinutes: 0,
        confidence: 0.0,
        reason: 'Tahmin yapılamadı',
        timestamp: time,
      );
    }
  }

  /// Model ile tahmin
  Future<DelayPrediction> _predictWithModel(
    String routeId,
    String stopId,
    DateTime time,
  ) async {
    try {
      // GPS verilerini al (trafik yoğunluğu için)
      final vehicles = await _vehicleService.getVehiclesForRoute(routeId);
      final trafficDensity = _calculateTrafficDensity(vehicles);

      // Input verisini hazırla
      final input = _prepareInput(
        hour: time.hour,
        dayOfWeek: time.weekday - 1, // 0-6
        weather: 0, // TODO: Gerçek hava durumu API'si
        traffic: trafficDensity,
        routeNumber: int.tryParse(routeId) ?? 0,
      );

      // Model inference
      final output = List.filled(_outputSize, 0.0).reshape([1, _outputSize]);
      _interpreter!.run(input, output);

      final delayMinutes = output[0][0].round();

      debugPrint('🔮 ML Tahmin: $delayMinutes dk gecikme (${routeId})');

      return DelayPrediction(
        routeId: routeId,
        stopId: stopId,
        delayMinutes: delayMinutes,
        confidence: 0.85,
        reason: _getDelayReason(delayMinutes, time.hour, trafficDensity),
        timestamp: time,
      );
    } catch (e) {
      debugPrint('❌ Model inference hatası: $e');
      return await _predictWithAlgorithm(routeId, stopId, time);
    }
  }

  /// Fallback algoritma (model yoksa)
  Future<DelayPrediction> _predictWithAlgorithm(
    String routeId,
    String stopId,
    DateTime time,
  ) async {
    // GPS verilerini al
    final vehicles = await _vehicleService.getVehiclesForRoute(routeId);
    final trafficDensity = _calculateTrafficDensity(vehicles);

    int delay = 0;
    String reason = 'Zamanında';
    double confidence = 0.7;

    // Saat bazlı tahmin
    if (time.hour >= 7 && time.hour <= 9) {
      // Sabah yoğunluğu
      delay = 5 + (trafficDensity * 10).round();
      reason = 'Sabah yoğunluğu';
      confidence = 0.75;
    } else if (time.hour >= 17 && time.hour <= 19) {
      // Akşam yoğunluğu
      delay = 7 + (trafficDensity * 12).round();
      reason = 'Akşam yoğunluğu';
      confidence = 0.8;
    } else if (time.hour >= 12 && time.hour <= 14) {
      // Öğle saatleri
      delay = 2 + (trafficDensity * 5).round();
      reason = 'Öğle trafiği';
      confidence = 0.6;
    } else if (time.hour >= 22 || time.hour <= 6) {
      // Gece saatleri
      delay = -(2 + (trafficDensity * 3).round()); // Genelde erken
      reason = 'Gece saatleri - az trafik';
      confidence = 0.65;
    } else {
      // Normal saatler
      delay = (trafficDensity * 3).round();
      reason = trafficDensity > 0.5 ? 'Orta yoğunluk' : 'Normal trafik';
      confidence = 0.6;
    }

    // Hafta sonu düzeltmesi
    if (time.weekday == DateTime.saturday || time.weekday == DateTime.sunday) {
      delay = (delay * 0.7).round(); // %30 daha az gecikme
      reason += ' (Hafta sonu)';
    }

    debugPrint('📊 Algoritma Tahmini: $delay dk gecikme (${routeId})');

    return DelayPrediction(
      routeId: routeId,
      stopId: stopId,
      delayMinutes: delay,
      confidence: confidence,
      reason: reason,
      timestamp: time,
    );
  }

  /// Trafik yoğunluğu hesapla (0.0 - 1.0)
  double _calculateTrafficDensity(List<VehicleLocation> vehicles) {
    if (vehicles.isEmpty) return 0.5; // Veri yoksa orta yoğunluk varsay

    // Araç hızlarından yoğunluk çıkar
    final speeds =
        vehicles.map((v) => v.gps.speed ?? 0.0).where((s) => s > 0).toList();

    if (speeds.isEmpty) return 0.5;

    final avgSpeed = speeds.reduce((a, b) => a + b) / speeds.length;

    // Hız yavaşsa trafik yoğun
    // 50 km/s üstü = az yoğun (0.0)
    // 10 km/s altı = çok yoğun (1.0)
    if (avgSpeed >= 50) return 0.0;
    if (avgSpeed <= 10) return 1.0;

    return 1.0 - ((avgSpeed - 10) / 40); // Linear interpolation
  }

  /// Model input'u hazırla
  List<List<double>> _prepareInput({
    required int hour,
    required int dayOfWeek,
    required int weather,
    required double traffic,
    required int routeNumber,
  }) {
    return [
      [
        hour.toDouble() / 23.0, // Normalize (0-1)
        dayOfWeek.toDouble() / 6.0,
        weather.toDouble() / 2.0, // 0=güneşli, 1=yağmurlu, 2=karlı
        traffic, // Zaten 0-1 arası
        routeNumber.toDouble() / 100.0, // Hat numarası normalize
      ]
    ];
  }

  /// Gecikme sebebini açıkla
  String _getDelayReason(int delay, int hour, double traffic) {
    if (delay <= -2) return 'Az trafik - erken varış bekleniyor';
    if (delay <= 2) return 'Zamanında varış bekleniyor';
    if (delay <= 5) return 'Hafif gecikme olabilir';
    if (delay <= 10) {
      if (hour >= 7 && hour <= 9) return 'Sabah yoğunluğu nedeniyle gecikme';
      if (hour >= 17 && hour <= 19) return 'Akşam yoğunluğu nedeniyle gecikme';
      return 'Orta düzeyde gecikme bekleniyor';
    }
    return 'Yoğun trafik - ciddi gecikme bekleniyor';
  }

  /// Modeli kapat
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

/// Gecikme tahmini sonucu
class DelayPrediction {
  final String routeId;
  final String stopId;
  final int delayMinutes; // Negatif = erken, Pozitif = geç
  final double confidence; // 0.0-1.0
  final String reason;
  final DateTime timestamp;

  DelayPrediction({
    required this.routeId,
    required this.stopId,
    required this.delayMinutes,
    required this.confidence,
    required this.reason,
    required this.timestamp,
  });

  /// Kullanıcı dostu mesaj
  String get userMessage {
    if (delayMinutes <= -2) {
      return '${delayMinutes.abs()} dakika erken gelebilir';
    } else if (delayMinutes <= 2) {
      return 'Zamanında gelecek';
    } else {
      return '$delayMinutes dakika gecikebilir';
    }
  }

  /// Renk kodu (UI için)
  String get statusColor {
    if (delayMinutes <= 2) return 'green';
    if (delayMinutes <= 5) return 'yellow';
    if (delayMinutes <= 10) return 'orange';
    return 'red';
  }

  /// İkon (UI için)
  String get statusIcon {
    if (delayMinutes <= 2) return 'check_circle';
    if (delayMinutes <= 5) return 'warning';
    if (delayMinutes <= 10) return 'error';
    return 'cancel';
  }

  bool get isOnTime => delayMinutes.abs() <= 2;
  bool get isEarly => delayMinutes < -2;
  bool get isLate => delayMinutes > 2;
  bool get isHighConfidence => confidence >= 0.7;

  @override
  String toString() => 'DelayPrediction($delayMinutes min, $confidence conf)';
}
