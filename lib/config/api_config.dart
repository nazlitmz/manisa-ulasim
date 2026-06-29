// lib/config/api_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // API Base URL - v1 endpoint (set via MANISA_API_BASE_URL in .env)
  static String get baseUrl => dotenv.env['MANISA_API_BASE_URL'] ?? '';

  // Bearer Token (set via MANISA_BEARER_TOKEN in .env)
  static String get bearerToken => dotenv.env['MANISA_BEARER_TOKEN'] ?? '';

  // Groq AI chat completions endpoint (set via GROQ_API_URL in .env)
  static String get groqApiUrl => dotenv.env['GROQ_API_URL'] ?? '';

  // OpenStreetMap tile server URL template (set via OSM_TILE_URL in .env)
  static String get osmTileUrl => dotenv.env['OSM_TILE_URL'] ?? '';

  // OSRM public routing server base URL (set via OSRM_BASE_URL in .env)
  static String get osrmBaseUrl => dotenv.env['OSRM_BASE_URL'] ?? '';

  // Google Maps directions deep-link base URL (set via GOOGLE_MAPS_DIRECTIONS_URL in .env)
  static String get googleMapsDirectionsUrl =>
      dotenv.env['GOOGLE_MAPS_DIRECTIONS_URL'] ?? '';

  // Google Maps search deep-link base URL (set via GOOGLE_MAPS_SEARCH_URL in .env)
  static String get googleMapsSearchUrl =>
      dotenv.env['GOOGLE_MAPS_SEARCH_URL'] ?? '';

  /// Doğru timezone'da timestamp oluştur
  static String getCorrectTimestamp() {
    // UTC timestamp
    final utcNow = DateTime.now().toUtc();

    // Eğer sunucu Türkiye saati kullanıyorsa (UTC+3)
    // final turkeyTz = tz.getLocation('Europe/Istanbul');
    // final turkeyNow = tz.TZDateTime.now(turkeyTz);
    // return turkeyNow.toIso8601String();

    // Şimdilik UTC kullan
    return utcNow.toIso8601String();
  }
}
