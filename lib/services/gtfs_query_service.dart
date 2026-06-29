import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'city_database_manager.dart';

class GtfsQueryService {
  static final GtfsQueryService instance = GtfsQueryService._internal();
  GtfsQueryService._internal();

  Database get _db => CityDatabaseManager.instance.database;

  // ==================== DURAKLAR ====================

  Future<List<Map<String, dynamic>>> getAllStops() async {
    return await _db.query('stops');
  }

  Future<Map<String, dynamic>?> getStop(String stopId) async {
    final r = await _db.query('stops',
        where: 'stop_id = ?', whereArgs: [stopId], limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  Future<List<Map<String, dynamic>>> getNearbyStops(double lat, double lon,
      {double radiusMeters = 500}) async {
    final all = await getAllStops();
    final result = <Map<String, dynamic>>[];
    for (final stop in all) {
      final sLat = (stop['stop_lat'] as num).toDouble();
      final sLon = (stop['stop_lon'] as num).toDouble();
      final dist = _haversine(lat, lon, sLat, sLon);
      if (dist <= radiusMeters) result.add({...stop, 'distance_m': dist});
    }
    result.sort((a, b) =>
        (a['distance_m'] as double).compareTo(b['distance_m'] as double));
    return result;
  }

  // ==================== HATLAR ====================

  Future<List<Map<String, dynamic>>> getAllActiveRoutes() async {
    return await _db.query('routes',
        where: 'is_active = 1',
        orderBy: 'CAST(route_short_name AS INTEGER), route_short_name');
  }

  Future<Map<String, dynamic>?> getRoute(String routeId) async {
    final r = await _db.query('routes',
        where: 'route_id = ?', whereArgs: [routeId], limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  Future<List<Map<String, dynamic>>> getRoutesForStop(String stopId) async {
    return await _db.rawQuery('''
      SELECT DISTINCT r.*
      FROM routes r
      JOIN trips t ON r.route_id = t.route_id
      JOIN stop_times st ON t.trip_id = st.trip_id
      WHERE st.stop_id = ? AND r.is_active = 1
      ORDER BY CAST(r.route_short_name AS INTEGER), r.route_short_name
    ''', [stopId]);
  }

  // ==================== SEFERLER ====================

  Future<List<Map<String, dynamic>>> getTripsForRoute(String routeId,
      {int? directionId}) async {
    final where = directionId != null
        ? 'route_id = ? AND direction_id = ?'
        : 'route_id = ?';
    final args = directionId != null ? [routeId, directionId] : [routeId];
    return await _db.query('trips', where: where, whereArgs: args);
  }

  // ==================== GÜZERGAH DURAKLARI ====================

  Future<List<Map<String, dynamic>>> getStopsForRoute(String routeId,
      {int direction = 0}) async {
    final best = await _db.rawQuery('''
      SELECT t.trip_id, COUNT(st.id) as cnt
      FROM trips t
      JOIN stop_times st ON t.trip_id = st.trip_id
      WHERE t.route_id = ? AND t.direction_id = ?
      GROUP BY t.trip_id
      ORDER BY cnt DESC
      LIMIT 1
    ''', [routeId, direction]);

    if (best.isEmpty) return [];

    final tripId = best.first['trip_id'] as String;
    return await _db.rawQuery('''
      SELECT s.*, st.stop_sequence, st.arrival_time, st.departure_time
      FROM stop_times st
      JOIN stops s ON s.stop_id = st.stop_id
      WHERE st.trip_id = ?
      ORDER BY st.stop_sequence ASC
    ''', [tripId]);
  }

  // ==================== SHAPE ====================

  Future<List<Map<String, dynamic>>> getShape(String shapeId) async {
    return await _db.rawQuery('''
      SELECT shape_pt_lat, shape_pt_lon
      FROM shapes
      WHERE shape_id = ?
      ORDER BY shape_pt_sequence ASC
    ''', [shapeId]);
  }

  /// routeId + direction → trips tablosundan shape_id bulur → shape koordinatlarını döner
  Future<List<Map<String, dynamic>>> getShapeForRoute(
    String routeId, {
    int direction = 0,
  }) async {
    // En çok durağa sahip trip'i bul (en temsili güzergah)
    final tripRows = await _db.rawQuery('''
      SELECT t.trip_id, t.shape_id, COUNT(st.id) as cnt
      FROM trips t
      JOIN stop_times st ON t.trip_id = st.trip_id
      WHERE t.route_id = ? AND t.direction_id = ?
        AND t.shape_id IS NOT NULL AND t.shape_id != ''
      GROUP BY t.trip_id
      ORDER BY cnt DESC
      LIMIT 1
    ''', [routeId, direction]);

    if (tripRows.isEmpty) {
      // direction bulunamazsa herhangi bir direction'ı dene
      final fallback = await _db.rawQuery('''
        SELECT t.trip_id, t.shape_id, COUNT(st.id) as cnt
        FROM trips t
        JOIN stop_times st ON t.trip_id = st.trip_id
        WHERE t.route_id = ?
          AND t.shape_id IS NOT NULL AND t.shape_id != ''
        GROUP BY t.trip_id
        ORDER BY cnt DESC
        LIMIT 1
      ''', [routeId]);
      if (fallback.isEmpty) return [];
      final shapeId = fallback.first['shape_id'] as String;
      return getShape(shapeId);
    }

    final shapeId = tripRows.first['shape_id'] as String;
    return getShape(shapeId);
  }

  // ==================== YAKLAŞAN SEFERLER ====================

  Future<List<String>> getUpcomingArrivals(
    String stopId, {
    String? routeId,
    int limit = 10,
  }) async {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    final todayCol = _todayCol();
    final todayStr = _todayStr();

    final validServices = await _getValidServiceIds(todayCol, todayStr);
    if (validServices.isEmpty) {
      debugPrint('⚠️ Bugün için geçerli servis bulunamadı');
    }

    final routeFilter = routeId != null ? 'AND t.route_id = ?' : '';
    final serviceFilter = validServices.isNotEmpty
        ? 'AND t.service_id IN (${validServices.map((_) => '?').join(',')})'
        : '';

    final args = [
      stopId,
      if (validServices.isNotEmpty) ...validServices,
      if (routeId != null) routeId,
    ];

    final rows = await _db.rawQuery('''
      SELECT t.trip_id, t.route_id, t.service_id, t.trip_headsign,
             st.arrival_time, st.departure_time, st.stop_sequence
      FROM stop_times st
      JOIN trips t ON st.trip_id = t.trip_id
      WHERE st.stop_id = ?
        $serviceFilter
        $routeFilter
      ORDER BY st.departure_time ASC
    ''', args);

    final departures = <int>{};

    for (final row in rows) {
      final tripId = row['trip_id'] as String;
      final depStr =
          (row['departure_time'] ?? row['arrival_time'])?.toString() ?? '';
      final headsign = row['trip_headsign']?.toString() ?? '';

      final freqs = await _db
          .query('frequencies', where: 'trip_id = ?', whereArgs: [tripId]);

      if (freqs.isNotEmpty) {
        for (final f in freqs) {
          final startMin = _toMinutes(f['start_time'] as String?);
          final endMin = _toMinutes(f['end_time'] as String?);
          final headway = (f['headway_secs'] as int?) ?? 0;
          if (startMin == null || endMin == null || headway <= 0) continue;
          final headwayMin = headway ~/ 60;
          if (headwayMin <= 0) continue;
          var t = startMin;
          while (t <= endMin) {
            if (t >= currentMinutes) departures.add(t);
            t += headwayMin;
          }
        }
      } else if (depStr.isNotEmpty && depStr != '00:00:00') {
        final min = _toMinutes(depStr);
        if (min != null && min >= currentMinutes) departures.add(min);
      } else {
        final extracted = _extractTimeFromHeadsign(headsign);
        if (extracted != null && extracted >= currentMinutes) {
          departures.add(extracted);
        }
      }
    }

    if (departures.isEmpty) {
      debugPrint('⚠️ Service bypass: tüm trip\'ler taranıyor');
      final bypassRows = await _db.rawQuery('''
        SELECT st.departure_time, st.arrival_time, t.trip_id, t.trip_headsign
        FROM stop_times st
        JOIN trips t ON st.trip_id = t.trip_id
        WHERE st.stop_id = ?
          ${routeId != null ? 'AND t.route_id = ?' : ''}
        ORDER BY st.departure_time ASC
      ''', [stopId, if (routeId != null) routeId]);

      for (final row in bypassRows) {
        final depStr =
            (row['departure_time'] ?? row['arrival_time'])?.toString() ?? '';
        final headsign = row['trip_headsign']?.toString() ?? '';

        if (depStr.isNotEmpty && depStr != '00:00:00') {
          final min = _toMinutes(depStr);
          if (min != null && min >= currentMinutes) departures.add(min);
        } else {
          final extracted = _extractTimeFromHeadsign(headsign);
          if (extracted != null && extracted >= currentMinutes) {
            departures.add(extracted);
          }
        }
      }
    }

    final sorted = departures.toList()..sort();
    return sorted.take(limit).map(_fromMinutes).toList();
  }

  int? _extractTimeFromHeadsign(String headsign) {
    if (headsign.isEmpty) return null;
    final match = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(headsign);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (h == null || m == null || h > 23 || m > 59) return null;
    return h * 60 + m;
  }

  Future<List<String>> _getValidServiceIds(
      String todayCol, String todayStr) async {
    final calRows = await _db.rawQuery('''
      SELECT service_id FROM calendar
      WHERE $todayCol = 1
        AND ? BETWEEN start_date AND end_date
    ''', [todayStr]);

    final serviceIds = calRows.map((r) => r['service_id'] as String).toSet();

    final excRows = await _db
        .query('calendar_dates', where: 'date = ?', whereArgs: [todayStr]);
    for (final row in excRows) {
      final sid = row['service_id'] as String;
      final type = row['exception_type'] as int;
      if (type == 1) serviceIds.add(sid);
      if (type == 2) serviceIds.remove(sid);
    }

    return serviceIds.toList();
  }

  // ==================== ROTA PLANLAMA ====================

  Future<List<Map<String, dynamic>>> findDirectRoutes(
      String fromStopId, String toStopId) async {
    return await _db.rawQuery('''
      SELECT DISTINCT r.*
      FROM routes r
      JOIN trips t ON r.route_id = t.route_id
      WHERE r.is_active = 1
        AND EXISTS (
          SELECT 1 FROM stop_times s1
          JOIN stop_times s2 ON s1.trip_id = s2.trip_id
          WHERE s1.stop_id = ?
            AND s2.stop_id = ?
            AND s1.stop_sequence < s2.stop_sequence
            AND s1.trip_id = t.trip_id
        )
      ORDER BY CAST(r.route_short_name AS INTEGER), r.route_short_name
    ''', [fromStopId, toStopId]);
  }

  Future<List<Map<String, dynamic>>> planRoutes({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    double walkRadius = 800,
  }) async {
    final boardingStops =
        await getNearbyStops(fromLat, fromLon, radiusMeters: walkRadius);
    final alightingStops =
        await getNearbyStops(toLat, toLon, radiusMeters: walkRadius);

    if (boardingStops.isEmpty || alightingStops.isEmpty) return [];

    final results = <String, Map<String, dynamic>>{};

    for (final bStop in boardingStops.take(15)) {
      for (final aStop in alightingStops.take(15)) {
        if (bStop['stop_id'] == aStop['stop_id']) continue;

        final routes = await findDirectRoutes(
          bStop['stop_id'] as String,
          aStop['stop_id'] as String,
        );

        for (final route in routes) {
          final key = route['route_id'] as String;
          if (results.containsKey(key)) continue;

          final upcoming = await getUpcomingArrivals(
            bStop['stop_id'] as String,
            routeId: key,
            limit: 3,
          );

          results[key] = {
            'route': route,
            'boarding_stop': bStop,
            'alighting_stop': aStop,
            'walk_to_m': bStop['distance_m'],
            'walk_from_m': aStop['distance_m'],
            'next_departures': upcoming,
            'is_operating': upcoming.isNotEmpty,
          };
        }
      }
    }

    final list = results.values.toList();
    list.sort((a, b) {
      final aOp = (a['is_operating'] as bool) ? 0 : 1;
      final bOp = (b['is_operating'] as bool) ? 0 : 1;
      if (aOp != bOp) return aOp.compareTo(bOp);
      final aW = (a['walk_to_m'] as double) + (a['walk_from_m'] as double);
      final bW = (b['walk_to_m'] as double) + (b['walk_from_m'] as double);
      return aW.compareTo(bW);
    });

    return list.take(10).toList();
  }

  // ==================== ÜCRET ====================

  Future<List<Map<String, dynamic>>> getFareProductsForNetwork(
      String networkId) async {
    return await _db.rawQuery('''
      SELECT fp.*, rc.rider_category_name, fm.fare_media_name
      FROM fare_leg_rules flr
      JOIN fare_products fp ON flr.fare_product_id = fp.fare_product_id
      LEFT JOIN rider_categories rc ON fp.rider_category_id = rc.rider_category_id
      LEFT JOIN fare_media fm ON fp.fare_media_id = fm.fare_media_id
      WHERE flr.network_id = ?
      ORDER BY fp.amount ASC
    ''', [networkId]);
  }

  Future<double?> getDefaultFareForRoute(String routeId) async {
    final rows = await _db.rawQuery('''
      SELECT fp.amount
      FROM route_networks rn
      JOIN fare_leg_rules flr ON rn.network_id = flr.network_id
      JOIN fare_products fp ON flr.fare_product_id = fp.fare_product_id
      JOIN rider_categories rc ON fp.rider_category_id = rc.rider_category_id
      WHERE rn.route_id = ? AND rc.is_default_fare_category = 1
      ORDER BY flr.rule_priority DESC
      LIMIT 1
    ''', [routeId]);

    if (rows.isEmpty) return null;
    return (rows.first['amount'] as num?)?.toDouble();
  }

  // ==================== ZAMAN YARDIMCILARI ====================

  String _todayCol() {
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

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }

  int? _toMinutes(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  String _fromMinutes(int minutes) {
    final m = minutes % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  // ==================== MESAFE ====================

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
