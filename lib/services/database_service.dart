import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';

import '../models/stop_model.dart';
import '../models/route_model.dart';
import 'city_detection_service.dart';
import 'city_database_manager.dart';
import 'gtfs_query_service.dart';
import 'kktc_intercity_service.dart';

/// Veritabanı servisi - Singleton pattern
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // ── Şehir tespiti ──────────────────────────────────────────────────────
  bool get _isManisa =>
      CityDetectionService.instance.currentCity == null ||
      CityDetectionService.instance.currentCity == SupportedCity.manisa;

  Future<void> initialize() async {
    if (_isInitialized && _database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'manisa_ulasim.db');

      debugPrint('📁 Veritabanı yolu: $path');

      _database = await openDatabase(
        path,
        version: 5,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      _isInitialized = true;
      debugPrint('✅ Veritabanı başlatıldı');

      await loadGtfsData();
    } catch (e) {
      debugPrint('❌ Veritabanı hatası: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('📊 Tablolar oluşturuluyor (v$version)...');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stop_id TEXT UNIQUE NOT NULL,
        stop_name TEXT NOT NULL,
        stop_lat REAL NOT NULL,
        stop_lon REAL NOT NULL,
        wheelchair_boarding INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        route_id TEXT UNIQUE NOT NULL,
        route_short_name TEXT NOT NULL,
        route_long_name TEXT,
        route_type INTEGER DEFAULT 3,
        route_color TEXT,
        route_text_color TEXT,
        route_sort_order INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT UNIQUE NOT NULL,
        route_id TEXT NOT NULL,
        service_id TEXT,
        trip_headsign TEXT,
        direction_id INTEGER,
        shape_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stop_times (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        stop_id TEXT NOT NULL,
        arrival_time TEXT,
        departure_time TEXT,
        stop_sequence INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS shapes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shape_id TEXT NOT NULL,
        shape_pt_lat REAL NOT NULL,
        shape_pt_lon REAL NOT NULL,
        shape_pt_sequence INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS calendar (
        service_id TEXT PRIMARY KEY NOT NULL,
        monday    INTEGER NOT NULL DEFAULT 0,
        tuesday   INTEGER NOT NULL DEFAULT 0,
        wednesday INTEGER NOT NULL DEFAULT 0,
        thursday  INTEGER NOT NULL DEFAULT 0,
        friday    INTEGER NOT NULL DEFAULT 0,
        saturday  INTEGER NOT NULL DEFAULT 0,
        sunday    INTEGER NOT NULL DEFAULT 0,
        start_date TEXT NOT NULL,
        end_date   TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS frequencies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        headway_secs INTEGER NOT NULL,
        exact_times INTEGER DEFAULT 0
      )
    ''');

    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_stops_id ON stops(stop_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_routes_id ON routes(route_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_routes_short ON routes(route_short_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trips_route ON trips(route_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trips_service ON trips(service_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stop_times_trip ON stop_times(trip_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stop_times_stop ON stop_times(stop_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stop_times_combined ON stop_times(trip_id, stop_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shapes_id ON shapes(shape_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_calendar_service ON calendar(service_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_frequencies_trip ON frequencies(trip_id)');

    debugPrint('✅ Tablolar ve indeksler oluşturuldu');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Veritabanı güncelleniyor: v$oldVersion -> v$newVersion');

    if (oldVersion < 5) {
      await db.execute('DROP TABLE IF EXISTS stop_times');
      await db.execute('DROP TABLE IF EXISTS trips');
      await db.execute('DROP TABLE IF EXISTS routes');
      await db.execute('DROP TABLE IF EXISTS stops');
      await db.execute('DROP TABLE IF EXISTS shapes');
      await db.execute('DROP TABLE IF EXISTS calendar');
      await db.execute('DROP TABLE IF EXISTS frequencies');
      await _onCreate(db, newVersion);
    }
  }

  Future<void> loadGtfsData() async {
    if (_database == null) return;

    try {
      final stopsCount = Sqflite.firstIntValue(
              await _database!.rawQuery('SELECT COUNT(*) FROM stops')) ??
          0;

      if (stopsCount > 0) {
        debugPrint('✅ Veriler zaten yüklü ($stopsCount durak)');

        final calendarCount = Sqflite.firstIntValue(
                await _database!.rawQuery('SELECT COUNT(*) FROM calendar')) ??
            0;
        final frequenciesCount = Sqflite.firstIntValue(await _database!
                .rawQuery('SELECT COUNT(*) FROM frequencies')) ??
            0;

        if (calendarCount == 0) await _loadCalendar();
        if (frequenciesCount == 0) await _loadFrequencies();
        return;
      }

      debugPrint('📥 GTFS verileri yükleniyor...');
      await _loadStops();
      await _loadRoutes();
      await _loadTrips();
      await _loadStopTimes();
      await _loadShapes();
      await _loadCalendar();
      await _loadFrequencies();

      await _verifyData();

      debugPrint('✅ GTFS yükleme tamamlandı');
    } catch (e) {
      debugPrint('❌ GTFS yükleme hatası: $e');
    }
  }

  Future<void> _verifyData() async {
    final stops = Sqflite.firstIntValue(
            await _database!.rawQuery('SELECT COUNT(*) FROM stops')) ??
        0;
    final routes = Sqflite.firstIntValue(
            await _database!.rawQuery('SELECT COUNT(*) FROM routes')) ??
        0;
    final trips = Sqflite.firstIntValue(
            await _database!.rawQuery('SELECT COUNT(*) FROM trips')) ??
        0;
    final stopTimes = Sqflite.firstIntValue(
            await _database!.rawQuery('SELECT COUNT(*) FROM stop_times')) ??
        0;

    debugPrint('📊 Veri Doğrulama:');
    debugPrint('   Duraklar: $stops');
    debugPrint('   Hatlar: $routes');
    debugPrint('   Seferler: $trips');
    debugPrint('   Durak Zamanları: $stopTimes');
  }

  Future<void> _loadStops() async {
    try {
      final csvString = await rootBundle.loadString('assets/data/stops.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      final batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final stopId = _getValue(row, headers, 'stop_id');
          final stopName = _getValue(row, headers, 'stop_name');
          final latStr = _getValue(row, headers, 'stop_lat');
          final lonStr = _getValue(row, headers, 'stop_lon');

          if (stopId.isEmpty) continue;
          final lat = double.tryParse(latStr);
          final lon = double.tryParse(lonStr);
          if (lat == null || lon == null) continue;

          batch.insert(
              'stops',
              {
                'stop_id': stopId,
                'stop_name': stopName,
                'stop_lat': lat,
                'stop_lon': lon,
                'wheelchair_boarding': int.tryParse(
                        _getValue(row, headers, 'wheelchair_boarding')) ??
                    0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          successCount++;
        } catch (e) {
          continue;
        }
      }

      await batch.commit(noResult: true);
      debugPrint('✅ Duraklar yüklendi: $successCount');
    } catch (e) {
      debugPrint('❌ stops.txt hatası: $e');
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final csvString = await rootBundle.loadString('assets/data/routes.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      final batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final routeId = _getValue(row, headers, 'route_id');
          if (routeId.isEmpty) continue;

          String isActiveStr =
              _getValue(row, headers, 'is_active').toLowerCase();
          bool isActive = isActiveStr.isEmpty ||
              isActiveStr == 'true' ||
              isActiveStr == '1' ||
              isActiveStr.contains('"active":true');

          batch.insert(
              'routes',
              {
                'route_id': routeId,
                'route_short_name': _getValue(row, headers, 'route_short_name'),
                'route_long_name': _getValue(row, headers, 'route_long_name'),
                'route_type':
                    int.tryParse(_getValue(row, headers, 'route_type')) ?? 3,
                'route_color': _getValue(row, headers, 'route_color'),
                'route_text_color': _getValue(row, headers, 'route_text_color'),
                'is_active': isActive ? 1 : 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          successCount++;
        } catch (e) {
          continue;
        }
      }

      await batch.commit(noResult: true);
      debugPrint('✅ Hatlar yüklendi: $successCount');
    } catch (e) {
      debugPrint('❌ routes.txt hatası: $e');
    }
  }

  Future<void> _loadTrips() async {
    try {
      final csvString = await rootBundle.loadString('assets/data/trips.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      final batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final tripId = _getValue(row, headers, 'trip_id');
          if (tripId.isEmpty) continue;

          batch.insert(
              'trips',
              {
                'trip_id': tripId,
                'route_id': _getValue(row, headers, 'route_id'),
                'service_id': _getValue(row, headers, 'service_id'),
                'trip_headsign': _getValue(row, headers, 'trip_headsign'),
                'direction_id':
                    int.tryParse(_getValue(row, headers, 'direction_id')),
                'shape_id': _getValue(row, headers, 'shape_id'),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          successCount++;
        } catch (e) {
          continue;
        }
      }

      await batch.commit(noResult: true);
      debugPrint('✅ Seferler yüklendi: $successCount');
    } catch (e) {
      debugPrint('❌ trips.txt hatası: $e');
    }
  }

  Future<void> _loadStopTimes() async {
    try {
      final csvString =
          await rootBundle.loadString('assets/data/stop_times.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      int batchCount = 0;
      var batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final tripId = _getValue(row, headers, 'trip_id');
          final stopId = _getValue(row, headers, 'stop_id');
          if (tripId.isEmpty || stopId.isEmpty) continue;

          batch.insert('stop_times', {
            'trip_id': tripId,
            'stop_id': stopId,
            'arrival_time': _getValue(row, headers, 'arrival_time'),
            'departure_time': _getValue(row, headers, 'departure_time'),
            'stop_sequence':
                int.tryParse(_getValue(row, headers, 'stop_sequence')) ?? 0,
          });

          successCount++;
          batchCount++;

          if (batchCount >= 5000) {
            await batch.commit(noResult: true);
            batch = _database!.batch();
            batchCount = 0;
          }
        } catch (e) {
          continue;
        }
      }

      if (batchCount > 0) await batch.commit(noResult: true);
      debugPrint('✅ stop_times yüklendi: $successCount');
    } catch (e) {
      debugPrint('❌ stop_times.txt hatası: $e');
    }
  }

  Future<void> _loadShapes() async {
    try {
      final csvString = await rootBundle.loadString('assets/data/shapes.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      int batchCount = 0;
      var batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final shapeId = _getValue(row, headers, 'shape_id');
          final lat = double.tryParse(_getValue(row, headers, 'shape_pt_lat'));
          final lon = double.tryParse(_getValue(row, headers, 'shape_pt_lon'));
          final seq =
              int.tryParse(_getValue(row, headers, 'shape_pt_sequence')) ?? 0;

          if (shapeId.isEmpty || lat == null || lon == null) continue;

          batch.insert('shapes', {
            'shape_id': shapeId,
            'shape_pt_lat': lat,
            'shape_pt_lon': lon,
            'shape_pt_sequence': seq,
          });

          successCount++;
          batchCount++;

          if (batchCount >= 5000) {
            await batch.commit(noResult: true);
            batch = _database!.batch();
            batchCount = 0;
          }
        } catch (e) {
          continue;
        }
      }

      if (batchCount > 0) await batch.commit(noResult: true);
      debugPrint('✅ shapes yüklendi: $successCount');
    } catch (e) {
      debugPrint('❌ shapes.txt hatası: $e');
    }
  }

  Future<void> _loadCalendar() async {
    try {
      final csvString = await rootBundle.loadString('assets/data/calendar.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      final batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final serviceId = _getValue(row, headers, 'service_id');
          if (serviceId.isEmpty) continue;

          batch.insert(
              'calendar',
              {
                'service_id': serviceId,
                'monday': int.tryParse(_getValue(row, headers, 'monday')) ?? 0,
                'tuesday':
                    int.tryParse(_getValue(row, headers, 'tuesday')) ?? 0,
                'wednesday':
                    int.tryParse(_getValue(row, headers, 'wednesday')) ?? 0,
                'thursday':
                    int.tryParse(_getValue(row, headers, 'thursday')) ?? 0,
                'friday': int.tryParse(_getValue(row, headers, 'friday')) ?? 0,
                'saturday':
                    int.tryParse(_getValue(row, headers, 'saturday')) ?? 0,
                'sunday': int.tryParse(_getValue(row, headers, 'sunday')) ?? 0,
                'start_date': _getValue(row, headers, 'start_date'),
                'end_date': _getValue(row, headers, 'end_date'),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          successCount++;
        } catch (e) {
          continue;
        }
      }

      await batch.commit(noResult: true);
      debugPrint('✅ calendar yüklendi: $successCount');
    } catch (e) {
      debugPrint('⚠️ calendar.txt yüklenemedi: $e');
    }
  }

  Future<void> _loadFrequencies() async {
    try {
      final csvString =
          await rootBundle.loadString('assets/data/frequencies.txt');
      final rows = const CsvToListConverter(fieldDelimiter: ',', eol: '\n')
          .convert(csvString);
      if (rows.isEmpty) return;

      final headers = _parseHeaders(rows[0]);
      int successCount = 0;
      final batch = _database!.batch();

      for (var i = 1; i < rows.length; i++) {
        try {
          final row = rows[i];
          final tripId = _getValue(row, headers, 'trip_id');
          final startTime = _getValue(row, headers, 'start_time');
          final endTime = _getValue(row, headers, 'end_time');
          final headwaySecs =
              int.tryParse(_getValue(row, headers, 'headway_secs')) ?? 0;

          if (tripId.isEmpty || startTime.isEmpty || endTime.isEmpty) continue;

          batch.insert('frequencies', {
            'trip_id': tripId,
            'start_time': startTime,
            'end_time': endTime,
            'headway_secs': headwaySecs,
            'exact_times':
                int.tryParse(_getValue(row, headers, 'exact_times')) ?? 0,
          });
          successCount++;
        } catch (e) {
          continue;
        }
      }

      await batch.commit(noResult: true);
      debugPrint('✅ frequencies yüklendi: $successCount');
    } catch (e) {
      debugPrint('⚠️ frequencies.txt yüklenemedi: $e');
    }
  }

  // ==================== YARDIMCI FONKSİYONLAR ====================

  Map<String, int> _parseHeaders(List<dynamic> headerRow) {
    final headers = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      headers[headerRow[i].toString().trim().toLowerCase()] = i;
    }
    return headers;
  }

  String _getValue(List<dynamic> row, Map<String, int> headers, String key) {
    final index = headers[key.toLowerCase()];
    if (index == null || index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }

  // ==================== SORGULAR ====================

  Future<List<Stop>> getAllStops() async {
    if (_database == null) await initialize();
    final maps = await _database!.query('stops');
    return maps.map((map) => Stop.fromMap(map)).toList();
  }

  Future<List<TransitRoute>> getAllRoutes() async {
    if (_database == null) await initialize();
    final maps = await _database!.query('routes',
        where: 'is_active = ?', whereArgs: [1], orderBy: 'route_short_name');
    return maps.map((map) => TransitRoute.fromMap(map)).toList();
  }

  Future<List<TransitRoute>> getRoutesForStop(String stopId) async {
    if (_database == null) await initialize();

    final maps = await _database!.rawQuery('''
      SELECT DISTINCT r.* FROM routes r
      INNER JOIN trips t ON r.route_id = t.route_id
      INNER JOIN stop_times st ON t.trip_id = st.trip_id
      WHERE st.stop_id = ? AND r.is_active = 1
      ORDER BY CAST(r.route_short_name AS INTEGER), r.route_short_name
    ''', [stopId]);

    return maps.map((map) => TransitRoute.fromMap(map)).toList();
  }

  Future<List<Map<String, double>>> getShapeForRoute(String routeId,
      {int direction = 1}) async {
    if (_database == null) await initialize();

    final shapeId = '$routeId$direction';
    final maps = await _database!.rawQuery('''
      SELECT shape_pt_lat, shape_pt_lon, shape_pt_sequence
      FROM shapes WHERE shape_id = ? ORDER BY shape_pt_sequence
    ''', [shapeId]);

    return maps
        .map((map) => {
              'lat': (map['shape_pt_lat'] as num).toDouble(),
              'lon': (map['shape_pt_lon'] as num).toDouble(),
            })
        .toList();
  }

  Future<List<Stop>> getStopsForRouteDirection(String routeId,
      {int direction = 1}) async {
    if (_database == null) await initialize();

    final gtfsDirection = direction - 1;

    final bestTripResult = await _database!.rawQuery('''
      SELECT t.trip_id, COUNT(st.stop_id) as stop_count
      FROM trips t
      INNER JOIN stop_times st ON t.trip_id = st.trip_id
      WHERE t.route_id = ? AND t.direction_id = ?
      GROUP BY t.trip_id
      ORDER BY stop_count DESC
      LIMIT 1
    ''', [routeId, gtfsDirection]);

    String? primaryTripId;
    if (bestTripResult.isNotEmpty) {
      primaryTripId = bestTripResult.first['trip_id'] as String;
    }

    if (primaryTripId == null) {
      final nullDirResult = await _database!.rawQuery('''
        SELECT t.trip_id, COUNT(st.stop_id) as stop_count
        FROM trips t
        INNER JOIN stop_times st ON t.trip_id = st.trip_id
        WHERE t.route_id = ? AND (t.direction_id IS NULL OR t.direction_id = ?)
        GROUP BY t.trip_id
        ORDER BY stop_count DESC
        LIMIT 1
      ''', [routeId, gtfsDirection]);

      if (nullDirResult.isNotEmpty) {
        primaryTripId = nullDirResult.first['trip_id'] as String;
        debugPrint('⚠️ direction_id NULL fallback kullanıldı: $primaryTripId');
      }
    }

    if (primaryTripId == null) {
      debugPrint('❌ getStopsForRouteDirection: trip bulunamadı '
          '(routeId=$routeId, direction=$direction)');
      return [];
    }

    final maps = await _database!.rawQuery('''
      SELECT s.*, st.stop_sequence
      FROM stop_times st
      INNER JOIN stops s ON s.stop_id = st.stop_id
      WHERE st.trip_id = ?
      ORDER BY st.stop_sequence ASC
    ''', [primaryTripId]);

    final seen = <String>{};
    final stops = <Stop>[];
    for (final map in maps) {
      final stopId = map['stop_id'] as String;
      if (seen.contains(stopId)) continue;
      seen.add(stopId);
      stops.add(Stop.fromMap(map));
    }

    debugPrint('📍 getStopsForRouteDirection: routeId=$routeId '
        'direction=$direction → trip=$primaryTripId → ${stops.length} durak');

    return stops;
  }

  Future<List<Stop>> getStopsForRouteThroughStop(
      String routeId, String targetStopId) async {
    if (_database == null) await initialize();

    final tripResult = await _database!.rawQuery('''
      SELECT t.trip_id, t.direction_id, COUNT(st2.stop_id) as stop_count
      FROM trips t
      INNER JOIN stop_times st ON t.trip_id = st.trip_id AND st.stop_id = ?
      INNER JOIN stop_times st2 ON t.trip_id = st2.trip_id
      WHERE t.route_id = ?
      GROUP BY t.trip_id
      ORDER BY stop_count DESC
      LIMIT 1
    ''', [targetStopId, routeId]);

    if (tripResult.isEmpty) {
      debugPrint('❌ getStopsForRouteThroughStop: "$targetStopId" durağını '
          'içeren trip bulunamadı (routeId=$routeId)');
      return [];
    }

    final tripId = tripResult.first['trip_id'] as String;
    final directionId = tripResult.first['direction_id'];
    debugPrint('✅ getStopsForRouteThroughStop: "$targetStopId" için '
        'trip=$tripId direction=$directionId seçildi');

    final maps = await _database!.rawQuery('''
      SELECT s.*, st.stop_sequence
      FROM stop_times st
      INNER JOIN stops s ON s.stop_id = st.stop_id
      WHERE st.trip_id = ?
      ORDER BY st.stop_sequence ASC
    ''', [tripId]);

    final seen = <String>{};
    final stops = <Stop>[];
    for (final map in maps) {
      final stopId = map['stop_id'] as String;
      if (seen.contains(stopId)) continue;
      seen.add(stopId);
      stops.add(Stop.fromMap(map));
    }

    return stops;
  }

  Future<List<TransitRoute>> findRoutesBetweenStops(
      String fromStopId, String toStopId) async {
    if (_database == null) await initialize();

    final maps = await _database!.rawQuery('''
      SELECT DISTINCT r.* FROM routes r
      INNER JOIN trips t ON r.route_id = t.route_id
      WHERE r.is_active = 1
      AND EXISTS (
        SELECT 1 FROM stop_times st1
        INNER JOIN stop_times st2 ON st1.trip_id = st2.trip_id
        WHERE st1.stop_id = ? 
        AND st2.stop_id = ?
        AND st1.stop_sequence < st2.stop_sequence
        AND st1.trip_id = t.trip_id
      )
      ORDER BY CAST(r.route_short_name AS INTEGER), r.route_short_name
    ''', [fromStopId, toStopId]);

    return maps.map((map) => TransitRoute.fromMap(map)).toList();
  }

  Future<int> getEstimatedDuration(
      String routeId, String fromStopId, String toStopId) async {
    if (_database == null) await initialize();

    final result = await _database!.rawQuery('''
      SELECT st1.stop_sequence as from_seq, st2.stop_sequence as to_seq
      FROM stop_times st1
      INNER JOIN stop_times st2 ON st1.trip_id = st2.trip_id
      INNER JOIN trips t ON st1.trip_id = t.trip_id
      WHERE t.route_id = ? AND st1.stop_id = ? AND st2.stop_id = ?
      AND st1.stop_sequence < st2.stop_sequence
      LIMIT 1
    ''', [routeId, fromStopId, toStopId]);

    if (result.isEmpty) return 15;

    final fromSeq = result.first['from_seq'] as int;
    final toSeq = result.first['to_seq'] as int;
    return ((toSeq - fromSeq) * 1.5).round().clamp(5, 120);
  }

  // ==================== SEFER SAATLERİ ====================

  String _todayWeekdayColumn() {
    switch (DateTime.now().weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
        return 'sunday';
      default:
        return 'monday';
    }
  }

  String _todayAsGtfsDate() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  int? _timeToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length < 2) return null;
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      if (hours == null || minutes == null) return null;
      return hours * 60 + minutes;
    } catch (e) {
      return null;
    }
  }

  String _minutesToTime(int minutes) {
    var m = minutes;
    if (m >= 24 * 60) m = m % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  Future<String?> _resolveRouteId(String routeIdentifier) async {
    if (_database == null) await initialize();

    final result = await _database!.query(
      'routes',
      columns: ['route_id'],
      where: 'route_short_name = ? OR route_id = ?',
      whereArgs: [routeIdentifier, routeIdentifier],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['route_id'] as String;
    }
    return null;
  }

  Future<List<String>> getUpcomingDeparturesForStop(
      String routeIdentifier, String stopId,
      {int? direction}) async {
    if (_database == null) await initialize();

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final actualRouteId = await _resolveRouteId(routeIdentifier);
    if (actualRouteId == null) return [];

    final todayCol = _todayWeekdayColumn();
    final todayStr = _todayAsGtfsDate();

    final gtfsDirection = direction != null ? direction - 1 : null;
    final directionFilter =
        gtfsDirection != null ? 'AND t.direction_id = $gtfsDirection' : '';

    final allDepartures = <int>{};

    final calendarTrips = await _database!.rawQuery('''
      SELECT DISTINCT t.trip_id, t.trip_headsign,
             st.departure_time as dep_time
      FROM trips t
      INNER JOIN stop_times st ON t.trip_id = st.trip_id
      INNER JOIN calendar c ON t.service_id = c.service_id
      WHERE t.route_id = ?
        AND st.stop_sequence = 1
        AND c.$todayCol = 1
        AND ? BETWEEN c.start_date AND c.end_date
        $directionFilter
    ''', [actualRouteId, todayStr]);

    debugPrint(
        '📅 calendarTrips count: ${calendarTrips.length} (routeId=$actualRouteId, day=$todayCol, date=$todayStr)');

    final List<Map<String, Object?>> tripRows;
    if (calendarTrips.isNotEmpty) {
      tripRows = calendarTrips;
    } else {
      debugPrint('⚠️ Calendar boş döndü — bypass ile tüm tripleri alıyorum');
      final bypassTrips = await _database!.rawQuery('''
        SELECT DISTINCT t.trip_id, t.trip_headsign,
               st.departure_time as dep_time
        FROM trips t
        INNER JOIN stop_times st ON t.trip_id = st.trip_id
        WHERE t.route_id = ?
          AND st.stop_sequence = 1
          AND st.departure_time IS NOT NULL
          AND st.departure_time != ''
          $directionFilter
        ORDER BY st.departure_time
      ''', [actualRouteId]);
      tripRows = bypassTrips;
      debugPrint('🔄 Bypass trip sayısı: ${bypassTrips.length}');
    }

    for (final tripRow in tripRows) {
      final tripId = tripRow['trip_id'] as String;
      final depTimeStr = tripRow['dep_time']?.toString() ?? '';

      final freqQuery = await _database!.query(
        'frequencies',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );

      if (freqQuery.isNotEmpty) {
        for (final freq in freqQuery) {
          final startMinutes = _timeToMinutes(freq['start_time'] as String);
          final endMinutes = _timeToMinutes(freq['end_time'] as String);
          final headwaySecs = freq['headway_secs'] as int;

          if (startMinutes == null || endMinutes == null || headwaySecs <= 0) {
            continue;
          }
          final headwayMinutes = headwaySecs ~/ 60;
          if (headwayMinutes <= 0) continue;

          var t = startMinutes;
          while (t <= endMinutes) {
            final dep = t % (24 * 60);
            if (dep >= currentMinutes) allDepartures.add(dep);
            t += headwayMinutes;
          }
        }
      } else {
        if (depTimeStr.isNotEmpty && depTimeStr != '00:00:00') {
          final dep = (_timeToMinutes(depTimeStr) ?? 0) % (24 * 60);
          if (dep >= currentMinutes) allDepartures.add(dep);
        }
      }
    }

    if (allDepartures.isEmpty) {
      debugPrint('⚠️ ADIM 4: frequencies-only fallback');
      final freqOnly = await _database!.rawQuery('''
        SELECT f.start_time, f.end_time, f.headway_secs
        FROM frequencies f
        INNER JOIN trips t ON f.trip_id = t.trip_id
        WHERE t.route_id = ?
          $directionFilter
        LIMIT 100
      ''', [actualRouteId]);

      for (final freq in freqOnly) {
        final startMinutes = _timeToMinutes(freq['start_time'] as String);
        final endMinutes = _timeToMinutes(freq['end_time'] as String);
        final headwaySecs = freq['headway_secs'] as int;
        if (startMinutes == null || endMinutes == null || headwaySecs <= 0) {
          continue;
        }
        final headwayMinutes = headwaySecs ~/ 60;
        if (headwayMinutes <= 0) continue;
        var t = startMinutes;
        while (t <= endMinutes) {
          final dep = t % (24 * 60);
          if (dep >= currentMinutes) allDepartures.add(dep);
          t += headwayMinutes;
        }
      }
    }

    final sortedDepartures = allDepartures.toList()..sort();
    return sortedDepartures.take(10).map((m) => _minutesToTime(m)).toList();
  }

  Future<Map<String, String?>> getFirstLastDepartures(String routeIdentifier,
      {int? direction}) async {
    final actualRouteId = await _resolveRouteId(routeIdentifier);
    if (actualRouteId == null) return {'first': null, 'last': null};

    final todayCol = _todayWeekdayColumn();
    final todayStr = _todayAsGtfsDate();

    final freqResult = await _database!.rawQuery('''
      SELECT MIN(f.start_time) as first_time, MAX(f.end_time) as last_time
      FROM frequencies f
      INNER JOIN trips t ON f.trip_id = t.trip_id
      INNER JOIN calendar c ON t.service_id = c.service_id
      WHERE t.route_id = ?
        AND c.$todayCol = 1
        AND ? BETWEEN c.start_date AND c.end_date
    ''', [actualRouteId, todayStr]);

    if (freqResult.isNotEmpty && freqResult.first['first_time'] != null) {
      return {
        'first': _minutesToTime(
            _timeToMinutes(freqResult.first['first_time']?.toString()) ?? 0),
        'last': _minutesToTime(
            _timeToMinutes(freqResult.first['last_time']?.toString()) ?? 0),
      };
    }

    debugPrint('⚠️ getFirstLastDepartures: calendar bypass');
    final stResult = await _database!.rawQuery('''
      SELECT MIN(st.departure_time) as first_time,
             MAX(st.departure_time) as last_time
      FROM stop_times st
      INNER JOIN trips t ON st.trip_id = t.trip_id
      WHERE t.route_id = ?
        AND st.stop_sequence = 1
        AND st.departure_time IS NOT NULL
        AND st.departure_time != '00:00:00'
    ''', [actualRouteId]);

    if (stResult.isNotEmpty && stResult.first['first_time'] != null) {
      return {
        'first': stResult.first['first_time'] as String?,
        'last': stResult.first['last_time'] as String?,
      };
    }

    final freqFallback = await _database!.rawQuery('''
      SELECT MIN(f.start_time) as first_time, MAX(f.end_time) as last_time
      FROM frequencies f
      INNER JOIN trips t ON f.trip_id = t.trip_id
      WHERE t.route_id = ?
    ''', [actualRouteId]);

    if (freqFallback.isNotEmpty && freqFallback.first['first_time'] != null) {
      return {
        'first': _minutesToTime(
            _timeToMinutes(freqFallback.first['first_time']?.toString()) ?? 0),
        'last': _minutesToTime(
            _timeToMinutes(freqFallback.first['last_time']?.toString()) ?? 0),
      };
    }

    return {'first': null, 'last': null};
  }

  Future<String> getOperatingHoursForRoute(String routeIdentifier,
      {int? direction}) async {
    final firstLast =
        await getFirstLastDepartures(routeIdentifier, direction: direction);
    if (firstLast['first'] == null || firstLast['last'] == null) {
      return 'Sefer bilgisi yok';
    }
    return '${firstLast['first']} - ${firstLast['last']}';
  }

  Future<List<StopTime>> getUpcomingTripsForRoute(String routeId, String stopId,
      {int? direction}) async {
    final departures = await getUpcomingDeparturesForStop(routeId, stopId,
        direction: direction);
    return departures
        .map((time) => StopTime(
              tripId: '',
              stopId: stopId,
              arrivalTime: time,
              departureTime: time,
              stopSequence: 0,
            ))
        .toList();
  }

  // ==================== SMART ROUTING ====================

  /// Yakındaki durakları getirir.
  /// Kıbrıs modunda GtfsQueryService (cyprus.db) + KIBHAS duraklarını döner.
  Future<List<Stop>> getNearbyStops(double userLat, double userLon,
      {double maxDistance = 1500}) async {
    if (!_isManisa) {
      debugPrint('🌍 getNearbyStops → Kıbrıs modu (GtfsQueryService)');
      final raw = await GtfsQueryService.instance
          .getNearbyStops(userLat, userLon, radiusMeters: maxDistance);

      final gtfsStops = raw.map((s) {
        return Stop(
          stopId: s['stop_id']?.toString() ?? '',
          stopName: s['stop_name']?.toString() ?? '',
          latitude: (s['stop_lat'] as num).toDouble(),
          longitude: (s['stop_lon'] as num).toDouble(),
          distanceFromUser: (s['distance_m'] as num).toDouble(),
        );
      }).toList();

      // ✅ Yakındaki KIBHAS duraklarını da ekle
      final kibhasStops = <Stop>[];
      for (final ks in kAllKibhasStops) {
        final d = _calculateDistance(userLat, userLon, ks.lat, ks.lon);
        if (d <= maxDistance) {
          kibhasStops.add(Stop(
            stopId: ks.stopId,
            stopName: ks.stopName,
            latitude: ks.lat,
            longitude: ks.lon,
            distanceFromUser: d,
          ));
        }
      }
      kibhasStops.sort((a, b) =>
          (a.distanceFromUser ?? 0).compareTo(b.distanceFromUser ?? 0));

      // GTFS durakları önce, KIBHAS durakları arkaya
      return [...gtfsStops, ...kibhasStops];
    }

    // ── Manisa: orijinal kod ──────────────────────────────────────────────
    if (_database == null) await initialize();

    final allStops = await getAllStops();
    final nearbyStops = <Map<String, dynamic>>[];

    for (final stop in allStops) {
      final distance =
          _calculateDistance(userLat, userLon, stop.latitude, stop.longitude);
      if (distance <= maxDistance) {
        nearbyStops.add({'stop': stop, 'distance': distance});
      }
    }

    nearbyStops.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    return nearbyStops.map((data) {
      final stop = data['stop'] as Stop;
      final distance = data['distance'] as double;
      return stop.copyWith(distanceFromUser: distance);
    }).toList();
  }

  /// Akıllı rota arama.
  /// Kıbrıs modunda GtfsQueryService.planRoutes kullanır.
  Future<List<Map<String, dynamic>>> findSmartRoutes({
    required double userLat,
    required double userLon,
    required double destLat,
    required double destLon,
    double maxWalkingDistance = 1000,
    Stop? forceBoardingStop,
  }) async {
    debugPrint('🗺️ findSmartRoutes:');
    debugPrint('   User: $userLat, $userLon');
    debugPrint('   Dest: $destLat, $destLon');

    if (!_isManisa) {
      debugPrint('   🌍 Kıbrıs modu — GtfsQueryService kullanılıyor');

      // ✅ forceBoardingStop bir KIBHAS durağıysa (kibhas_stop_xxx),
      // GtfsQueryService'i çağırma — KktcBusService'ten direkt al
      if (forceBoardingStop != null &&
          KktcBusService.instance.isKibhasStop(forceBoardingStop.stopId)) {
        debugPrint(
            '   🚌 KIBHAS durağı seçildi: ${forceBoardingStop.stopName}');
        final matchingLines =
            KktcBusService.instance.linesForStop(forceBoardingStop.stopId);

        if (matchingLines.isEmpty) return [];

        final walkToStop = _calculateDistance(
          userLat,
          userLon,
          forceBoardingStop.latitude,
          forceBoardingStop.longitude,
        );

        // ✅ Aynı hatta geçen diğer KIBHAS duraklarını da ekle
        // (Sabancı seçilince DAÜ, Üst Geçit gibi yakın durakları da öner)
        final nearbyKibhasOnSameLines = <KktcBusStop>[];
        final seenStopIds = <String>{forceBoardingStop.stopId};
        for (final line in matchingLines) {
          for (final s in line.stops) {
            if (!seenStopIds.add(s.stopId)) continue;
            nearbyKibhasOnSameLines.add(s);
          }
        }

        final results = <Map<String, dynamic>>[];
        for (final line in matchingLines) {
          final upcoming = KktcBusService.instance.nextDepartures(line, max: 1);
          final nextDep = upcoming.isNotEmpty ? upcoming.first.time : null;
          final isOp =
              upcoming.isNotEmpty && upcoming.first.minutesFromNow < 480;

          // Hedef koordinata en yakın iniş durağını bul
          KktcBusStop? bestAlighting;
          double bestDist = double.infinity;
          for (final s in line.stops) {
            if (s.stopId == forceBoardingStop.stopId) continue;
            final d = _calculateDistance(destLat, destLon, s.lat, s.lon);
            if (d < bestDist) {
              bestDist = d;
              bestAlighting = s;
            }
          }
          bestAlighting ??= line.stops.last;

          final alightingStop = Stop(
            stopId: bestAlighting.stopId,
            stopName: bestAlighting.stopName,
            latitude: bestAlighting.lat,
            longitude: bestAlighting.lon,
            distanceFromUser: bestDist,
          );

          final route = TransitRoute(
            routeId: line.id,
            routeShortName: line.company,
            // ✅ Seçilen durak adını göster — "Sabancı → Ercan Havalimanı"
            routeLongName: '${forceBoardingStop.stopName} → ${line.to}',
            routeType: 3,
            routeColor: _companyColorHex(line.company),
            isActive: true,
          );

          final walkingTime = ((walkToStop + bestDist) / 80).round();

          results.add({
            'route': route,
            'boardingStop': forceBoardingStop,
            'alightingStop': alightingStop,
            'walkToStop': walkToStop,
            'walkFromStop': bestDist,
            'rideDuration': line.durationMinutes,
            'totalDuration': line.durationMinutes + walkingTime,
            'nextDeparture': nextDep,
            'isOperating': isOp,
          });
        }

        // ✅ Aynı hattaki diğer KIBHAS duraklarını Stop listesi olarak döndür
        // destination_search_screen bu listeyi alternativeKibhasStops olarak kullanır
        final altKibhasStops = nearbyKibhasOnSameLines.map((ks) {
          final d = _calculateDistance(forceBoardingStop.latitude,
              forceBoardingStop.longitude, ks.lat, ks.lon);
          return Stop(
            stopId: ks.stopId,
            stopName: ks.stopName,
            latitude: ks.lat,
            longitude: ks.lon,
            distanceFromUser: d,
          );
        }).toList()
          ..sort((a, b) =>
              (a.distanceFromUser ?? 0).compareTo(b.distanceFromUser ?? 0));

        // results listesine meta olarak ekle (ilk sonuçta taşı)
        if (results.isNotEmpty) {
          results[0]['alternativeKibhasStops'] = altKibhasStops;
        }

        return results;
      }

      // Normal GTFS durağı ya da forceBoardingStop yok → planRoutes
      final fromLat = forceBoardingStop?.latitude ?? userLat;
      final fromLon = forceBoardingStop?.longitude ?? userLon;
      final walkRadius = forceBoardingStop != null ? 50.0 : maxWalkingDistance;

      final results = await GtfsQueryService.instance.planRoutes(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: destLat,
        toLon: destLon,
        walkRadius: walkRadius,
      );

      return results.map((r) {
        final routeMap = r['route'] as Map<String, dynamic>;
        final boardingMap = r['boarding_stop'] as Map<String, dynamic>;
        final alightingMap = r['alighting_stop'] as Map<String, dynamic>;
        final walkTo = (r['walk_to_m'] as num).toDouble();
        final walkFrom = (r['walk_from_m'] as num).toDouble();
        final nextDeps = r['next_departures'] as List<String>;

        final route = TransitRoute(
          routeId: routeMap['route_id']?.toString() ?? '',
          routeShortName: routeMap['route_short_name']?.toString() ?? '',
          routeLongName: routeMap['route_long_name']?.toString() ?? '',
          routeType: (routeMap['route_type'] as num?)?.toInt() ?? 3,
          isActive: true,
        );

        final Stop boardingStop;
        if (forceBoardingStop != null) {
          boardingStop = forceBoardingStop;
        } else {
          boardingStop = Stop(
            stopId: boardingMap['stop_id']?.toString() ?? '',
            stopName: boardingMap['stop_name']?.toString() ?? '',
            latitude: (boardingMap['stop_lat'] as num).toDouble(),
            longitude: (boardingMap['stop_lon'] as num).toDouble(),
            distanceFromUser: walkTo,
          );
        }

        final alightingStop = Stop(
          stopId: alightingMap['stop_id']?.toString() ?? '',
          stopName: alightingMap['stop_name']?.toString() ?? '',
          latitude: (alightingMap['stop_lat'] as num).toDouble(),
          longitude: (alightingMap['stop_lon'] as num).toDouble(),
          distanceFromUser: walkFrom,
        );

        final actualWalkTo = forceBoardingStop != null
            ? _calculateDistance(userLat, userLon, forceBoardingStop.latitude,
                forceBoardingStop.longitude)
            : walkTo;

        final walkingTime = ((actualWalkTo + walkFrom) / 80).round();
        final totalDuration = 20 + walkingTime;

        return {
          'route': route,
          'boardingStop': boardingStop,
          'alightingStop': alightingStop,
          'walkToStop': actualWalkTo,
          'walkFromStop': walkFrom,
          'rideDuration': 20,
          'totalDuration': totalDuration,
          'nextDeparture': nextDeps.isNotEmpty ? nextDeps.first : null,
          'isOperating': nextDeps.isNotEmpty,
        };
      }).toList();
    }

    // ── Manisa: orijinal kod ──────────────────────────────────────────────
    if (_database == null) await initialize();

    if (forceBoardingStop != null) {
      debugPrint('   🎯 Zorunlu biniş durağı: ${forceBoardingStop.stopName}');
    }

    final allStops = await getAllStops();

    final allUserStops = <Map<String, dynamic>>[];
    final allDestStops = <Map<String, dynamic>>[];

    for (final stop in allStops) {
      final userDist =
          _calculateDistance(userLat, userLon, stop.latitude, stop.longitude);
      final destDist =
          _calculateDistance(destLat, destLon, stop.latitude, stop.longitude);

      if (userDist <= 2000)
        allUserStops.add({'stop': stop, 'distance': userDist});
      if (destDist <= 2000)
        allDestStops.add({'stop': stop, 'distance': destDist});
    }

    allUserStops.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
    allDestStops.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    if (allUserStops.isEmpty || allDestStops.isEmpty) {
      debugPrint('   ❌ Yakında durak yok!');
      return [];
    }

    final foundRoutes = <String, Map<String, dynamic>>{};

    if (forceBoardingStop != null) {
      final walkToStop = _calculateDistance(userLat, userLon,
          forceBoardingStop.latitude, forceBoardingStop.longitude);

      for (final destStopData in allDestStops.take(30)) {
        final destStop = destStopData['stop'] as Stop;
        final walkFromStop = destStopData['distance'] as double;

        if (forceBoardingStop.stopId == destStop.stopId) continue;

        final routes = await findRoutesBetweenStops(
            forceBoardingStop.stopId, destStop.stopId);

        for (final route in routes) {
          final routeKey = route.routeId;
          final existing = foundRoutes[routeKey];
          final rideDuration = await getEstimatedDuration(
              route.routeId, forceBoardingStop.stopId, destStop.stopId);
          final walkingTime = ((walkToStop + walkFromStop) / 80).round();
          final totalDuration = rideDuration + walkingTime;

          bool isBetter = existing == null ||
              totalDuration < (existing['totalDuration'] as int) - 5 ||
              (totalDuration <= (existing['totalDuration'] as int) + 5 &&
                  walkFromStop < (existing['walkFromStop'] as double));

          if (isBetter) {
            String? nextDeparture;
            final departures = await getUpcomingDeparturesForStop(
                route.routeShortName, forceBoardingStop.stopId,
                direction: 1);
            if (departures.isNotEmpty) nextDeparture = departures.first;

            foundRoutes[routeKey] = {
              'route': route,
              'boardingStop':
                  forceBoardingStop.copyWith(distanceFromUser: walkToStop),
              'alightingStop':
                  destStop.copyWith(distanceFromUser: walkFromStop),
              'walkToStop': walkToStop,
              'walkFromStop': walkFromStop,
              'rideDuration': rideDuration,
              'totalDuration': totalDuration,
              'nextDeparture': nextDeparture,
              'isOperating': departures.isNotEmpty,
            };
          }
        }
      }
    } else {
      var userStopsToTry =
          allUserStops.where((s) => (s['distance'] as double) <= 800).toList();
      var destStopsToTry =
          allDestStops.where((s) => (s['distance'] as double) <= 800).toList();

      await _searchRoutes(userStopsToTry, destStopsToTry, foundRoutes);

      if (foundRoutes.isEmpty) {
        userStopsToTry = allUserStops.where((s) {
          final d = s['distance'] as double;
          return d > 800 && d <= 1500;
        }).toList();
        destStopsToTry = allDestStops
            .where((s) => (s['distance'] as double) <= 1000)
            .toList();
        await _searchRoutes(userStopsToTry, destStopsToTry, foundRoutes);
      }

      if (foundRoutes.isEmpty) {
        userStopsToTry = allUserStops.where((s) {
          final d = s['distance'] as double;
          return d > 1500 && d <= 2000;
        }).toList();
        destStopsToTry = allDestStops
            .where((s) => (s['distance'] as double) <= 1500)
            .toList();
        await _searchRoutes(userStopsToTry, destStopsToTry, foundRoutes);
      }
    }

    final results = foundRoutes.values.toList();
    results.sort((a, b) {
      final walkFromA = a['walkFromStop'] as double;
      final walkFromB = b['walkFromStop'] as double;
      if ((walkFromA - walkFromB).abs() > 200) {
        return walkFromA.compareTo(walkFromB);
      }
      return (a['totalDuration'] as int).compareTo(b['totalDuration'] as int);
    });

    return results.take(10).toList();
  }

  Future<void> _searchRoutes(
    List<Map<String, dynamic>> userStops,
    List<Map<String, dynamic>> destStops,
    Map<String, Map<String, dynamic>> foundRoutes,
  ) async {
    for (final userStopData in userStops.take(25)) {
      final userStop = userStopData['stop'] as Stop;
      final walkToStop = userStopData['distance'] as double;

      for (final destStopData in destStops.take(25)) {
        final destStop = destStopData['stop'] as Stop;
        final walkFromStop = destStopData['distance'] as double;

        if (userStop.stopId == destStop.stopId) continue;

        final routes =
            await findRoutesBetweenStops(userStop.stopId, destStop.stopId);

        for (final route in routes) {
          final routeKey = route.routeId;
          final existing = foundRoutes[routeKey];
          final rideDuration = await getEstimatedDuration(
              route.routeId, userStop.stopId, destStop.stopId);
          final walkingTime = ((walkToStop + walkFromStop) / 80).round();
          final totalDuration = rideDuration + walkingTime;

          bool isBetter = existing == null ||
              totalDuration < (existing['totalDuration'] as int) - 5 ||
              (totalDuration <= (existing['totalDuration'] as int) + 5 &&
                  walkFromStop < (existing['walkFromStop'] as double));

          if (isBetter) {
            String? nextDeparture;
            final departures = await getUpcomingDeparturesForStop(
                route.routeShortName, userStop.stopId,
                direction: 1);
            if (departures.isNotEmpty) nextDeparture = departures.first;

            foundRoutes[routeKey] = {
              'route': route,
              'boardingStop': userStop.copyWith(distanceFromUser: walkToStop),
              'alightingStop':
                  destStop.copyWith(distanceFromUser: walkFromStop),
              'walkToStop': walkToStop,
              'walkFromStop': walkFromStop,
              'rideDuration': rideDuration,
              'totalDuration': totalDuration,
              'nextDeparture': nextDeparture,
              'isOperating': departures.isNotEmpty,
            };
          }
        }
      }
    }
  }

  // ==================== ALTERNATİF DURAK & AKTARMA ====================

  Future<List<Stop>> getNearbyAlternativeStops(
    Stop fromStop, {
    double maxDistance = 600,
    int limit = 5,
  }) async {
    if (_database == null) await initialize();
    final allStops = await getAllStops();

    final alternatives = <Map<String, dynamic>>[];
    for (final stop in allStops) {
      if (stop.stopId == fromStop.stopId) continue;
      final d = _calculateDistance(
          fromStop.latitude, fromStop.longitude, stop.latitude, stop.longitude);
      if (d <= maxDistance) {
        alternatives.add({'stop': stop, 'distance': d});
      }
    }

    alternatives.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    return alternatives.take(limit).map((e) {
      final stop = e['stop'] as Stop;
      final dist = e['distance'] as double;
      return stop.copyWith(distanceFromUser: dist);
    }).toList();
  }

  /// Aktarmalı rota arama.
  /// Kıbrıs modunda boş liste döner.
  Future<List<Map<String, dynamic>>> findTransferRoutes({
    required double userLat,
    required double userLon,
    required double destLat,
    required double destLon,
    double maxWalkingDistance = 2000,
    Stop? forceBoardingStop,
  }) async {
    debugPrint('🔄 findTransferRoutes başlıyor...');

    if (!_isManisa) {
      debugPrint('   🌍 Kıbrıs modu — transfer routes desteklenmiyor');
      return [];
    }

    if (_database == null) await initialize();

    final allStops = await getAllStops();

    List<Map<String, dynamic>> boardingCandidates;
    if (forceBoardingStop != null) {
      boardingCandidates = [
        {
          'stop': forceBoardingStop,
          'distance': _calculateDistance(userLat, userLon,
              forceBoardingStop.latitude, forceBoardingStop.longitude),
        }
      ];
    } else {
      boardingCandidates = [];
      for (final stop in allStops) {
        final d =
            _calculateDistance(userLat, userLon, stop.latitude, stop.longitude);
        if (d <= maxWalkingDistance) {
          boardingCandidates.add({'stop': stop, 'distance': d});
        }
      }
      boardingCandidates.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));
      boardingCandidates = boardingCandidates.take(15).toList();
    }

    final alightingCandidates = <Map<String, dynamic>>[];
    for (final stop in allStops) {
      final d =
          _calculateDistance(destLat, destLon, stop.latitude, stop.longitude);
      if (d <= maxWalkingDistance) {
        alightingCandidates.add({'stop': stop, 'distance': d});
      }
    }
    alightingCandidates.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
    final topAlighting = alightingCandidates.take(15).toList();

    final results = <Map<String, dynamic>>[];
    final seenKeys = <String>{};

    for (final boardData in boardingCandidates.take(8)) {
      final boardStop = boardData['stop'] as Stop;
      final walkToBoard = boardData['distance'] as double;

      final firstLegRoutes = await getRoutesForStop(boardStop.stopId);
      if (firstLegRoutes.isEmpty) continue;

      for (final firstRoute in firstLegRoutes.take(6)) {
        final dir1Stops =
            await getStopsForRouteDirection(firstRoute.routeId, direction: 1);
        final dir2Stops =
            await getStopsForRouteDirection(firstRoute.routeId, direction: 2);
        final transferCandidates = {...dir1Stops, ...dir2Stops}.toList();

        for (final transferStop in transferCandidates) {
          if (transferStop.stopId == boardStop.stopId) continue;

          for (final alightData in topAlighting.take(10)) {
            final alightStop = alightData['stop'] as Stop;
            final walkFromAlight = alightData['distance'] as double;

            if (alightStop.stopId == boardStop.stopId) continue;
            if (alightStop.stopId == transferStop.stopId) continue;

            final secondLegRoutes = await findRoutesBetweenStops(
                transferStop.stopId, alightStop.stopId);
            if (secondLegRoutes.isEmpty) continue;

            for (final secondRoute in secondLegRoutes.take(3)) {
              if (secondRoute.routeId == firstRoute.routeId) continue;

              final firstLegCheck = await findRoutesBetweenStops(
                  boardStop.stopId, transferStop.stopId);
              if (!firstLegCheck.any((r) => r.routeId == firstRoute.routeId))
                continue;

              final key =
                  '${firstRoute.routeId}_${transferStop.stopId}_${secondRoute.routeId}_${alightStop.stopId}';
              if (seenKeys.contains(key)) continue;
              seenKeys.add(key);

              final leg1Duration = await getEstimatedDuration(
                  firstRoute.routeId, boardStop.stopId, transferStop.stopId);
              final leg2Duration = await getEstimatedDuration(
                  secondRoute.routeId, transferStop.stopId, alightStop.stopId);
              final walkingTime = ((walkToBoard + walkFromAlight) / 80).round();
              const transferWait = 5;
              final totalDuration =
                  leg1Duration + leg2Duration + walkingTime + transferWait;

              final dep1 = await getUpcomingDeparturesForStop(
                  firstRoute.routeShortName, boardStop.stopId,
                  direction: 1);
              final dep2 = await getUpcomingDeparturesForStop(
                  secondRoute.routeShortName, transferStop.stopId,
                  direction: 1);

              results.add({
                'type': 'transfer',
                'firstRoute': firstRoute,
                'boardingStop':
                    boardStop.copyWith(distanceFromUser: walkToBoard),
                'transferStop': transferStop,
                'leg1Duration': leg1Duration,
                'nextDeparture1': dep1.isNotEmpty ? dep1.first : null,
                'isOperating1': dep1.isNotEmpty,
                'secondRoute': secondRoute,
                'alightingStop':
                    alightStop.copyWith(distanceFromUser: walkFromAlight),
                'leg2Duration': leg2Duration,
                'nextDeparture2': dep2.isNotEmpty ? dep2.first : null,
                'isOperating2': dep2.isNotEmpty,
                'walkToStop': walkToBoard,
                'walkFromStop': walkFromAlight,
                'totalDuration': totalDuration,
                'isOperating': dep1.isNotEmpty && dep2.isNotEmpty,
              });

              if (results.length >= 20) break;
            }
            if (results.length >= 20) break;
          }
          if (results.length >= 20) break;
        }
        if (results.length >= 20) break;
      }
      if (results.length >= 20) break;
    }

    results.sort((a, b) {
      final aOp = a['isOperating'] as bool;
      final bOp = b['isOperating'] as bool;
      if (aOp != bOp) return aOp ? -1 : 1;
      return (a['totalDuration'] as int).compareTo(b['totalDuration'] as int);
    });

    return results.take(5).toList();
  }

  // ==================== KKTC ROTA OLUŞTURUCU ====================

  /// forceBoardingStop verilmişse o durağa yakın terminalden hedefe giden
  /// hatları döner. Verilmemişse hedefe giden tüm hatlar.
  List<Map<String, dynamic>> _buildKktcRoutes(
    double destLat,
    double destLon, {
    Stop? forceBoardingStop,
    double userLat = 0,
    double userLon = 0,
  }) {
    const cityCoords = {
      'Lefkoşa': [35.1731, 33.3595],
      'Girne': [35.3414, 33.3193],
      'Mağusa': [35.1228, 33.9408],
      'Ercan': [35.1547, 33.4961],
      'Güzelyurt': [35.2009, 32.9970],
      'Lefke': [35.1167, 32.8500],
    };

    // Hedef koordinata en yakın şehri bul
    String? nearestDestCity;
    double minDestDist = double.infinity;
    for (final entry in cityCoords.entries) {
      final d =
          _calculateDistance(destLat, destLon, entry.value[0], entry.value[1]);
      if (d < minDestDist) {
        minDestDist = d;
        nearestDestCity = entry.key;
      }
    }
    if (nearestDestCity == null || minDestDist > 8000) return [];

    List<KktcBusLine> filtered;

    if (forceBoardingStop != null) {
      // Seçilen durağa en yakın KIBHAS şehrini bul
      String? nearestFromCity;
      double minFromDist = double.infinity;
      for (final entry in cityCoords.entries) {
        final d = _calculateDistance(forceBoardingStop.latitude,
            forceBoardingStop.longitude, entry.value[0], entry.value[1]);
        if (d < minFromDist) {
          minFromDist = d;
          nearestFromCity = entry.key;
        }
      }
      if (nearestFromCity == null) return [];
      // Aynı şehirdeyse KIBHAS'a gerek yok
      if (nearestFromCity == nearestDestCity) return [];

      filtered = kKktcBusLines
          .where((l) =>
              l.fromCity == nearestFromCity && l.toCity == nearestDestCity)
          .toList();
      // O yönde hat yoksa hedefe giden tüm hatları döndür (fallback)
      if (filtered.isEmpty) {
        filtered =
            kKktcBusLines.where((l) => l.toCity == nearestDestCity).toList();
      }
    } else {
      filtered =
          kKktcBusLines.where((l) => l.toCity == nearestDestCity).toList();
    }

    if (filtered.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    for (final line in filtered) {
      final upcoming = KktcBusService.instance.nextDepartures(line, max: 1);
      final nextDep = upcoming.isNotEmpty ? upcoming.first.time : null;
      final isOp = upcoming.isNotEmpty && upcoming.first.minutesFromNow < 480;

      final Stop boardingStop;
      final double walkToStop;
      if (forceBoardingStop != null) {
        boardingStop = forceBoardingStop;
        walkToStop = _calculateDistance(
          userLat,
          userLon,
          forceBoardingStop.latitude,
          forceBoardingStop.longitude,
        );
      } else {
        walkToStop = minDestDist > 500 ? 500.0 : minDestDist;
        boardingStop = Stop(
          stopId: '${line.id}_from',
          stopName: line.from,
          latitude: line.fromLat,
          longitude: line.fromLon,
          distanceFromUser: walkToStop,
        );
      }

      // ✅ routeLongName: seçilen durak adından hedefe — "Sabancı → Ercan Havalimanı"
      final boardingName = forceBoardingStop?.stopName ?? line.from;

      final route = TransitRoute(
        routeId: line.id,
        routeShortName: line.company,
        routeLongName: '$boardingName → ${line.to}',
        routeType: 3,
        routeColor: _companyColorHex(line.company),
        isActive: true,
      );

      final alightingStop = Stop(
        stopId: '${line.id}_to',
        stopName: line.to,
        latitude: line.toLat,
        longitude: line.toLon,
        distanceFromUser: 0,
      );

      results.add({
        'route': route,
        'boardingStop': boardingStop,
        'alightingStop': alightingStop,
        'walkToStop': walkToStop,
        'walkFromStop': 0.0,
        'rideDuration': line.durationMinutes,
        'totalDuration': line.durationMinutes + (walkToStop / 80).round(),
        'nextDeparture': nextDep,
        'isOperating': isOp,
      });
    }

    return results;
  }

  Future<Map<String, dynamic>> findRoutesWithFallback({
    required double userLat,
    required double userLon,
    required double destLat,
    required double destLon,
    double maxWalkingDistance = 2000,
    Stop? forceBoardingStop,
  }) async {
    final direct = await findSmartRoutes(
      userLat: userLat,
      userLon: userLon,
      destLat: destLat,
      destLon: destLon,
      maxWalkingDistance: maxWalkingDistance,
      forceBoardingStop: forceBoardingStop,
    );

    if (direct.isNotEmpty) {
      return {
        'direct': direct,
        'transfer': <Map<String, dynamic>>[],
        'alternativeStops': <Stop>[],
        'suggestion': null,
      };
    }

    debugPrint('⚠️ Direkt rota bulunamadı, alternatifler aranıyor...');

    if (!_isManisa) {
      // Kıbrıs: GTFS rotası bulunamadıysa _buildKktcRoutes dene
      // ✅ forceBoardingStop ve user koordinatlarını geç
      final kktcRoutes = _buildKktcRoutes(
        destLat,
        destLon,
        forceBoardingStop: forceBoardingStop,
        userLat: userLat,
        userLon: userLon,
      );
      if (kktcRoutes.isNotEmpty) {
        return {
          'direct': kktcRoutes,
          'transfer': <Map<String, dynamic>>[],
          'alternativeStops': <Stop>[],
          'suggestion': null,
        };
      }
      return {
        'direct': <Map<String, dynamic>>[],
        'transfer': <Map<String, dynamic>>[],
        'alternativeStops': <Stop>[],
        'suggestion': 'Bu güzergah için uygun rota bulunamadı.',
      };
    }

    List<Stop> alternativeStops = [];
    if (forceBoardingStop != null) {
      alternativeStops = await getNearbyAlternativeStops(
        forceBoardingStop,
        maxDistance: 600,
      );
    }

    final transfer = await findTransferRoutes(
      userLat: userLat,
      userLon: userLon,
      destLat: destLat,
      destLon: destLon,
      maxWalkingDistance: maxWalkingDistance,
      forceBoardingStop: forceBoardingStop,
    );

    String? suggestion;
    if (forceBoardingStop != null && alternativeStops.isNotEmpty) {
      final nearest = alternativeStops.first;
      final dist = nearest.distanceFromUser?.toInt() ?? 0;
      suggestion =
          '${forceBoardingStop.stopName} durağından bu güzergah için direkt hat bulunamadı. '
          '${dist}m ötedeki ${nearest.stopName} durağını deneyebilirsiniz.';
    } else if (transfer.isNotEmpty) {
      final t = transfer.first;
      final r1 = (t['firstRoute'] as TransitRoute).routeShortName;
      final r2 = (t['secondRoute'] as TransitRoute).routeShortName;
      final tStop = (t['transferStop'] as Stop).stopName;
      suggestion = 'Direkt hat bulunamadı. $r1 hattıyla $tStop durağında '
          'inerek $r2 hattına aktarma yapabilirsiniz.';
    }

    return {
      'direct': <Map<String, dynamic>>[],
      'transfer': transfer,
      'alternativeStops': alternativeStops,
      'suggestion': suggestion,
    };
  }

  // ==================== HESAPLAMA ====================

  /// Şirket adına göre GTFS hex renk kodu döner (routeColor alanı için)
  static String _companyColorHex(String company) {
    switch (company) {
      case 'KIBHAS':
        return '1565C0'; // koyu mavi
      case 'İtimat':
        return 'E65100'; // turuncu
      case 'Kombos':
        return '2E7D32'; // koyu yeşil
      default:
        return '455A64'; // gri
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
  }
}

class StopTime {
  final String tripId;
  final String stopId;
  final String? arrivalTime;
  final String? departureTime;
  final int stopSequence;

  StopTime({
    required this.tripId,
    required this.stopId,
    this.arrivalTime,
    this.departureTime,
    required this.stopSequence,
  });
}
