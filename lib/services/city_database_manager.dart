import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Desteklenen şehirler
enum SupportedCity {
  manisa,
  cyprus,
  izmir,
}

extension SupportedCityExtension on SupportedCity {
  String get dbFileName {
    switch (this) {
      case SupportedCity.manisa:
        return 'manisa.db';
      case SupportedCity.cyprus:
        return 'cyprus.db';
      case SupportedCity.izmir:
        return 'izmir.db';
    }
  }

  String get displayName {
    switch (this) {
      case SupportedCity.manisa:
        return 'Manisa';
      case SupportedCity.cyprus:
        return 'Kıbrıs';
      case SupportedCity.izmir:
        return 'İzmir';
    }
  }

  /// Her şehrin assets klasörü altındaki GTFS veri yolu
  String get assetsPath {
    switch (this) {
      case SupportedCity.manisa:
        return 'assets/gtfs/manisa';
      case SupportedCity.cyprus:
        return 'assets/gtfs/cyprus';
      case SupportedCity.izmir:
        return 'assets/gtfs/izmir';
    }
  }
}

/// Çok şehirli veritabanı yöneticisi — Singleton
///
/// Kullanım:
///   await CityDatabaseManager.instance.switchCity(SupportedCity.cyprus);
///   final db = CityDatabaseManager.instance.database;
class CityDatabaseManager {
  static final CityDatabaseManager instance = CityDatabaseManager._internal();
  CityDatabaseManager._internal();

  Database? _database;
  SupportedCity? _currentCity;

  Database get database {
    if (_database == null)
      throw StateError('Veritabanı henüz açılmadı. switchCity() çağırın.');
    return _database!;
  }

  SupportedCity? get currentCity => _currentCity;
  bool get isOpen => _database != null && _database!.isOpen;

  /// Şehri değiştir — mevcut DB'yi kapat, yenisini aç/oluştur
  Future<void> switchCity(SupportedCity city) async {
    if (_currentCity == city && isOpen) {
      debugPrint('✅ ${city.displayName} zaten açık');
      return;
    }

    await _closeCurrentDatabase();

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, city.dbFileName);

    debugPrint('🏙️ ${city.displayName} veritabanı açılıyor: $path');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => _createSchema(db, city),
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint(
            '🔄 ${city.displayName} DB güncelleniyor: v$oldVersion -> v$newVersion');
        await _dropAllTables(db);
        await _createSchema(db, city);
      },
    );

    _currentCity = city;
    debugPrint('✅ ${city.displayName} veritabanı açıldı');
  }

  Future<void> _closeCurrentDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      debugPrint('🔒 ${_currentCity?.displayName} veritabanı kapatıldı');
    }
    _database = null;
    _currentCity = null;
  }

  // ==================== SCHEMA OLUŞTURMA ====================

  Future<void> _createSchema(Database db, SupportedCity city) async {
    debugPrint('📊 ${city.displayName} tabloları oluşturuluyor...');

    // Temel GTFS tabloları (tüm şehirler)
    await _createCoreTables(db);

    // Gelişmiş GTFS tabloları (Cyprus gibi ek dosyaları olan şehirler için)
    await _createExtendedTables(db);

    // İndeksler
    await _createIndexes(db);

    debugPrint('✅ ${city.displayName} şeması hazır');
  }

  Future<void> _createCoreTables(Database db) async {
    // agency.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agency (
        agency_id   TEXT PRIMARY KEY NOT NULL,
        agency_name TEXT NOT NULL,
        agency_url  TEXT,
        agency_timezone TEXT NOT NULL,
        agency_lang TEXT,
        agency_phone TEXT,
        agency_fare_url TEXT,
        agency_email TEXT
      )
    ''');

    // stops.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stops (
        stop_id            TEXT PRIMARY KEY NOT NULL,
        stop_code          TEXT,
        stop_name          TEXT NOT NULL,
        stop_desc          TEXT,
        stop_lat           REAL NOT NULL,
        stop_lon           REAL NOT NULL,
        zone_id            TEXT,
        stop_url           TEXT,
        location_type      INTEGER DEFAULT 0,
        parent_station     TEXT,
        stop_timezone      TEXT,
        wheelchair_boarding INTEGER DEFAULT 0,
        level_id           TEXT,
        platform_code      TEXT,
        direction          TEXT,
        position           TEXT
      )
    ''');

    // routes.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS routes (
        route_id           TEXT PRIMARY KEY NOT NULL,
        agency_id          TEXT,
        route_short_name   TEXT,
        route_long_name    TEXT,
        route_desc         TEXT,
        route_type         INTEGER NOT NULL DEFAULT 3,
        route_url          TEXT,
        route_color        TEXT,
        route_text_color   TEXT,
        route_sort_order   INTEGER DEFAULT 0,
        continuous_pickup  INTEGER,
        continuous_drop_off INTEGER,
        network_id         TEXT,
        is_active          INTEGER DEFAULT 1
      )
    ''');

    // trips.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trips (
        trip_id              TEXT PRIMARY KEY NOT NULL,
        route_id             TEXT NOT NULL,
        service_id           TEXT,
        trip_headsign        TEXT,
        trip_short_name      TEXT,
        direction_id         INTEGER,
        block_id             TEXT,
        shape_id             TEXT,
        wheelchair_accessible INTEGER DEFAULT 0,
        bikes_allowed        INTEGER DEFAULT 0
      )
    ''');

    // stop_times.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stop_times (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id          TEXT NOT NULL,
        arrival_time     TEXT,
        departure_time   TEXT,
        stop_id          TEXT NOT NULL,
        stop_sequence    INTEGER NOT NULL,
        stop_headsign    TEXT,
        pickup_type      INTEGER DEFAULT 0,
        drop_off_type    INTEGER DEFAULT 0,
        continuous_pickup  INTEGER,
        continuous_drop_off INTEGER,
        shape_dist_traveled REAL,
        timepoint        INTEGER DEFAULT 1
      )
    ''');

    // calendar.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS calendar (
        service_id TEXT PRIMARY KEY NOT NULL,
        monday     INTEGER NOT NULL DEFAULT 0,
        tuesday    INTEGER NOT NULL DEFAULT 0,
        wednesday  INTEGER NOT NULL DEFAULT 0,
        thursday   INTEGER NOT NULL DEFAULT 0,
        friday     INTEGER NOT NULL DEFAULT 0,
        saturday   INTEGER NOT NULL DEFAULT 0,
        sunday     INTEGER NOT NULL DEFAULT 0,
        start_date TEXT NOT NULL,
        end_date   TEXT NOT NULL
      )
    ''');

    // calendar_dates.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS calendar_dates (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        service_id     TEXT NOT NULL,
        date           TEXT NOT NULL,
        exception_type INTEGER NOT NULL
      )
    ''');

    // shapes.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shapes (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        shape_id            TEXT NOT NULL,
        shape_pt_lat        REAL NOT NULL,
        shape_pt_lon        REAL NOT NULL,
        shape_pt_sequence   INTEGER NOT NULL,
        shape_dist_traveled REAL
      )
    ''');

    // frequencies.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS frequencies (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id      TEXT NOT NULL,
        start_time   TEXT NOT NULL,
        end_time     TEXT NOT NULL,
        headway_secs INTEGER NOT NULL,
        exact_times  INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _createExtendedTables(Database db) async {
    // networks.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS networks (
        network_id   TEXT PRIMARY KEY NOT NULL,
        network_name TEXT
      )
    ''');

    // areas.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS areas (
        area_id   TEXT PRIMARY KEY NOT NULL,
        area_name TEXT
      )
    ''');

    // stop_areas.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stop_areas (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        area_id TEXT NOT NULL,
        stop_id TEXT NOT NULL
      )
    ''');

    // route_networks.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS route_networks (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        network_id TEXT NOT NULL,
        route_id   TEXT NOT NULL
      )
    ''');

    // transfers.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transfers (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        from_stop_id        TEXT,
        to_stop_id          TEXT,
        from_route_id       TEXT,
        to_route_id         TEXT,
        from_trip_id        TEXT,
        to_trip_id          TEXT,
        transfer_type       INTEGER NOT NULL DEFAULT 0,
        min_transfer_time   INTEGER
      )
    ''');

    // fare_media.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fare_media (
        fare_media_id   TEXT PRIMARY KEY NOT NULL,
        fare_media_name TEXT,
        fare_media_type INTEGER NOT NULL
      )
    ''');

    // rider_categories.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rider_categories (
        rider_category_id   TEXT PRIMARY KEY NOT NULL,
        rider_category_name TEXT,
        is_default_fare_category INTEGER DEFAULT 0,
        eligibility_url     TEXT
      )
    ''');

    // fare_products.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fare_products (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        fare_product_id  TEXT NOT NULL,
        fare_product_name TEXT,
        amount           REAL,
        currency         TEXT,
        fare_media_id    TEXT,
        rider_category_id TEXT
      )
    ''');

    // fare_leg_rules.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fare_leg_rules (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        leg_group_id            TEXT,
        network_id              TEXT,
        from_area_id            TEXT,
        to_area_id              TEXT,
        from_timeframe_group_id TEXT,
        to_timeframe_group_id   TEXT,
        fare_product_id         TEXT NOT NULL,
        rule_priority           INTEGER DEFAULT 0
      )
    ''');

    // fare_transfer_rules.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fare_transfer_rules (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        from_leg_group_id       TEXT,
        to_leg_group_id         TEXT,
        transfer_count          INTEGER,
        duration_limit          INTEGER,
        duration_limit_type     INTEGER,
        fare_transfer_type      INTEGER,
        fare_product_id         TEXT
      )
    ''');

    // pathways.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pathways (
        pathway_id         TEXT PRIMARY KEY NOT NULL,
        from_stop_id       TEXT NOT NULL,
        to_stop_id         TEXT NOT NULL,
        pathway_mode       INTEGER NOT NULL,
        is_bidirectional   INTEGER NOT NULL,
        length             REAL,
        traversal_time     INTEGER,
        stair_count        INTEGER,
        max_slope          REAL,
        min_width          REAL,
        signposted_as      TEXT,
        reversed_signposted_as TEXT
      )
    ''');

    // levels.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS levels (
        level_id    TEXT PRIMARY KEY NOT NULL,
        level_index REAL NOT NULL,
        level_name  TEXT
      )
    ''');

    // feed_info.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feed_info (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_publisher_name  TEXT NOT NULL,
        feed_publisher_url   TEXT NOT NULL,
        feed_lang            TEXT NOT NULL,
        feed_start_date      TEXT,
        feed_end_date        TEXT,
        feed_version         TEXT,
        feed_contact_email   TEXT,
        feed_contact_url     TEXT
      )
    ''');

    // timeframes.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS timeframes (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        timeframe_group_id    TEXT NOT NULL,
        start_time            TEXT,
        end_time              TEXT,
        service_id            TEXT
      )
    ''');

    // location_groups.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS location_groups (
        location_group_id   TEXT PRIMARY KEY NOT NULL,
        location_group_name TEXT
      )
    ''');

    // location_group_stops.txt
    await db.execute('''
      CREATE TABLE IF NOT EXISTS location_group_stops (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        location_group_id TEXT NOT NULL,
        stop_id           TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    // stop_times — en kritik indeksler
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_st_stop_id  ON stop_times(stop_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_st_trip_id  ON stop_times(trip_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_st_combined ON stop_times(trip_id, stop_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_st_seq      ON stop_times(trip_id, stop_sequence)');

    // trips
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trips_route_id   ON trips(route_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trips_service_id ON trips(service_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trips_direction  ON trips(route_id, direction_id)');

    // stops
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stops_stop_id ON stops(stop_id)');

    // routes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_routes_short ON routes(route_short_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_routes_active ON routes(is_active)');

    // shapes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shapes_id  ON shapes(shape_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shapes_seq ON shapes(shape_id, shape_pt_sequence)');

    // calendar
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_calendar_service ON calendar(service_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cal_dates_service ON calendar_dates(service_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cal_dates_date    ON calendar_dates(date)');

    // frequencies
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_freq_trip ON frequencies(trip_id)');

    // fare
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_fare_products_id ON fare_products(fare_product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_fare_leg_network  ON fare_leg_rules(network_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stop_areas_area   ON stop_areas(area_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stop_areas_stop   ON stop_areas(stop_id)');

    debugPrint('✅ İndeksler oluşturuldu');
  }

  Future<void> _dropAllTables(Database db) async {
    final tables = [
      'agency',
      'stops',
      'routes',
      'trips',
      'stop_times',
      'calendar',
      'calendar_dates',
      'shapes',
      'frequencies',
      'networks',
      'areas',
      'stop_areas',
      'route_networks',
      'transfers',
      'fare_media',
      'rider_categories',
      'fare_products',
      'fare_leg_rules',
      'fare_transfer_rules',
      'pathways',
      'levels',
      'feed_info',
      'timeframes',
      'location_groups',
      'location_group_stops',
    ];
    for (final t in tables) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
  }

  Future<void> close() async {
    await _closeCurrentDatabase();
  }
}
