import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/trip_record_model.dart';
import '../models/route_model.dart';
import '../models/stop_model.dart';

/// Kullanıcı yolculuk geçmişi servisi
///
/// Özellikler:
/// - Yolculukları kaydet
/// - Geçmiş analiz et
/// - Akıllı öneriler üret
class TripHistoryService {
  static final TripHistoryService _instance = TripHistoryService._internal();
  factory TripHistoryService() => _instance;
  TripHistoryService._internal();

  Database? _database;

  /// Veritabanını başlat
  Future<void> initialize() async {
    if (_database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'trip_history.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
      );

      debugPrint('✅ Trip history veritabanı başlatıldı');
    } catch (e) {
      debugPrint('❌ Trip history DB hatası: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Yolculuk geçmişi tablosu
    await db.execute('''
      CREATE TABLE trip_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        route_id TEXT NOT NULL,
        route_short_name TEXT NOT NULL,
        boarding_stop_id TEXT NOT NULL,
        boarding_stop_name TEXT NOT NULL,
        alighting_stop_id TEXT NOT NULL,
        alighting_stop_name TEXT NOT NULL,
        trip_date TEXT NOT NULL,
        trip_time TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        duration_minutes INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    // AI sorgu cache tablosu
    await db.execute('''
      CREATE TABLE ai_query_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        intent TEXT NOT NULL,
        response TEXT NOT NULL,
        confidence REAL NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // İndeksler
    await db.execute('CREATE INDEX idx_trip_date ON trip_history(trip_date)');
    await db.execute('CREATE INDEX idx_trip_route ON trip_history(route_id)');
    await db.execute(
        'CREATE INDEX idx_trip_stops ON trip_history(boarding_stop_id, alighting_stop_id)');

    debugPrint('✅ Trip history tabloları oluşturuldu');
  }

  // ==================== YOLCULUK KAYDETME ====================

  /// Yolculuğu kaydet
  Future<void> recordTrip({
    required TransitRoute route,
    required Stop boardingStop,
    required Stop alightingStop,
    int? durationMinutes,
  }) async {
    if (_database == null) await initialize();

    final now = DateTime.now();

    try {
      await _database!.insert('trip_history', {
        'route_id': route.routeId,
        'route_short_name': route.routeShortName,
        'boarding_stop_id': boardingStop.stopId,
        'boarding_stop_name': boardingStop.stopName,
        'alighting_stop_id': alightingStop.stopId,
        'alighting_stop_name': alightingStop.stopName,
        'trip_date': _formatDate(now),
        'trip_time': _formatTime(now),
        'day_of_week': now.weekday,
        'duration_minutes': durationMinutes,
        'created_at': now.millisecondsSinceEpoch,
      });

      debugPrint(
          '✅ Yolculuk kaydedildi: ${route.routeShortName} - ${boardingStop.stopName} → ${alightingStop.stopName}');
    } catch (e) {
      debugPrint('❌ Yolculuk kaydetme hatası: $e');
    }
  }

  // ==================== GEÇMİŞ SORGULAMA ====================

  /// Tüm yolculukları getir
  Future<List<TripRecord>> getAllTrips({int? limit}) async {
    if (_database == null) await initialize();

    final maps = await _database!.query(
      'trip_history',
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return maps.map((map) => TripRecord.fromMap(map)).toList();
  }

  /// Belirli bir tarih aralığındaki yolculukları getir
  Future<List<TripRecord>> getTripsByDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    if (_database == null) await initialize();

    final maps = await _database!.query(
      'trip_history',
      where: 'trip_date BETWEEN ? AND ?',
      whereArgs: [_formatDate(start), _formatDate(end)],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => TripRecord.fromMap(map)).toList();
  }

  /// Belirli bir hat için yolculukları getir
  Future<List<TripRecord>> getTripsByRoute(String routeId) async {
    if (_database == null) await initialize();

    final maps = await _database!.query(
      'trip_history',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => TripRecord.fromMap(map)).toList();
  }

  // ==================== İSTATİSTİKLER ====================

  /// En çok kullanılan hatlar
  Future<List<RouteUsageStats>> getMostUsedRoutes({int limit = 5}) async {
    if (_database == null) await initialize();

    final maps = await _database!.rawQuery('''
      SELECT 
        route_id,
        route_short_name,
        COUNT(*) as trip_count,
        AVG(duration_minutes) as avg_duration
      FROM trip_history
      WHERE trip_date >= date('now', '-30 days')
      GROUP BY route_id
      ORDER BY trip_count DESC
      LIMIT ?
    ''', [limit]);

    return maps
        .map((map) => RouteUsageStats(
              routeId: map['route_id'] as String,
              routeShortName: map['route_short_name'] as String,
              tripCount: map['trip_count'] as int,
              avgDuration: (map['avg_duration'] as num?)?.toDouble(),
            ))
        .toList();
  }

  /// En çok kullanılan güzergahlar
  Future<List<RoutePatternStats>> getMostUsedPatterns({int limit = 5}) async {
    if (_database == null) await initialize();

    final maps = await _database!.rawQuery('''
      SELECT 
        route_short_name,
        boarding_stop_name,
        alighting_stop_name,
        COUNT(*) as trip_count
      FROM trip_history
      WHERE trip_date >= date('now', '-30 days')
      GROUP BY boarding_stop_id, alighting_stop_id
      ORDER BY trip_count DESC
      LIMIT ?
    ''', [limit]);

    return maps
        .map((map) => RoutePatternStats(
              routeShortName: map['route_short_name'] as String,
              boardingStopName: map['boarding_stop_name'] as String,
              alightingStopName: map['alighting_stop_name'] as String,
              tripCount: map['trip_count'] as int,
            ))
        .toList();
  }

  /// Toplam yolculuk sayısı
  Future<int> getTotalTripCount() async {
    if (_database == null) await initialize();

    final result =
        await _database!.rawQuery('SELECT COUNT(*) as count FROM trip_history');

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== AKILLI ÖNERİLER ====================

  /// Belirli bir saat dilimi için önerileri getir
  Future<List<SmartRecommendation>> getRecommendationsForTime({
    required int hour, // 0-23
    int? dayOfWeek, // 1-7 (Monday-Sunday)
  }) async {
    if (_database == null) await initialize();

    // Belirli saat dilimine yakın yolculukları bul
    final timeStart = '$hour:00';
    final timeEnd = '${hour + 1}:00';

    String whereClause = 'trip_time >= ? AND trip_time < ?';
    List<dynamic> whereArgs = [timeStart, timeEnd];

    if (dayOfWeek != null) {
      whereClause += ' AND day_of_week = ?';
      whereArgs.add(dayOfWeek);
    }

    final maps = await _database!.rawQuery('''
      SELECT 
        route_short_name,
        boarding_stop_name,
        alighting_stop_name,
        COUNT(*) as usage_count,
        AVG(duration_minutes) as avg_duration
      FROM trip_history
      WHERE $whereClause
        AND trip_date >= date('now', '-60 days')
      GROUP BY boarding_stop_id, alighting_stop_id
      HAVING usage_count >= 2
      ORDER BY usage_count DESC
      LIMIT 5
    ''', whereArgs);

    return maps
        .map((map) => SmartRecommendation(
              routeShortName: map['route_short_name'] as String,
              boardingStopName: map['boarding_stop_name'] as String,
              alightingStopName: map['alighting_stop_name'] as String,
              usageCount: map['usage_count'] as int,
              avgDuration: (map['avg_duration'] as num?)?.toDouble(),
              confidence: _calculateConfidence(map['usage_count'] as int),
            ))
        .toList();
  }

  /// Güven skoru hesapla (0.0 - 1.0)
  double _calculateConfidence(int usageCount) {
    if (usageCount >= 10) return 1.0;
    if (usageCount >= 5) return 0.8;
    if (usageCount >= 3) return 0.6;
    return 0.4;
  }

  // ==================== TEMİZLİK ====================

  /// Eski kayıtları temizle (90 günden eski)
  Future<void> cleanOldRecords() async {
    if (_database == null) await initialize();

    try {
      final deletedCount = await _database!.delete(
        'trip_history',
        where: 'trip_date < date(\'now\', \'-90 days\')',
      );

      debugPrint('🗑️ $deletedCount eski yolculuk kaydı temizlendi');
    } catch (e) {
      debugPrint('❌ Temizlık hatası: $e');
    }
  }

  /// Tüm geçmişi sil
  Future<void> clearAllHistory() async {
    if (_database == null) await initialize();

    await _database!.delete('trip_history');
    debugPrint('🗑️ Tüm yolculuk geçmişi silindi');
  }

  // ==================== YARDIMCI METODLAR ====================

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

// ==================== İSTATİSTİK MODELLERİ ====================

class RouteUsageStats {
  final String routeId;
  final String routeShortName;
  final int tripCount;
  final double? avgDuration;

  RouteUsageStats({
    required this.routeId,
    required this.routeShortName,
    required this.tripCount,
    this.avgDuration,
  });
}

class RoutePatternStats {
  final String routeShortName;
  final String boardingStopName;
  final String alightingStopName;
  final int tripCount;

  RoutePatternStats({
    required this.routeShortName,
    required this.boardingStopName,
    required this.alightingStopName,
    required this.tripCount,
  });
}

class SmartRecommendation {
  final String routeShortName;
  final String boardingStopName;
  final String alightingStopName;
  final int usageCount;
  final double? avgDuration;
  final double confidence;

  SmartRecommendation({
    required this.routeShortName,
    required this.boardingStopName,
    required this.alightingStopName,
    required this.usageCount,
    this.avgDuration,
    required this.confidence,
  });

  String get description {
    final duration =
        avgDuration != null ? ' (~${avgDuration!.toInt()} dk)' : '';
    return '$boardingStopName → $alightingStopName$duration';
  }
}
