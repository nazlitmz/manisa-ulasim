import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_message_model.dart';
import '../config/api_config.dart';
import 'database_service.dart';
import '../config/popular_places_config.dart';
import '../services/city_detection_service.dart';
import '../services/city_database_manager.dart';
import '../services/kktc_intercity_service.dart';
import '../config/routes.dart';

// ══════════════════════════════════════════════════════════════════
// Popüler yerler — PopularPlacesConfig'den dinamik olarak alınır
// ══════════════════════════════════════════════════════════════════

class _PopularDestination {
  final String name;
  final double latitude;
  final double longitude;
  final List<String> keywords;

  const _PopularDestination({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.keywords,
  });
}

/// PopularPlacesConfig.current'tan _PopularDestination listesi üretir.
/// Şehre göre otomatik değişir.
List<_PopularDestination> _buildPopularDestinations() {
  final places = PopularPlacesConfig.current;
  return places.map((p) {
    final normalized = p.name
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll("'", '');

    // İsmin farklı varyasyonlarını keyword olarak ekle
    final keywords = <String>[normalized];

    // Boşluksuz versiyon
    final noSpace = normalized.replaceAll(' ', '');
    if (noSpace != normalized) keywords.add(noSpace);

    // İlk kelime (ör: "forum" → "forum magnesia")
    final firstWord = normalized.split(' ').first;
    if (firstWord.length > 3 && !keywords.contains(firstWord)) {
      keywords.add(firstWord);
    }

    return _PopularDestination(
      name: p.name,
      latitude: p.latitude,
      longitude: p.longitude,
      keywords: keywords,
    );
  }).toList();
}

// Sabit Manisa yerleri — şehir Manisa'yken kullanılır (eski davranış korunur)
const _kManisaDestinations = [
  _PopularDestination(
    name: 'Meydan AVM',
    latitude: 38.611139,
    longitude: 27.387089,
    keywords: ['meydan avm', 'meydanavm', 'beyaz fil', 'beyazfil', 'beyazfile'],
  ),
  _PopularDestination(
    name: 'Forum Magnesia AVM',
    latitude: 38.616165,
    longitude: 27.400331,
    keywords: ['forum magnesia', 'forum avm', 'magnesia', 'forum'],
  ),
  _PopularDestination(
    name: 'Prime Mall AVM',
    latitude: 38.61566,
    longitude: 27.39725,
    keywords: ['prime mall', 'prime avm', 'prime'],
  ),
  _PopularDestination(
    name: 'CBÜ Hastanesi',
    latitude: 38.611043,
    longitude: 27.378358,
    keywords: [
      'cbu hastanesi',
      'cbu hastane',
      'cbuhastane',
      'celal bayar hastane'
    ],
  ),
  _PopularDestination(
    name: 'Şehir Hastanesi',
    latitude: 38.6095,
    longitude: 27.458,
    keywords: ['sehir hastanesi', 'sehir hastane', 'yeni hastane'],
  ),
  _PopularDestination(
    name: 'Manisa Terminal',
    latitude: 38.6378,
    longitude: 27.4460,
    keywords: ['manisa terminal', 'manisa otogar', 'terminal', 'otogar'],
  ),
  _PopularDestination(
    name: 'CBÜ Kampüs',
    latitude: 38.6767,
    longitude: 27.3114,
    keywords: [
      'cbu kampus',
      'celal bayar universite',
      'cbu universite',
      'kampus',
      'universite',
      'cbu'
    ],
  ),
  _PopularDestination(
    name: 'Manisa Meydan',
    latitude: 38.6127,
    longitude: 27.4297,
    keywords: [
      'cumhuriyet meydani',
      'manisa meydani',
      'cumhuriyet meydan',
      'manisa meydan',
      'meydan'
    ],
  ),
  _PopularDestination(
    name: 'Muradiye',
    latitude: 38.6509,
    longitude: 27.3309,
    keywords: ['muradiye'],
  ),
];

// Kıbrıs yerleri
const _kCyprusDestinations = [
  _PopularDestination(
    name: 'NEÜ Kampüs',
    latitude: 35.1979,
    longitude: 33.3568,
    keywords: ['neu kampus', 'neu', 'yakin dogu universitesi', 'near east'],
  ),
  _PopularDestination(
    name: 'DAÜ Kampüs',
    latitude: 35.1504,
    longitude: 33.9077,
    keywords: [
      'dau kampus',
      'dau',
      'dogus amerikan universitesi',
      'eastern mediterranean',
      'emu'
    ],
  ),
  _PopularDestination(
    name: 'Lefkoşa Terminal',
    latitude: 35.1731,
    longitude: 33.3595,
    keywords: ['lefkosa terminal', 'lefkosa otogar', 'nicosia terminal'],
  ),
  _PopularDestination(
    name: 'Girne Limanı',
    latitude: 35.3411,
    longitude: 33.3196,
    keywords: ['girne', 'kyrenia', 'girne limani'],
  ),
  _PopularDestination(
    name: 'Mağusa Kalesi',
    latitude: 35.1233,
    longitude: 33.9428,
    keywords: ['magusa', 'famagusta', 'gazimagusa'],
  ),
  _PopularDestination(
    name: 'Lefkoşa Merkez',
    latitude: 35.1856,
    longitude: 33.3823,
    keywords: ['lefkosa', 'nicosia', 'lefkosa merkez'],
  ),
];

/// Aktif şehre göre popüler destinasyon listesi döner
List<_PopularDestination> _getActiveDestinations() {
  final city = CityDetectionService.instance.currentCity;
  if (city == SupportedCity.cyprus) return _kCyprusDestinations;
  return _kManisaDestinations;
}

// ══════════════════════════════════════════════════════════════════
// GTFS SAAT YARDIMCI METODLARI
// ══════════════════════════════════════════════════════════════════

int _gtfsTimeToMinutes(String timeStr) {
  final parts = timeStr.split(':');
  if (parts.length < 2) return 0;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return h * 60 + m;
}

String _gtfsMinutesToDisplay(int totalMinutes) {
  final h = (totalMinutes ~/ 60) % 24;
  final m = totalMinutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

int _nowInMinutes() {
  final now = DateTime.now();
  return now.hour * 60 + now.minute;
}

int _minutesDiff(int depMinutes, int nowMinutes) {
  int diff = depMinutes - nowMinutes;
  if (diff < -720) diff += 1440;
  return diff;
}

class AIService {
  final String _apiKey;
  final DatabaseService _databaseService = DatabaseService();

  final _FaqCache _faqCache = _FaqCache();
  late final _RateLimiter _rateLimiter;

  static String get _baseUrl => ApiConfig.groqApiUrl;
  static const String _model = 'llama-3.3-70b-versatile';

  final Map<String, AIResponse> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 15);

  bool _rateLimiterReady = false;

  AIService({required String apiKey}) : _apiKey = apiKey {
    _rateLimiter = _RateLimiter();
    _faqCache.initialize();
    _initRateLimiter();
  }

  Future<void> _initRateLimiter() async {
    await _rateLimiter.initialize();
    _rateLimiterReady = true;
    debugPrint('✅ Rate Limiter hazır');
  }

  Future<AIResponse> chat(
    String userMessage, {
    List<AIMessage> conversationHistory = const [],
    double? userLat,
    double? userLon,
  }) async {
    if (_apiKey.isEmpty) {
      throw AIException('API key boş.');
    }

    try {
      if (!_rateLimiterReady) {
        await _rateLimiter.initialize();
        _rateLimiterReady = true;
      }

      final rateLimitCheck = _rateLimiter.canMakeRequest();
      if (!rateLimitCheck.allowed) {
        debugPrint('🚫 Rate limit asildi');
        return AIResponse(
          intent: 'rate_limited',
          parameters: {},
          response:
              rateLimitCheck.reason ?? '⚠️ Günlük istek limitine ulaşıldı.',
          confidence: 1.0,
          timestamp: DateTime.now(),
        );
      }

      _rateLimiter.recordRequest();
      debugPrint('📊 Rate limit gecti. Kalan: ' +
          (rateLimitCheck.remainingDaily - 1).toString() +
          ' gun');

      final cachedFaq = _faqCache.getCachedResponse(userMessage);
      if (cachedFaq != null) {
        debugPrint('💾 FAQ Cache HIT');
        return AIResponse(
          intent: 'faq',
          parameters: {},
          response: cachedFaq,
          confidence: 1.0,
          timestamp: DateTime.now(),
        );
      }

      final intent = _detectIntent(userMessage);
      debugPrint('🎯 Intent: ' + intent);

      final dbResult = await _fetchDbData(
        intent: intent,
        userMessage: userMessage,
        userLat: userLat,
        userLon: userLon,
      );

      if (dbResult.directAnswer != null) {
        _faqCache.cacheResponse(userMessage, dbResult.directAnswer!);
        return AIResponse(
          intent: intent,
          parameters: {},
          response: dbResult.directAnswer!,
          confidence: 1.0,
          timestamp: DateTime.now(),
          navigationRoute: dbResult.navigationRoute,
          navigationArgs: dbResult.navigationArgs,
          awaitingConfirmation: dbResult.awaitingConfirmation,
          pendingBoardingStop: dbResult.pendingBoardingStop,
          pendingDestination: dbResult.pendingDestination,
          pendingUserLat: dbResult.pendingUserLat,
          pendingUserLon: dbResult.pendingUserLon,
        );
      }

      if (intent == 'off_topic') {
        final cityName = PopularPlacesConfig.cityName;
        return AIResponse(
          intent: intent,
          parameters: {},
          response:
              'Ben sadece $cityName toplu taşıma konularında yardımcı olabilirim. '
              'Otobüs saati, güzergah veya durak hakkında bir şey sormak ister misiniz? 🚌',
          confidence: 1.0,
          timestamp: DateTime.now(),
        );
      }

      final cacheKey =
          _getCacheKey('$userMessage|${dbResult.contextForAI.hashCode}');
      if (_cache.containsKey(cacheKey)) {
        final cached = _cache[cacheKey]!;
        if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
          debugPrint('💾 Memory Cache HIT');
          return cached;
        }
      }

      debugPrint(
          '🤖 AI API çağrısı - Kalan: ${rateLimitCheck.remainingDaily}/gün');

      final systemPrompt = _buildStrictSystemPrompt(dbResult.contextForAI);
      final recentHistory = conversationHistory.length > 6
          ? conversationHistory.sublist(conversationHistory.length - 6)
          : conversationHistory;

      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        ...recentHistory.where((m) => !m.isSystem).map((m) => m.toJson()),
        {'role': 'user', 'content': userMessage},
      ];

      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'temperature': 0.1,
              'max_tokens': 500,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        final aiResponse = AIResponse(
          intent: intent,
          parameters: {},
          response: content.trim(),
          confidence: 0.9,
          timestamp: DateTime.now(),
          navigationRoute: dbResult.navigationRoute,
          navigationArgs: dbResult.navigationArgs,
        );

        _cache[cacheKey] = aiResponse;
        _faqCache.cacheResponse(userMessage, content.trim());

        debugPrint('✅ AI yanıt alındı');
        return aiResponse;
      } else if (response.statusCode == 401) {
        throw AIException('Geçersiz API key.');
      } else if (response.statusCode == 429) {
        throw AIException('İstek limiti aşıldı. Lütfen bekleyin.');
      } else {
        throw AIException('API hatası: ${response.statusCode}');
      }
    } on TimeoutException {
      throw AIException('Zaman aşımı. İnternet bağlantınızı kontrol edin.');
    } on AIException {
      rethrow;
    } catch (e) {
      debugPrint('❌ AI Hatası: $e');
      throw AIException('Hata: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // INTENT TESPİTİ
  // ══════════════════════════════════════════════════════════════════

  String _detectIntent(String message) {
    final n = _normalize(message);

    final trimmed = n.trim();
    if (trimmed == 'evet' ||
        trimmed == 'e' ||
        trimmed == 'hayir' ||
        trimmed == 'h' ||
        trimmed == 'evet dogru' ||
        trimmed == 'evet oradayim') {
      return 'confirmation';
    }

    final hasBoardingStop = _extractBoardingStop(message) != null;
    final destResult = _extractDestinationResult(message);
    final hasDestination = destResult != null;

    if (hasBoardingStop && hasDestination) return 'route_query_with_stop';

    if (hasDestination &&
        (n.contains('nasil gider') ||
            n.contains('gitmek istiyorum') ||
            n.contains('yol tarifi') ||
            n.contains('ulasabilirim') ||
            n.contains('nereden bineyim') ||
            n.contains('gidebilirim') ||
            n.contains('nasil gidebilirim'))) {
      return 'route_query';
    }

    // Manisa + Kıbrıs transit keywords
    final transitKeywords = [
      'hat', 'otobus', 'minibus', 'dolmus', 'durak', 'sefer',
      'kalkis', 'varis', 'gidiyorum', 'gitmek', 'nasil gider',
      'nereye', 'nereden', 'ulasim', 'terminal', 'kampus',
      'hastane', 'avm', 'dakika', 'saat', 'ne zaman',
      'kalkiyor', 'geliyor', 'transfer',
      // Manisa
      'beyaz fil', 'beyazfile', 'cumhuriyet', 'karakol', 'karakoy',
      'manisa', 'cbu', 'celal bayar',
      // Kıbrıs
      'lefkosa', 'girne', 'magusa', 'gazimagusa', 'famagusta',
      'kyrenia', 'nicosia', 'kktc', 'kibris', 'neu', 'dau', 'emu',
      'liman', 'kale', 'itimat', 'kombos', 'kibhas', 'ercan', 'havalimani',
      'guzelyurt', 'lefke', 'iskele',
    ];
    if (!transitKeywords.any((kw) => n.contains(kw))) return 'off_topic';

    if (RegExp(r'\d+').hasMatch(n) &&
        (n.contains('ne zaman') ||
            n.contains('kac dakika') ||
            n.contains('kaldi') ||
            n.contains('gelir') ||
            n.contains('kalkiyor') ||
            n.contains('sefer') ||
            n.contains('hat') ||
            n.contains('otobus'))) {
      return 'bus_time_query';
    }

    if (hasDestination) return 'route_query';

    if (n.contains('yakin') && n.contains('durak')) return 'nearby_stops';

    if (n.contains('hangi hat') ||
        n.contains('tum hat') ||
        n.contains('hat neler') ||
        n.contains('hatlar')) {
      return 'route_list';
    }

    return 'general_transit';
  }

  // ══════════════════════════════════════════════════════════════════
  // VERİTABANI VERİSİ
  // ══════════════════════════════════════════════════════════════════

  Future<_DbResult> _fetchDbData({
    required String intent,
    required String userMessage,
    double? userLat,
    double? userLon,
  }) async {
    try {
      switch (intent) {
        case 'bus_time_query':
          return await _busTimeData(userMessage);

        case 'route_query_with_stop':
          return await _routeDataWithBoardingStop(
              userMessage, userLat, userLon);

        case 'route_query':
          final destResult = _extractDestinationResult(userMessage);
          if (destResult != null && destResult.hasCoordinates) {
            return await _routeDataWithCoords(
              destResult: destResult,
              userLat: userLat,
              userLon: userLon,
            );
          }
          if (userLat != null && userLon != null) {
            return await _routeData(userMessage, userLat, userLon);
          }
          return _DbResult(
            contextForAI: '',
            directAnswer: '📍 Rota hesaplamak için konumunuza ihtiyacım var.\n'
                'Lütfen konum iznini açın veya "Nereye Gitmek İstiyorsunuz?" '
                'sayfasını kullanın.',
            navigationRoute: AppRoutes.destinationSearch,
          );

        case 'nearby_stops':
          if (userLat != null && userLon != null) {
            return await _nearbyStopsData(userLat, userLon);
          }
          return _DbResult(
            contextForAI: '',
            directAnswer:
                '📍 Yakın durakları görmek için konum iznini açmanız gerekiyor.',
          );

        case 'route_list':
          return await _routeListData();

        case 'off_topic':
        case 'confirmation':
          return _DbResult(contextForAI: '');

        default:
          return await _generalData();
      }
    } catch (e) {
      debugPrint('⚠️ DB hatası: $e');
      return _DbResult(
        contextForAI: '',
        directAnswer: '⚠️ Veritabanına erişilemiyor. Lütfen tekrar deneyin.',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // SEFER SAATİ
  // ══════════════════════════════════════════════════════════════════

  Future<_DbResult> _busTimeData(String message) async {
    // Kıbrıs modunda KktcBusService kullan (İtimat, Kombos, KIBHAS)
    final city = CityDetectionService.instance.currentCity;
    if (city == SupportedCity.cyprus) {
      final lines2 = KktcBusService.instance.searchByMessage(message);
      if (lines2.isNotEmpty) {
        final formatted = KktcBusService.instance.formatForAI(lines2);
        return _DbResult(
          contextForAI: '',
          directAnswer: formatted,
        );
      }
      // Mesajda şehir/şirket bulunamadı — genel bilgi ver
      return _DbResult(
        contextForAI: '',
        directAnswer:
            'KKTC\'de şehirlerarası ulaşım bu firmalar tarafından sağlanıyor:\n\n'
            '🚌 İtimat — Mağusa ↔ Lefkoşa (07:00–19:00, her saat başı)\n'
            '🚌 Kombos — Girne ↔ Lefkoşa (06:00–19:30) | Girne ↔ Mağusa (07:00–18:00)\n'
            '✈️ KIBHAS — Ercan Havalimanı ↔ Tüm şehirler\n\n'
            'Hangi güzergah için bilgi almak istiyorsunuz?\n'
            'Örnek: "Mağusa\'dan Lefkoşa\'ya ne zaman otobüs var?"',
      );
    }

    final routeNumber = _extractRouteNumber(message);

    if (routeNumber == null) {
      final routes = await _databaseService.getAllRoutes();
      final list =
          routes.map((r) => 'Hat ${r.routeShortName}').take(30).join(', ');
      return _DbResult(
        contextForAI: '',
        directAnswer:
            'Hangi hattı sormak istiyorsunuz?\n\nMevcut hatlar: $list',
      );
    }

    final routes = await _databaseService.getAllRoutes();
    final route =
        routes.where((r) => r.routeShortName == routeNumber).firstOrNull;

    if (route == null) {
      final list =
          routes.map((r) => 'Hat ${r.routeShortName}').take(20).join(', ');
      return _DbResult(
        contextForAI: '',
        directAnswer: 'Hat $routeNumber bulunamadı.\n\nMevcut hatlar: $list',
      );
    }

    final now = DateTime.now();
    final nowMinutes = _nowInMinutes();
    final currentTimeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final stopName = _extractStopName(message);
    String? targetStopId;
    String usedStopName = '';

    if (stopName != null) {
      final allStops = await _databaseService.getAllStops();
      final match = allStops
          .where((s) => _normalize(s.stopName).contains(_normalize(stopName)))
          .firstOrNull;
      if (match != null) {
        targetStopId = match.stopId;
        usedStopName = match.stopName;
      }
    }

    if (targetStopId == null) {
      final stops = await _databaseService
          .getStopsForRouteDirection(route.routeId, direction: 1);
      if (stops.isEmpty) {
        return _DbResult(
          contextForAI: '',
          directAnswer: 'Hat $routeNumber için durak bilgisi bulunamadı.',
        );
      }
      targetStopId = stops.first.stopId;
      usedStopName = stops.first.stopName;
    }

    final departures = await _databaseService.getUpcomingDeparturesForStop(
      routeNumber,
      targetStopId,
      direction: 1,
    );

    final operatingHours =
        await _databaseService.getOperatingHoursForRoute(routeNumber);

    final sb = StringBuffer();
    sb.writeln('🚌 Hat $routeNumber — ${route.routeLongName}');
    sb.writeln('📍 Durak: $usedStopName');
    sb.writeln('🕐 Şu an: $currentTimeStr');
    sb.writeln('⏰ Sefer saatleri: $operatingHours');
    sb.writeln();

    if (departures.isEmpty) {
      sb.writeln('Bu saat için aktif sefer bulunmuyor.');
    } else {
      sb.writeln('Sonraki seferler:');
      int shown = 0;

      for (final dep in departures) {
        if (shown >= 5) break;

        final depMinutes = _gtfsTimeToMinutes(dep);
        final diff = _minutesDiff(depMinutes, nowMinutes);

        if (diff <= 0) {
          debugPrint('⏭ Atlandı (geçmiş): $dep (diff=$diff, now=$nowMinutes)');
          continue;
        }

        final displayTime = _gtfsMinutesToDisplay(depMinutes);

        if (diff < 60) {
          sb.writeln('• $displayTime → $diff dakika sonra');
        } else {
          final h = diff ~/ 60;
          final m = diff % 60;
          sb.writeln('• $displayTime → ${h}s ${m}dk sonra');
        }
        shown++;
      }

      if (shown == 0) {
        sb.writeln('Bu saat için aktif sefer bulunmuyor.');
      }
    }

    return _DbResult(
      contextForAI: '',
      directAnswer: sb.toString().trim(),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // KOORDİNATLI ROTA
  // ══════════════════════════════════════════════════════════════════

  Future<_DbResult> _routeDataWithCoords({
    required _DestinationResult destResult,
    double? userLat,
    double? userLon,
  }) async {
    if (userLat == null || userLon == null) {
      return _DbResult(
        contextForAI: '',
        directAnswer: '📍 Rota hesaplamak için konumunuza ihtiyacım var.\n'
            '"${destResult.displayName}" için "Nereye Gitmek İstiyorsunuz?" '
            'sayfasını kullanabilirsiniz.',
        navigationRoute: AppRoutes.destinationSearch,
        navigationArgs: destResult.hasCoordinates
            ? {
                'name': destResult.displayName,
                'lat': destResult.latitude,
                'lon': destResult.longitude,
              }
            : null,
      );
    }

    final nowMinutes = _nowInMinutes();
    final isCyprus =
        CityDetectionService.instance.currentCity == SupportedCity.cyprus;

    final result = await _databaseService.findRoutesWithFallback(
      userLat: userLat,
      userLon: userLon,
      destLat: destResult.latitude!,
      destLon: destResult.longitude!,
    );

    final direct = result['direct'] as List<Map<String, dynamic>>;
    final transfer = result['transfer'] as List<Map<String, dynamic>>;

    final sb = StringBuffer();
    sb.writeln('🗺️ ${destResult.displayName} için rota:');
    sb.writeln();

    if (direct.isNotEmpty) {
      // Kıbrıs'ta isOperating her zaman false — sıralama anlamsız
      final sortedDirect = isCyprus
          ? direct
          : [
              ...direct.where((r) => r['isOperating'] == true),
              ...direct.where((r) => r['isOperating'] != true),
            ];

      for (int i = 0; i < sortedDirect.take(2).length; i++) {
        final r = sortedDirect[i];
        final route = r['route'];
        final boarding = r['boardingStop'];
        final alighting = r['alightingStop'];
        final walkTo = (r['walkToStop'] as double).toInt();
        final walkFrom = (r['walkFromStop'] as double).toInt();
        final totalDur = r['totalDuration'] as int;
        final nextDep = r['nextDeparture'] as String?;
        final isOp = r['isOperating'] as bool;

        sb.writeln(
            '${i + 1}. Hat ${route.routeShortName} — ${route.routeLongName}');
        sb.writeln('   🚶 ${boarding.stopName} durağına yürü ($walkTo m)');
        sb.writeln('   🚌 Hat ${route.routeShortName}\'e bin');
        sb.writeln('   🏁 ${alighting.stopName}\'de in');
        if (walkFrom > 50) sb.writeln('   🚶 Hedefe $walkFrom m yürü');
        sb.writeln('   ⏱ ~$totalDur dakika');

        // Kıbrıs'ta sefer saati verisi yok — satırı atla
        final isCyprus =
            CityDetectionService.instance.currentCity == SupportedCity.cyprus;
        if (!isCyprus) {
          if (isOp && nextDep != null) {
            final depMinutes = _gtfsTimeToMinutes(nextDep);
            final diff = _minutesDiff(depMinutes, nowMinutes);
            if (diff > 0) {
              final displayTime = _gtfsMinutesToDisplay(depMinutes);
              sb.writeln('   🕐 Sonraki sefer: $displayTime ($diff dk sonra)');
            }
          } else {
            sb.writeln('   ⚠️ Şu an aktif sefer yok');
          }
        }
        if (i < sortedDirect.length - 1) sb.writeln();
      }
    } else if (transfer.isNotEmpty) {
      final t = transfer.first;
      final r1 = (t['firstRoute']).routeShortName;
      final r2 = (t['secondRoute']).routeShortName;
      sb.writeln('Aktarmalı rota:');
      sb.writeln('🚌 Hat $r1 ile ${(t['boardingStop']).stopName}\'den bin');
      sb.writeln('🔄 ${(t['transferStop']).stopName}\'de in → Hat $r2\'ye geç');
      sb.writeln('🏁 ${(t['alightingStop']).stopName}\'de in');
      sb.writeln('⏱ ~${t['totalDuration']} dakika');
    } else {
      sb.writeln('Bu güzergah için uygun hat bulunamadı.');
    }

    return _DbResult(
      contextForAI: '',
      directAnswer: sb.toString().trim(),
      navigationRoute: AppRoutes.destinationSearch,
      navigationArgs: {
        'name': destResult.displayName,
        'lat': destResult.latitude,
        'lon': destResult.longitude,
      },
    );
  }

  // ── Biniş durağı belirtilmiş rota ─────────────────────────────────

  Future<_DbResult> _routeDataWithBoardingStop(
      String message, double? userLat, double? userLon) async {
    final boardingStopName = _extractBoardingStop(message);
    final destResult = _extractDestinationResult(message);

    if (boardingStopName == null || destResult == null) {
      if (userLat != null && userLon != null) {
        return await _routeData(message, userLat, userLon);
      }
      return _DbResult(
        contextForAI: '',
        directAnswer: 'Nereye gitmek istediğinizi anlayamadım.\n'
            'Örnek: "CBÜ\'ye nasıl giderim?"',
      );
    }

    final allStops = await _databaseService.getAllStops();
    final boardingMatches = allStops
        .where((s) =>
            _normalize(s.stopName).contains(_normalize(boardingStopName)))
        .toList();

    if (boardingMatches.isEmpty) {
      return _DbResult(
        contextForAI: '',
        directAnswer: '"$boardingStopName" durağı bulunamadı. '
            'Durak adını kontrol edin.',
      );
    }

    final boardingStop = boardingMatches.first;

    if (userLat != null && userLon != null) {
      final distance = _calculateDistance(
          userLat, userLon, boardingStop.latitude, boardingStop.longitude);

      if (distance > 300) {
        final nearbyStops = await _databaseService
            .getNearbyStops(userLat, userLon, maxDistance: 300);
        final gpsStopName =
            nearbyStops.isNotEmpty ? nearbyStops.first.stopName : null;
        final distInt = distance.toInt();

        final gpsInfo = gpsStopName != null
            ? 'GPS\'iniz "$gpsStopName" yakınını gösteriyor ($distInt m uzakta).'
            : 'GPS\'iniz "${boardingStop.stopName}" durağından $distInt m uzakta gösteriyor.';

        return _DbResult(
          contextForAI: '',
          directAnswer: '📍 $gpsInfo\n\n'
              '"${boardingStop.stopName}" durağında olduğunuzdan emin misiniz?\n\n'
              '• "Evet" → ${boardingStop.stopName} durağından rota hesaplarım\n'
              '• "Hayır" → GPS konumunuza göre rota hesaplarım',
          pendingBoardingStop: boardingStop,
          pendingDestination: destResult.displayName,
          pendingUserLat: userLat,
          pendingUserLon: userLon,
          awaitingConfirmation: true,
        );
      }
    }

    return await _buildRouteFromStop(
        boardingStop, destResult.displayName, allStops,
        destLat: destResult.latitude, destLon: destResult.longitude);
  }

  Future<_DbResult> _buildRouteFromStop(
    dynamic boardingStop,
    String destination,
    List<dynamic> allStops, {
    double? destLat,
    double? destLon,
  }) async {
    double? finalDestLat = destLat;
    double? finalDestLon = destLon;
    String finalDestName = destination;

    if (finalDestLat == null || finalDestLon == null) {
      final popular = _findPopularDestination(destination);
      if (popular != null) {
        finalDestLat = popular.latitude;
        finalDestLon = popular.longitude;
        finalDestName = popular.name;
      } else {
        final destMatches = allStops
            .where(
                (s) => _normalize(s.stopName).contains(_normalize(destination)))
            .toList();
        if (destMatches.isEmpty) {
          return _DbResult(
            contextForAI: '',
            directAnswer: '"$destination" için durak bulunamadı.',
          );
        }
        finalDestLat = destMatches.first.latitude;
        finalDestLon = destMatches.first.longitude;
        finalDestName = destMatches.first.stopName;
      }
    }

    final nowMinutes = _nowInMinutes();
    final isCyprus =
        CityDetectionService.instance.currentCity == SupportedCity.cyprus;

    final result = await _databaseService.findRoutesWithFallback(
      userLat: boardingStop.latitude,
      userLon: boardingStop.longitude,
      destLat: finalDestLat!,
      destLon: finalDestLon!,
      forceBoardingStop: boardingStop,
    );

    final direct = result['direct'] as List<Map<String, dynamic>>;
    final transfer = result['transfer'] as List<Map<String, dynamic>>;

    final sb = StringBuffer();
    sb.writeln('🗺️ ${boardingStop.stopName} → $finalDestName:');
    sb.writeln();

    if (direct.isNotEmpty) {
      // Kıbrıs'ta isOperating her zaman false — sıralama anlamsız
      final sortedDirect = isCyprus
          ? direct
          : [
              ...direct.where((r) => r['isOperating'] == true),
              ...direct.where((r) => r['isOperating'] != true),
            ];

      for (int i = 0; i < sortedDirect.take(2).length; i++) {
        final r = sortedDirect[i];
        final route = r['route'];
        final alighting = r['alightingStop'];
        final walkFrom = (r['walkFromStop'] as double).toInt();
        final totalDur = r['totalDuration'] as int;
        final nextDep = r['nextDeparture'] as String?;
        final isOp = r['isOperating'] as bool;

        sb.writeln(
            '${i + 1}. Hat ${route.routeShortName} — ${route.routeLongName}');
        sb.writeln('   🚌 ${boardingStop.stopName}\'den bin');
        sb.writeln('   🏁 ${alighting.stopName}\'de in');
        if (walkFrom > 50) sb.writeln('   🚶 Hedefe $walkFrom m yürü');
        sb.writeln('   ⏱ ~$totalDur dakika');

        // Kıbrıs'ta sefer saati verisi yok — satırı atla
        final isCyprus =
            CityDetectionService.instance.currentCity == SupportedCity.cyprus;
        if (!isCyprus) {
          if (isOp && nextDep != null) {
            final depMinutes = _gtfsTimeToMinutes(nextDep);
            final diff = _minutesDiff(depMinutes, nowMinutes);
            if (diff > 0) {
              final displayTime = _gtfsMinutesToDisplay(depMinutes);
              sb.writeln('   🕐 Sonraki sefer: $displayTime ($diff dk sonra)');
            }
          } else {
            sb.writeln('   ⚠️ Şu an aktif sefer yok');
          }
        }
        if (i < sortedDirect.length - 1) sb.writeln();
      }
    } else if (transfer.isNotEmpty) {
      final t = transfer.first;
      sb.writeln('Aktarmalı rota:');
      sb.writeln(
          '🚌 Hat ${(t['firstRoute']).routeShortName} ile ${boardingStop.stopName}\'den bin');
      sb.writeln(
          '🔄 ${(t['transferStop']).stopName}\'de in → Hat ${(t['secondRoute']).routeShortName}\'ye geç');
      sb.writeln('🏁 ${(t['alightingStop']).stopName}\'de in');
      sb.writeln('⏱ ~${t['totalDuration']} dakika');
    } else {
      sb.writeln('Bu güzergah için uygun hat bulunamadı.');
    }

    return _DbResult(
      contextForAI: '',
      directAnswer: sb.toString().trim(),
      navigationRoute: AppRoutes.destinationSearch,
      navigationArgs: {
        'name': finalDestName,
        'lat': finalDestLat,
        'lon': finalDestLon,
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // GPS'TEN ROTA
  // ══════════════════════════════════════════════════════════════════

  Future<_DbResult> _routeData(
      String message, double userLat, double userLon) async {
    final destResult = _extractDestinationResult(message);

    if (destResult != null && destResult.hasCoordinates) {
      return await _routeDataWithCoords(
        destResult: destResult,
        userLat: userLat,
        userLon: userLon,
      );
    }

    if (destResult == null) {
      return _DbResult(
        contextForAI: '',
        directAnswer: 'Nereye gitmek istediğinizi anlayamadım.\n'
            'Örnek: "CBÜ\'ye nasıl giderim?" veya "Meydan AVM\'ye gitmek istiyorum"',
      );
    }

    final allStops = await _databaseService.getAllStops();
    final matches = allStops
        .where((s) =>
            _normalize(s.stopName).contains(_normalize(destResult.displayName)))
        .toList();

    if (matches.isEmpty) {
      return _DbResult(
        contextForAI: '',
        directAnswer: '"${destResult.displayName}" için durak bulunamadı. '
            'Farklı bir isim deneyin veya "Nereye Gitmek İstiyorsunuz?" '
            'sayfasını kullanın.',
        navigationRoute: AppRoutes.destinationSearch,
      );
    }

    final destStop = matches.first;
    final nowMinutes = _nowInMinutes();
    final isCyprus =
        CityDetectionService.instance.currentCity == SupportedCity.cyprus;

    final result = await _databaseService.findRoutesWithFallback(
      userLat: userLat,
      userLon: userLon,
      destLat: destStop.latitude,
      destLon: destStop.longitude,
    );

    final direct = result['direct'] as List<Map<String, dynamic>>;
    final transfer = result['transfer'] as List<Map<String, dynamic>>;

    final sb = StringBuffer();
    sb.writeln('🗺️ ${destStop.stopName} için rota:');
    sb.writeln();

    if (direct.isNotEmpty) {
      // Kıbrıs'ta isOperating her zaman false — sıralama anlamsız
      final sortedDirect = isCyprus
          ? direct
          : [
              ...direct.where((r) => r['isOperating'] == true),
              ...direct.where((r) => r['isOperating'] != true),
            ];

      for (int i = 0; i < sortedDirect.take(2).length; i++) {
        final r = sortedDirect[i];
        final route = r['route'];
        final boarding = r['boardingStop'];
        final alighting = r['alightingStop'];
        final walkTo = (r['walkToStop'] as double).toInt();
        final walkFrom = (r['walkFromStop'] as double).toInt();
        final totalDur = r['totalDuration'] as int;
        final nextDep = r['nextDeparture'] as String?;
        final isOp = r['isOperating'] as bool;

        sb.writeln(
            '${i + 1}. Hat ${route.routeShortName} — ${route.routeLongName}');
        sb.writeln('   🚶 ${boarding.stopName} durağına yürü ($walkTo m)');
        sb.writeln('   🚌 Hat ${route.routeShortName}\'e bin');
        sb.writeln('   🏁 ${alighting.stopName}\'de in');
        if (walkFrom > 50) sb.writeln('   🚶 Hedefe $walkFrom m yürü');
        sb.writeln('   ⏱ ~$totalDur dakika');

        // Kıbrıs'ta sefer saati verisi yok — satırı atla
        final isCyprus =
            CityDetectionService.instance.currentCity == SupportedCity.cyprus;
        if (!isCyprus) {
          if (isOp && nextDep != null) {
            final depMinutes = _gtfsTimeToMinutes(nextDep);
            final diff = _minutesDiff(depMinutes, nowMinutes);
            if (diff > 0) {
              final displayTime = _gtfsMinutesToDisplay(depMinutes);
              sb.writeln('   🕐 Sonraki sefer: $displayTime ($diff dk sonra)');
            }
          } else {
            sb.writeln('   ⚠️ Şu an aktif sefer yok');
          }
        }
        if (i < sortedDirect.length - 1) sb.writeln();
      }
    } else if (transfer.isNotEmpty) {
      final t = transfer.first;
      final r1 = (t['firstRoute']).routeShortName;
      final r2 = (t['secondRoute']).routeShortName;
      sb.writeln('Aktarmalı rota:');
      sb.writeln('🚌 Hat $r1 ile ${(t['boardingStop']).stopName}\'den bin');
      sb.writeln('🔄 ${(t['transferStop']).stopName}\'de in → Hat $r2\'ye geç');
      sb.writeln('🏁 ${(t['alightingStop']).stopName}\'de in');
      sb.writeln('⏱ ~${t['totalDuration']} dakika');
    } else {
      sb.writeln('Bu güzergah için uygun hat bulunamadı.');
    }

    return _DbResult(
      contextForAI: '',
      directAnswer: sb.toString().trim(),
      navigationRoute: AppRoutes.destinationSearch,
      navigationArgs: {
        'name': destStop.stopName,
        'lat': destStop.latitude,
        'lon': destStop.longitude,
      },
    );
  }

  // ── Yakın duraklar ─────────────────────────────────────────────────

  Future<_DbResult> _nearbyStopsData(double lat, double lon) async {
    final stops =
        await _databaseService.getNearbyStops(lat, lon, maxDistance: 600);

    if (stops.isEmpty) {
      return _DbResult(
        contextForAI: '',
        directAnswer: '600 metre çevrenizde durak bulunamadı.',
      );
    }

    final sb = StringBuffer();
    sb.writeln('📍 Yakınızdaki duraklar:');
    sb.writeln();
    for (final stop in stops.take(5)) {
      final dist = stop.distanceFromUser?.toInt() ?? 0;
      sb.writeln('• ${stop.stopName} ($dist m)');
    }

    return _DbResult(
      contextForAI: '',
      directAnswer: sb.toString().trim(),
      navigationRoute: AppRoutes.nearbyStops,
    );
  }

  // ── Hat listesi ────────────────────────────────────────────────────

  Future<_DbResult> _routeListData() async {
    final routes = await _databaseService.getAllRoutes();
    final cityName = PopularPlacesConfig.cityName;
    final sb = StringBuffer();
    sb.writeln('🚌 $cityName aktif hatlar (${routes.length} hat):');
    sb.writeln();
    for (final r in routes) {
      sb.writeln('• Hat ${r.routeShortName}: ${r.routeLongName}');
    }
    return _DbResult(
      contextForAI: '',
      directAnswer: sb.toString().trim(),
      navigationRoute: AppRoutes.allRoutes,
    );
  }

  // ── Genel soru ─────────────────────────────────────────────────────

  Future<_DbResult> _generalData() async {
    final routes = await _databaseService.getAllRoutes();
    final cityName = PopularPlacesConfig.cityName;
    return _DbResult(
      contextForAI: '$cityName sisteminde ${routes.length} aktif hat var. '
          'Hatlar: ${routes.map((r) => 'Hat ${r.routeShortName}').take(15).join(', ')}.',
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // SİSTEM PROMPTU — şehir adı dinamik
  // ══════════════════════════════════════════════════════════════════

  String _buildStrictSystemPrompt(String contextData) {
    final cityName = PopularPlacesConfig.cityName;
    return '''Sen $cityName toplu taşıma asistanısın.

VERİLEN VERİ:
$contextData

MUTLAK KURALLAR:
1. ASLA kendi kafandan saat, güzergah veya durak adı uydurma.
2. Sadece yukarıdaki veriye göre cevap ver.
3. "Tahmin ediyorum", "genellikle", "muhtemelen" kullanma.
4. Konu dışı sorulara: "Sadece $cityName ulaşımı konusunda yardımcı olabilirim."
5. Kısa ve net yaz. Türkçe kullan.
''';
  }

  // ══════════════════════════════════════════════════════════════════
  // YARDIMCI METODLAR
  // ══════════════════════════════════════════════════════════════════

  String? _extractRouteNumber(String message) {
    final patterns = [
      RegExp(r'hat\s*(\d+)', caseSensitive: false),
      RegExp(r'(\d+)\s*numaral[ıi]', caseSensitive: false),
      RegExp(r'(\d+)\s*hatt[ıi]', caseSensitive: false),
      RegExp(r'(\d+)\s*no', caseSensitive: false),
      RegExp(r'\b(\d{1,3})\b'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(message);
      if (m != null) return m.group(1);
    }
    return null;
  }

  String? _extractStopName(String message) {
    final match = RegExp(r'([A-Za-zÇçĞğİıÖöŞşÜü\s]+)\s+dura[ğg][ıi]ndan?',
            caseSensitive: false)
        .firstMatch(message);
    return match?.group(1)?.trim();
  }

  String? _extractBoardingStop(String message) {
    final patterns = [
      RegExp(r'([A-Za-zÇçĞğİıÖöŞşÜü0-9\s/]+?)\s+dura[ğg][ıi]nda(?:y[ıi]m|n?\s)',
          caseSensitive: false),
      RegExp(r'([A-Za-zÇçĞğİıÖöŞşÜü0-9\s/]+?)\s+dura[ğg][ıi]ndan',
          caseSensitive: false),
      RegExp(r'([A-Za-zÇçĞğİıÖöŞşÜü0-9\s/]+?)\s+dura[ğg][ıi]nda\s+bekliyorum',
          caseSensitive: false),
      RegExp(
          r'([A-Za-zÇçĞğİıÖöŞşÜü0-9\s/]+?)\s+dura[ğg][ıi]nda\s+(?:bulunuyorum|duruyorum)',
          caseSensitive: false),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(message);
      if (m != null) {
        final name = m.group(1)?.trim();
        if (name != null && name.length > 2) return name;
      }
    }
    return null;
  }

  _DestinationResult? _extractDestinationResult(String message) {
    final n = _normalize(message);
    final destinations = _getActiveDestinations();

    for (final dest in destinations) {
      for (final kw in dest.keywords) {
        if (n.contains(kw)) {
          return _DestinationResult(
            displayName: dest.name,
            latitude: dest.latitude,
            longitude: dest.longitude,
          );
        }
      }
    }

    final apoMatch = RegExp(
            r"(\w[\w\s]*?)['''][ae]\s+(?:nasıl|gitmek|ulaş|gidebilir)",
            caseSensitive: false)
        .firstMatch(message);
    if (apoMatch != null) {
      final raw = apoMatch.group(1)?.trim();
      if (raw != null && raw.length > 2) {
        return _DestinationResult(displayName: raw);
      }
    }

    final forMatch =
        RegExp(r'([\w\s]+?)\s+için\s+(?:rota|yol)', caseSensitive: false)
            .firstMatch(message);
    if (forMatch != null) {
      final raw = forMatch.group(1)?.trim();
      if (raw != null && raw.length > 2) {
        return _DestinationResult(displayName: raw);
      }
    }

    return null;
  }

  _PopularDestination? _findPopularDestination(String name) {
    final n = _normalize(name);
    final destinations = _getActiveDestinations();
    for (final dest in destinations) {
      if (_normalize(dest.name).contains(n) ||
          n.contains(_normalize(dest.name))) {
        return dest;
      }
      for (final kw in dest.keywords) {
        if (n.contains(kw) || kw.contains(n)) return dest;
      }
    }
    return null;
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll("'", '')
        .replaceAll("'", '');
  }

  String _getCacheKey(String key) =>
      key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * 0.017453292519943295;
    final dLon = (lon2 - lon1) * 0.017453292519943295;
    final a = _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(lat1 * 0.017453292519943295) *
            _cos(lat2 * 0.017453292519943295) *
            _sin(dLon / 2) *
            _sin(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return r * c;
  }

  double _sin(double x) {
    final x2 = x * x;
    return x * (1 - x2 / 6 * (1 - x2 / 20));
  }

  double _cos(double x) {
    final x2 = x * x;
    return 1 - x2 / 2 * (1 - x2 / 12);
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x > 1 ? x / 2 : x;
    for (int i = 0; i < 20; i++) r = (r + x / r) / 2;
    return r;
  }

  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265358979;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265358979;
    if (x == 0 && y > 0) return 1.5707963267948966;
    if (x == 0 && y < 0) return -1.5707963267948966;
    return 0;
  }

  double _atan(double x) => x / (1 + 0.28125 * x * x);

  void clearCache() {
    _cache.clear();
    _faqCache.clear();
  }

  UsageStats getUsageStats() => _rateLimiter.getUsageStats();

  // ══════════════════════════════════════════════════════════════════
  // PUBLIC ONAY METODLARI
  // ══════════════════════════════════════════════════════════════════

  Future<AIResponse> routeFromConfirmedStop({
    required dynamic boardingStop,
    required String destination,
  }) async {
    final allStops = await _databaseService.getAllStops();
    final result =
        await _buildRouteFromStop(boardingStop, destination, allStops);
    return AIResponse(
      intent: 'route_query_with_stop',
      parameters: {},
      response: result.directAnswer ?? 'Rota hesaplanamadı.',
      confidence: 1.0,
      timestamp: DateTime.now(),
      navigationRoute: result.navigationRoute,
      navigationArgs: result.navigationArgs,
    );
  }

  Future<AIResponse> routeFromGps({
    required String destination,
    required double userLat,
    required double userLon,
  }) async {
    final popular = _findPopularDestination(destination);
    if (popular != null) {
      final result = await _routeDataWithCoords(
        destResult: _DestinationResult(
          displayName: popular.name,
          latitude: popular.latitude,
          longitude: popular.longitude,
        ),
        userLat: userLat,
        userLon: userLon,
      );
      return AIResponse(
        intent: 'route_query',
        parameters: {},
        response: result.directAnswer ?? 'Rota hesaplanamadı.',
        confidence: 1.0,
        timestamp: DateTime.now(),
        navigationRoute: result.navigationRoute,
        navigationArgs: result.navigationArgs,
      );
    }

    final result =
        await _routeData('gitmek istiyorum $destination', userLat, userLon);
    return AIResponse(
      intent: 'route_query',
      parameters: {},
      response: result.directAnswer ?? 'Rota hesaplanamadı.',
      confidence: 1.0,
      timestamp: DateTime.now(),
      navigationRoute: result.navigationRoute,
      navigationArgs: result.navigationArgs,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Destinasyon sonucu
// ══════════════════════════════════════════════════════════════════

class _DestinationResult {
  final String displayName;
  final double? latitude;
  final double? longitude;

  const _DestinationResult({
    required this.displayName,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;
}

// ══════════════════════════════════════════════════════════════════
// FAQ CACHE
// ══════════════════════════════════════════════════════════════════

class _FaqCache {
  final Map<String, _CacheEntry> _store = {};

  static const Duration _dynamicTtl = Duration(minutes: 10);
  static const Duration _staticTtl = Duration(hours: 2);
  static const int _maxEntries = 100;

  void initialize() {
    debugPrint('💾 FAQ Cache başlatıldı');
  }

  String _normalizeKey(String message) {
    return message
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll("'", '')
        .replaceAll("'", '');
  }

  bool _isDynamic(String message) {
    final n = _normalizeKey(message);
    return n.contains('ne zaman') ||
        n.contains('kac dakika') ||
        n.contains('sefer') ||
        n.contains('kalkiyor') ||
        n.contains('gelir');
  }

  String? getCachedResponse(String message) {
    final key = _normalizeKey(message);
    final entry = _store[key];
    if (entry == null) return null;

    final ttl = _isDynamic(message) ? _dynamicTtl : _staticTtl;
    if (DateTime.now().difference(entry.createdAt) > ttl) {
      _store.remove(key);
      return null;
    }

    entry.hitCount++;
    return entry.response;
  }

  void cacheResponse(String message, String response) {
    if (_isDynamic(message)) return;

    final key = _normalizeKey(message);

    if (_store.length >= _maxEntries) {
      final lruKey = _store.entries
          .reduce((a, b) => a.value.hitCount < b.value.hitCount ? a : b)
          .key;
      _store.remove(lruKey);
    }

    _store[key] = _CacheEntry(response: response);
  }

  void clear() => _store.clear();
}

class _CacheEntry {
  final String response;
  final DateTime createdAt;
  int hitCount;

  _CacheEntry({required this.response})
      : createdAt = DateTime.now(),
        hitCount = 0;
}

// ══════════════════════════════════════════════════════════════════
// RATE LIMITER
// ══════════════════════════════════════════════════════════════════

class _RateLimiter {
  SharedPreferences? _prefs;
  bool _initialized = false;

  static const int _maxPerMinute = 3;
  static const int _maxPerDay = 3;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      debugPrint('🚦 Rate Limiter hazır: $_maxPerDay soru/gün');
    } catch (e) {
      debugPrint('❌ Rate Limiter initialize hatası: $e');
    }
  }

  _RateLimitResult canMakeRequest() {
    if (!_initialized || _prefs == null) {
      debugPrint('⚠️ Rate Limiter henüz hazır değil, geçici izin veriliyor');
      return _RateLimitResult(
        allowed: true,
        remainingDaily: _maxPerDay,
        remainingMinute: _maxPerMinute,
      );
    }

    _cleanup();

    final now = DateTime.now();
    final today = _getTodayKey();
    final lastDay = _prefs!.getString('rl_last_day') ?? '';

    if (lastDay != today) {
      _prefs!.setInt('rl_daily_count', 0);
      _prefs!.setString('rl_last_day', today);
      debugPrint('🌅 Yeni gün - sayaç sıfırlandı');
    }

    final dailyCount = _prefs!.getInt('rl_daily_count') ?? 0;
    if (dailyCount >= _maxPerDay) {
      return _RateLimitResult(
        allowed: false,
        reason: '🚫 Günlük soru limitiniz doldu!\n\n'
            'Bugün $_maxPerDay soru hakkınızı kullandınız.\n'
            'Yarın tekrar kullanabilirsiniz 🌅\n\n'
            '💡 Manuel arama yapabilirsiniz:\n'
            '• "Nereye Gitmek İstiyorsunuz?"\n'
            '• Yakındaki Duraklar\n'
            '• Tüm Hatlar',
        remainingDaily: 0,
        remainingMinute: 0,
      );
    }

    final minuteRequests = _prefs!.getStringList('rl_minute_requests') ?? [];
    if (minuteRequests.length >= _maxPerMinute) {
      final oldestTime = int.tryParse(minuteRequests.first) ?? 0;
      final waitSec = 60 - (now.millisecondsSinceEpoch - oldestTime) ~/ 1000;

      return _RateLimitResult(
        allowed: false,
        reason: '⏳ Çok hızlı sorgu!\n$waitSec saniye bekleyin.',
        remainingDaily: _maxPerDay - dailyCount,
        remainingMinute: 0,
      );
    }

    return _RateLimitResult(
      allowed: true,
      remainingDaily: _maxPerDay - dailyCount,
      remainingMinute: _maxPerMinute - minuteRequests.length,
    );
  }

  void recordRequest() {
    if (!_initialized || _prefs == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    final minuteRequests = _prefs!.getStringList('rl_minute_requests') ?? [];
    minuteRequests.add(now.toString());
    _prefs!.setStringList('rl_minute_requests', minuteRequests);

    final dailyCount = _prefs!.getInt('rl_daily_count') ?? 0;
    _prefs!.setInt('rl_daily_count', dailyCount + 1);

    final remaining = _maxPerDay - (dailyCount + 1);
    debugPrint(
        '📊 AI İstek: ${dailyCount + 1}/$_maxPerDay (kalan: $remaining)');
  }

  void _cleanup() {
    if (_prefs == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - 60000;

    final minuteRequests = _prefs!.getStringList('rl_minute_requests') ?? [];
    final validRequests = minuteRequests
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .where((t) => t > cutoff)
        .map((e) => e.toString())
        .toList();

    _prefs!.setStringList('rl_minute_requests', validRequests);
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  UsageStats getUsageStats() {
    if (!_initialized || _prefs == null) {
      return UsageStats(
        dailyUsed: 0,
        dailyLimit: _maxPerDay,
        minuteUsed: 0,
        minuteLimit: _maxPerMinute,
      );
    }

    final dailyCount = _prefs!.getInt('rl_daily_count') ?? 0;
    final minuteRequests = _prefs!.getStringList('rl_minute_requests') ?? [];

    return UsageStats(
      dailyUsed: dailyCount,
      dailyLimit: _maxPerDay,
      minuteUsed: minuteRequests.length,
      minuteLimit: _maxPerMinute,
    );
  }
}

class _RateLimitResult {
  final bool allowed;
  final String? reason;
  final int remainingDaily;
  final int remainingMinute;

  _RateLimitResult({
    required this.allowed,
    this.reason,
    required this.remainingDaily,
    required this.remainingMinute,
  });
}

// ══════════════════════════════════════════════════════════════════
// Yardımcı sınıflar
// ══════════════════════════════════════════════════════════════════

class _DbResult {
  final String contextForAI;
  final String? directAnswer;
  final String? navigationRoute;
  final Map<String, dynamic>? navigationArgs;
  final bool awaitingConfirmation;
  final dynamic pendingBoardingStop;
  final String? pendingDestination;
  final double? pendingUserLat;
  final double? pendingUserLon;

  _DbResult({
    required this.contextForAI,
    this.directAnswer,
    this.navigationRoute,
    this.navigationArgs,
    this.awaitingConfirmation = false,
    this.pendingBoardingStop,
    this.pendingDestination,
    this.pendingUserLat,
    this.pendingUserLon,
  });
}

class AIException implements Exception {
  final String message;
  AIException(this.message);

  @override
  String toString() => 'AIException: $message';
}

class AIResponse {
  final String intent;
  final Map<String, String> parameters;
  final String response;
  final double confidence;
  final DateTime timestamp;
  final String? navigationRoute;
  final Map<String, dynamic>? navigationArgs;
  final bool awaitingConfirmation;
  final dynamic pendingBoardingStop;
  final String? pendingDestination;
  final double? pendingUserLat;
  final double? pendingUserLon;

  AIResponse({
    required this.intent,
    required this.parameters,
    required this.response,
    required this.confidence,
    required this.timestamp,
    this.navigationRoute,
    this.navigationArgs,
    this.awaitingConfirmation = false,
    this.pendingBoardingStop,
    this.pendingDestination,
    this.pendingUserLat,
    this.pendingUserLon,
  });

  bool get hasNavigation => navigationRoute != null;
}

class UsageStats {
  final int dailyUsed;
  final int dailyLimit;
  final int minuteUsed;
  final int minuteLimit;

  UsageStats({
    required this.dailyUsed,
    required this.dailyLimit,
    required this.minuteUsed,
    required this.minuteLimit,
  });

  double get dailyPercent => dailyLimit > 0 ? dailyUsed / dailyLimit : 0;
  int get dailyRemaining => dailyLimit - dailyUsed;

  @override
  String toString() =>
      'Günlük: $dailyUsed/$dailyLimit | Dakikalık: $minuteUsed/$minuteLimit';
}
