import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:csv/csv.dart';

import 'city_database_manager.dart';

/// GTFS Import Servisi
///
/// Her şehrin assets/gtfs/<city>/ klasöründeki .txt dosyalarını
/// okuyup ilgili şehrin SQLite veritabanına yükler.
///
/// Kullanım:
///   final importer = GtfsImporter(SupportedCity.cyprus);
///   await importer.importAll();
class GtfsImporter {
  final SupportedCity city;

  GtfsImporter(this.city);

  Database get _db => CityDatabaseManager.instance.database;
  String get _base => city.assetsPath;

  // ==================== ANA METOD ====================

  /// Tüm GTFS dosyalarını sırayla yükler.
  /// Zaten yüklüyse atlar (stops count > 0 kontrolü).
  Future<void> importAll({bool forceReload = false}) async {
    final db = _db;

    if (!forceReload) {
      final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM stops')) ??
          0;
      if (count > 0) {
        debugPrint('✅ ${city.displayName} verisi zaten yüklü ($count durak)');
        await _checkAndLoadMissingTables();
        return;
      }
    }

    debugPrint('📥 ${city.displayName} GTFS yükleniyor...');

    // Sıra önemli: bağımlılıklar önce yüklenmeli
    await _importAgency();
    await _importStops();
    await _importRoutes();
    await _importTrips();
    await _importStopTimes(); // büyük dosya — batch ile
    await _importShapes(); // büyük dosya — batch ile
    await _importCalendar();
    await _importCalendarDates();
    await _importFrequencies();
    await _importNetworks();
    await _importAreas();
    await _importStopAreas();
    await _importRouteNetworks();
    await _importTransfers();
    await _importFareMedia();
    await _importRiderCategories();
    await _importFareProducts();
    await _importFareLegRules();
    await _importFareTransferRules();
    await _importFeedInfo();
    await _importTimeframes();
    await _importPathways();
    await _importLevels();
    await _importLocationGroups();
    await _importLocationGroupStops();

    await _verifyImport();
    debugPrint('✅ ${city.displayName} GTFS yükleme tamamlandı');
  }

  /// Eksik tabloları kontrol edip yükler (kısmi import tamamlama)
  Future<void> _checkAndLoadMissingTables() async {
    final db = _db;
    Future<bool> isEmpty(String table) async {
      final c = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
          0;
      return c == 0;
    }

    if (await isEmpty('calendar')) await _importCalendar();
    if (await isEmpty('frequencies')) await _importFrequencies();
    if (await isEmpty('fare_products')) await _importFareProducts();
    if (await isEmpty('fare_leg_rules')) await _importFareLegRules();
    if (await isEmpty('networks')) await _importNetworks();
    if (await isEmpty('areas')) await _importAreas();
  }

  // ==================== CSV YARDIMCILARI ====================

  /// Asset dosyasını yükler. Bulunamazsa null döner (opsiyonel dosyalar için).
  Future<String?> _loadAsset(String filename) async {
    try {
      return await rootBundle.loadString('$_base/$filename');
    } catch (_) {
      debugPrint('⚠️ $filename bulunamadı, atlanıyor');
      return null;
    }
  }

  /// CSV string → satır listesi. İlk satır header.
  List<List<dynamic>> _parseCsv(String csv) {
    return const CsvToListConverter(
      fieldDelimiter: ',',
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csv);
  }

  /// Header satırından kolon adı → indeks map'i oluşturur.
  /// BOM karakterini ve whitespace'i temizler.
  Map<String, int> _headers(List<dynamic> row) {
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final key = row[i]
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll('\uFEFF', ''); // UTF-8 BOM
      map[key] = i;
    }
    return map;
  }

  /// Satırdan değer alır. Yoksa veya boşsa '' döner.
  String _val(List<dynamic> row, Map<String, int> headers, String key) {
    final idx = headers[key.toLowerCase()];
    if (idx == null || idx >= row.length) return '';
    return row[idx]?.toString().trim() ?? '';
  }

  /// String → int, başarısız olursa null
  int? _int(String v) => v.isEmpty ? null : int.tryParse(v);

  /// String → double, başarısız olursa null
  double? _dbl(String v) => v.isEmpty ? null : double.tryParse(v);

  /// is_active alanını çözümler (bool veya JSON string olabilir)
  int _parseIsActive(String raw) {
    final lower = raw.toLowerCase();
    if (lower.isEmpty || lower == '1' || lower == 'true') return 1;
    if (lower == '0' || lower == 'false') return 0;
    if (lower.contains('"active":true')) return 1;
    if (lower.contains('"active":false')) return 0;
    return 1; // varsayılan aktif
  }

  // ==================== IMPORT FONKSİYONLARI ====================

  Future<void> _importAgency() async {
    final csv = await _loadAsset('agency.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'agency_id');
      if (id.isEmpty) continue;

      batch.insert(
          'agency',
          {
            'agency_id': id,
            'agency_name': _val(r, h, 'agency_name'),
            'agency_url': _val(r, h, 'agency_url'),
            'agency_timezone': _val(r, h, 'agency_timezone'),
            'agency_lang': _val(r, h, 'agency_lang'),
            'agency_phone': _val(r, h, 'agency_phone'),
            'agency_fare_url': _val(r, h, 'agency_fare_url'),
            'agency_email': _val(r, h, 'agency_email'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ agency: $count');
  }

  Future<void> _importStops() async {
    final csv = await _loadAsset('stops.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'stop_id');
      final lat = _dbl(_val(r, h, 'stop_lat'));
      final lon = _dbl(_val(r, h, 'stop_lon'));
      if (id.isEmpty || lat == null || lon == null) continue;

      batch.insert(
          'stops',
          {
            'stop_id': id,
            'stop_code': _val(r, h, 'stop_code'),
            'stop_name': _val(r, h, 'stop_name'),
            'stop_desc': _val(r, h, 'stop_desc'),
            'stop_lat': lat,
            'stop_lon': lon,
            'zone_id': _val(r, h, 'zone_id'),
            'stop_url': _val(r, h, 'stop_url'),
            'location_type': _int(_val(r, h, 'location_type')),
            'parent_station': _val(r, h, 'parent_station'),
            'stop_timezone': _val(r, h, 'stop_timezone'),
            'wheelchair_boarding': _int(_val(r, h, 'wheelchair_boarding')),
            'level_id': _val(r, h, 'level_id'),
            'platform_code': _val(r, h, 'platform_code'),
            'direction': _val(r, h, 'direction'),
            'position': _val(r, h, 'position'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ stops: $count');
  }

  Future<void> _importRoutes() async {
    final csv = await _loadAsset('routes.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'route_id');
      if (id.isEmpty) continue;

      batch.insert(
          'routes',
          {
            'route_id': id,
            'agency_id': _val(r, h, 'agency_id'),
            'route_short_name': _val(r, h, 'route_short_name'),
            'route_long_name': _val(r, h, 'route_long_name'),
            'route_desc': _val(r, h, 'route_desc'),
            'route_type': _int(_val(r, h, 'route_type')) ?? 3,
            'route_url': _val(r, h, 'route_url'),
            'route_color': _val(r, h, 'route_color'),
            'route_text_color': _val(r, h, 'route_text_color'),
            'route_sort_order': _int(_val(r, h, 'route_sort_order')) ?? 0,
            'continuous_pickup': _int(_val(r, h, 'continuous_pickup')),
            'continuous_drop_off': _int(_val(r, h, 'continuous_drop_off')),
            'network_id': _val(r, h, 'network_id'),
            'is_active': _parseIsActive(_val(r, h, 'is_active')),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ routes: $count');
  }

  Future<void> _importTrips() async {
    final csv = await _loadAsset('trips.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'trip_id');
      if (id.isEmpty) continue;

      batch.insert(
          'trips',
          {
            'trip_id': id,
            'route_id': _val(r, h, 'route_id'),
            'service_id': _val(r, h, 'service_id'),
            'trip_headsign': _val(r, h, 'trip_headsign'),
            'trip_short_name': _val(r, h, 'trip_short_name'),
            'direction_id': _int(_val(r, h, 'direction_id')),
            'block_id': _val(r, h, 'block_id'),
            'shape_id': _val(r, h, 'shape_id'),
            'wheelchair_accessible':
                _int(_val(r, h, 'wheelchair_accessible')) ?? 0,
            'bikes_allowed': _int(_val(r, h, 'bikes_allowed')) ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ trips: $count');
  }

  /// stop_times büyük olabilir — 5000'lik batch'ler ile yükle
  Future<void> _importStopTimes() async {
    final csv = await _loadAsset('stop_times.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    int count = 0;
    int batchCount = 0;
    var batch = _db.batch();

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final tripId = _val(r, h, 'trip_id');
      final stopId = _val(r, h, 'stop_id');
      if (tripId.isEmpty || stopId.isEmpty) continue;

      batch.insert('stop_times', {
        'trip_id': tripId,
        'arrival_time': _val(r, h, 'arrival_time'),
        'departure_time': _val(r, h, 'departure_time'),
        'stop_id': stopId,
        'stop_sequence': _int(_val(r, h, 'stop_sequence')) ?? 0,
        'stop_headsign': _val(r, h, 'stop_headsign'),
        'pickup_type': _int(_val(r, h, 'pickup_type')) ?? 0,
        'drop_off_type': _int(_val(r, h, 'drop_off_type')) ?? 0,
        'continuous_pickup': _int(_val(r, h, 'continuous_pickup')),
        'continuous_drop_off': _int(_val(r, h, 'continuous_drop_off')),
        'shape_dist_traveled': _dbl(_val(r, h, 'shape_dist_traveled')),
        'timepoint': _int(_val(r, h, 'timepoint')) ?? 1,
      });

      count++;
      batchCount++;

      if (batchCount >= 5000) {
        await batch.commit(noResult: true);
        batch = _db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) await batch.commit(noResult: true);
    debugPrint('✅ stop_times: $count');
  }

  /// shapes büyük olabilir — 5000'lik batch'ler
  Future<void> _importShapes() async {
    final csv = await _loadAsset('shapes.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    int count = 0;
    int batchCount = 0;
    var batch = _db.batch();

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final shapeId = _val(r, h, 'shape_id');
      final lat = _dbl(_val(r, h, 'shape_pt_lat'));
      final lon = _dbl(_val(r, h, 'shape_pt_lon'));
      final seq = _int(_val(r, h, 'shape_pt_sequence'));
      if (shapeId.isEmpty || lat == null || lon == null) continue;

      batch.insert('shapes', {
        'shape_id': shapeId,
        'shape_pt_lat': lat,
        'shape_pt_lon': lon,
        'shape_pt_sequence': seq ?? 0,
        'shape_dist_traveled': _dbl(_val(r, h, 'shape_dist_traveled')),
      });

      count++;
      batchCount++;

      if (batchCount >= 5000) {
        await batch.commit(noResult: true);
        batch = _db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) await batch.commit(noResult: true);
    debugPrint('✅ shapes: $count');
  }

  Future<void> _importCalendar() async {
    final csv = await _loadAsset('calendar.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'service_id');
      if (id.isEmpty) continue;

      batch.insert(
          'calendar',
          {
            'service_id': id,
            'monday': _int(_val(r, h, 'monday')) ?? 0,
            'tuesday': _int(_val(r, h, 'tuesday')) ?? 0,
            'wednesday': _int(_val(r, h, 'wednesday')) ?? 0,
            'thursday': _int(_val(r, h, 'thursday')) ?? 0,
            'friday': _int(_val(r, h, 'friday')) ?? 0,
            'saturday': _int(_val(r, h, 'saturday')) ?? 0,
            'sunday': _int(_val(r, h, 'sunday')) ?? 0,
            'start_date': _val(r, h, 'start_date'),
            'end_date': _val(r, h, 'end_date'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ calendar: $count');
  }

  Future<void> _importCalendarDates() async {
    final csv = await _loadAsset('calendar_dates.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'service_id');
      if (id.isEmpty) continue;

      batch.insert('calendar_dates', {
        'service_id': id,
        'date': _val(r, h, 'date'),
        'exception_type': _int(_val(r, h, 'exception_type')) ?? 1,
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ calendar_dates: $count');
  }

  Future<void> _importFrequencies() async {
    final csv = await _loadAsset('frequencies.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final tripId = _val(r, h, 'trip_id');
      if (tripId.isEmpty) continue;

      batch.insert('frequencies', {
        'trip_id': tripId,
        'start_time': _val(r, h, 'start_time'),
        'end_time': _val(r, h, 'end_time'),
        'headway_secs': _int(_val(r, h, 'headway_secs')) ?? 0,
        'exact_times': _int(_val(r, h, 'exact_times')) ?? 0,
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ frequencies: $count');
  }

  Future<void> _importNetworks() async {
    final csv = await _loadAsset('networks.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'network_id');
      if (id.isEmpty) continue;
      batch.insert(
          'networks',
          {
            'network_id': id,
            'network_name': _val(r, h, 'network_name'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ networks: $count');
  }

  Future<void> _importAreas() async {
    final csv = await _loadAsset('areas.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'area_id');
      if (id.isEmpty) continue;
      batch.insert(
          'areas',
          {
            'area_id': id,
            'area_name': _val(r, h, 'area_name'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ areas: $count');
  }

  Future<void> _importStopAreas() async {
    final csv = await _loadAsset('stop_areas.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final areaId = _val(r, h, 'area_id');
      final stopId = _val(r, h, 'stop_id');
      if (areaId.isEmpty || stopId.isEmpty) continue;
      batch.insert('stop_areas', {'area_id': areaId, 'stop_id': stopId});
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ stop_areas: $count');
  }

  Future<void> _importRouteNetworks() async {
    final csv = await _loadAsset('route_networks.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final netId = _val(r, h, 'network_id');
      final routeId = _val(r, h, 'route_id');
      if (netId.isEmpty || routeId.isEmpty) continue;
      batch
          .insert('route_networks', {'network_id': netId, 'route_id': routeId});
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ route_networks: $count');
  }

  Future<void> _importTransfers() async {
    final csv = await _loadAsset('transfers.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      batch.insert('transfers', {
        'from_stop_id': _val(r, h, 'from_stop_id'),
        'to_stop_id': _val(r, h, 'to_stop_id'),
        'from_route_id': _val(r, h, 'from_route_id'),
        'to_route_id': _val(r, h, 'to_route_id'),
        'from_trip_id': _val(r, h, 'from_trip_id'),
        'to_trip_id': _val(r, h, 'to_trip_id'),
        'transfer_type': _int(_val(r, h, 'transfer_type')) ?? 0,
        'min_transfer_time': _int(_val(r, h, 'min_transfer_time')),
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ transfers: $count');
  }

  Future<void> _importFareMedia() async {
    final csv = await _loadAsset('fare_media.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'fare_media_id');
      if (id.isEmpty) continue;
      batch.insert(
          'fare_media',
          {
            'fare_media_id': id,
            'fare_media_name': _val(r, h, 'fare_media_name'),
            'fare_media_type': _int(_val(r, h, 'fare_media_type')) ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ fare_media: $count');
  }

  Future<void> _importRiderCategories() async {
    final csv = await _loadAsset('rider_categories.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'rider_category_id');
      if (id.isEmpty) continue;
      batch.insert(
          'rider_categories',
          {
            'rider_category_id': id,
            'rider_category_name': _val(r, h, 'rider_category_name'),
            'is_default_fare_category':
                _int(_val(r, h, 'is_default_fare_category')) ?? 0,
            'eligibility_url': _val(r, h, 'eligibility_url'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ rider_categories: $count');
  }

  /// fare_products: fare_product_id PRIMARY KEY değil — aynı id farklı
  /// rider_category için tekrarlanabilir (AUTOINCREMENT id kullanılıyor)
  Future<void> _importFareProducts() async {
    final csv = await _loadAsset('fare_products.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'fare_product_id').trim();
      if (id.isEmpty) continue;
      batch.insert('fare_products', {
        'fare_product_id': id,
        'fare_product_name': _val(r, h, 'fare_product_name'),
        'amount': _dbl(_val(r, h, 'amount')),
        'currency': _val(r, h, 'currency'),
        'fare_media_id': _val(r, h, 'fare_media_id'),
        'rider_category_id': _val(r, h, 'rider_category_id'),
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ fare_products: $count');
  }

  Future<void> _importFareLegRules() async {
    final csv = await _loadAsset('fare_leg_rules.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final fareId = _val(r, h, 'fare_product_id').trim();
      if (fareId.isEmpty) continue;
      batch.insert('fare_leg_rules', {
        'leg_group_id': _val(r, h, 'leg_group_id'),
        'network_id': _val(r, h, 'network_id'),
        'from_area_id': _val(r, h, 'from_area_id'),
        'to_area_id': _val(r, h, 'to_area_id'),
        'from_timeframe_group_id': _val(r, h, 'from_timeframe_group_id'),
        'to_timeframe_group_id': _val(r, h, 'to_timeframe_group_id'),
        'fare_product_id': fareId,
        'rule_priority': _int(_val(r, h, 'rule_priority')) ?? 0,
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ fare_leg_rules: $count');
  }

  Future<void> _importFareTransferRules() async {
    final csv = await _loadAsset('fare_transfer_rules.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      batch.insert('fare_transfer_rules', {
        'from_leg_group_id': _val(r, h, 'from_leg_group_id'),
        'to_leg_group_id': _val(r, h, 'to_leg_group_id'),
        'transfer_count': _int(_val(r, h, 'transfer_count')),
        'duration_limit': _int(_val(r, h, 'duration_limit')),
        'duration_limit_type': _int(_val(r, h, 'duration_limit_type')),
        'fare_transfer_type': _int(_val(r, h, 'fare_transfer_type')),
        'fare_product_id': _val(r, h, 'fare_product_id'),
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ fare_transfer_rules: $count');
  }

  Future<void> _importFeedInfo() async {
    final csv = await _loadAsset('feed_info.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      batch.insert('feed_info', {
        'feed_publisher_name': _val(r, h, 'feed_publisher_name'),
        'feed_publisher_url': _val(r, h, 'feed_publisher_url'),
        'feed_lang': _val(r, h, 'feed_lang'),
        'feed_start_date': _val(r, h, 'feed_start_date'),
        'feed_end_date': _val(r, h, 'feed_end_date'),
        'feed_version': _val(r, h, 'feed_version'),
        'feed_contact_email': _val(r, h, 'feed_contact_email'),
        'feed_contact_url': _val(r, h, 'feed_contact_url'),
      });
    }

    await batch.commit(noResult: true);
    debugPrint('✅ feed_info yüklendi');
  }

  Future<void> _importTimeframes() async {
    final csv = await _loadAsset('timeframes.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final gid = _val(r, h, 'timeframe_group_id');
      if (gid.isEmpty) continue;
      batch.insert('timeframes', {
        'timeframe_group_id': gid,
        'start_time': _val(r, h, 'start_time'),
        'end_time': _val(r, h, 'end_time'),
        'service_id': _val(r, h, 'service_id'),
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ timeframes: $count');
  }

  Future<void> _importPathways() async {
    final csv = await _loadAsset('pathways.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'pathway_id');
      if (id.isEmpty) continue;
      batch.insert(
          'pathways',
          {
            'pathway_id': id,
            'from_stop_id': _val(r, h, 'from_stop_id'),
            'to_stop_id': _val(r, h, 'to_stop_id'),
            'pathway_mode': _int(_val(r, h, 'pathway_mode')) ?? 1,
            'is_bidirectional': _int(_val(r, h, 'is_bidirectional')) ?? 0,
            'length': _dbl(_val(r, h, 'length')),
            'traversal_time': _int(_val(r, h, 'traversal_time')),
            'stair_count': _int(_val(r, h, 'stair_count')),
            'max_slope': _dbl(_val(r, h, 'max_slope')),
            'min_width': _dbl(_val(r, h, 'min_width')),
            'signposted_as': _val(r, h, 'signposted_as'),
            'reversed_signposted_as': _val(r, h, 'reversed_signposted_as'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ pathways: $count');
  }

  Future<void> _importLevels() async {
    final csv = await _loadAsset('levels.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'level_id');
      if (id.isEmpty) continue;
      batch.insert(
          'levels',
          {
            'level_id': id,
            'level_index': _dbl(_val(r, h, 'level_index')) ?? 0.0,
            'level_name': _val(r, h, 'level_name'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ levels: $count');
  }

  Future<void> _importLocationGroups() async {
    final csv = await _loadAsset('location_groups.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final id = _val(r, h, 'location_group_id');
      if (id.isEmpty) continue;
      batch.insert(
          'location_groups',
          {
            'location_group_id': id,
            'location_group_name': _val(r, h, 'location_group_name'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ location_groups: $count');
  }

  Future<void> _importLocationGroupStops() async {
    final csv = await _loadAsset('location_group_stops.txt');
    if (csv == null) return;
    final rows = _parseCsv(csv);
    if (rows.length < 2) return;

    final h = _headers(rows[0]);
    final batch = _db.batch();
    int count = 0;

    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final gid = _val(r, h, 'location_group_id');
      final sid = _val(r, h, 'stop_id');
      if (gid.isEmpty || sid.isEmpty) continue;
      batch.insert('location_group_stops', {
        'location_group_id': gid,
        'stop_id': sid,
      });
      count++;
    }

    await batch.commit(noResult: true);
    debugPrint('✅ location_group_stops: $count');
  }

  // ==================== DOĞRULAMA ====================

  Future<void> _verifyImport() async {
    final db = _db;
    Future<int> count(String t) async =>
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ??
        0;

    debugPrint('📊 ${city.displayName} Import Özeti:');
    debugPrint('   stops:        ${await count('stops')}');
    debugPrint('   routes:       ${await count('routes')}');
    debugPrint('   trips:        ${await count('trips')}');
    debugPrint('   stop_times:   ${await count('stop_times')}');
    debugPrint('   shapes:       ${await count('shapes')}');
    debugPrint('   calendar:     ${await count('calendar')}');
    debugPrint('   fare_products:${await count('fare_products')}');
    debugPrint('   networks:     ${await count('networks')}');
  }
}
