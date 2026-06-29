import 'api_config.dart';

/// Uygulama sabitleri
class AppConstants {
  // Uygulama bilgileri
  static const String appName = 'Manisa Ulaşım';
  static const String appVersion = '1.0.0';
  
  // GTFS veri dosyaları
  static const String gtfsAgency = 'assets/data/agency.txt';
  static const String gtfsStops = 'assets/data/stops.txt';
  static const String gtfsRoutes = 'assets/data/routes.txt';
  static const String gtfsTrips = 'assets/data/trips.txt';
  static const String gtfsStopTimes = 'assets/data/stop_times.txt';
  static const String gtfsCalendar = 'assets/data/calendar.txt';
  static const String gtfsShapes = 'assets/data/shapes.txt';
  
  // Harita ayarları
  static const double defaultLatitude = 38.6191; // Manisa merkez
  static const double defaultLongitude = 27.4289;
  static const double defaultZoom = 14.0;
  static const double minZoom = 8.0;
  static const double maxZoom = 18.0;
  
  // OpenStreetMap tile URL (set via OSM_TILE_URL in .env)
  static String get osmTileUrl => ApiConfig.osmTileUrl;
  
  // Konum ayarları
  static const int locationUpdateIntervalMs = 5000; // 5 saniye
  static const double nearbyStopsRadiusMeters = 500.0; // 500 metre
  static const double maxSearchRadiusMeters = 2000.0; // 2 km
  
  // Zaman aşımları
  static const int apiTimeoutSeconds = 30;
  static const int locationTimeoutSeconds = 15;
  
  // Erişilebilirlik
  static const double minTouchTargetSize = 48.0; // Material Design önerisi
  static const double minFontSize = 14.0;
  static const double largeFontSize = 18.0;
  
  // Animasyon süreleri
  static const int shortAnimationMs = 200;
  static const int mediumAnimationMs = 400;
  static const int longAnimationMs = 600;
  
  // Veritabanı
  static const String databaseName = 'manisa_ulasim.db';
  static const int databaseVersion = 1;
  
  // Mesafeler (metre)
  static const Map<String, double> walkingRadiusOptions = {
    'Yakın (250m)': 250,
    'Normal (500m)': 500,
    'Uzak (1km)': 1000,
  };
}

/// Hat türleri (GTFS route_type)
class RouteTypes {
  static const int tram = 0;       // Tramvay
  static const int subway = 1;     // Metro
  static const int rail = 2;       // Tren
  static const int bus = 3;        // Otobüs
  static const int ferry = 4;      // Feribot
  static const int cableTram = 5;  // Teleferik tramvay
  static const int aerial = 6;     // Teleferik
  static const int funicular = 7;  // Füniküler
  static const int trolleybus = 11; // Troleybüs
  static const int monorail = 12;  // Monoray
  
  static String getName(int type) {
    switch (type) {
      case tram: return 'Tramvay';
      case subway: return 'Metro';
      case rail: return 'Tren';
      case bus: return 'Otobüs';
      case ferry: return 'Feribot';
      case cableTram: return 'Teleferik Tramvay';
      case aerial: return 'Teleferik';
      case funicular: return 'Füniküler';
      case trolleybus: return 'Troleybüs';
      case monorail: return 'Monoray';
      default: return 'Bilinmiyor';
    }
  }
  
  static String getIcon(int type) {
    switch (type) {
      case tram: return '🚊';
      case subway: return '🚇';
      case rail: return '🚆';
      case bus: return '🚌';
      case ferry: return '⛴️';
      case cableTram: 
      case aerial: 
      case funicular: return '🚡';
      case trolleybus: return '🚎';
      case monorail: return '🚝';
      default: return '🚍';
    }
  }
}

/// Haftanın günleri
class WeekDays {
  static const int monday = 1;
  static const int tuesday = 2;
  static const int wednesday = 3;
  static const int thursday = 4;
  static const int friday = 5;
  static const int saturday = 6;
  static const int sunday = 7;
  
  static String getName(int day) {
    switch (day) {
      case monday: return 'Pazartesi';
      case tuesday: return 'Salı';
      case wednesday: return 'Çarşamba';
      case thursday: return 'Perşembe';
      case friday: return 'Cuma';
      case saturday: return 'Cumartesi';
      case sunday: return 'Pazar';
      default: return '';
    }
  }
}
