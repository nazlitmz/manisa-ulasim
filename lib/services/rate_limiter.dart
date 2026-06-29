import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rate Limiter - AI kullanım limitlerini kontrol eder
///
/// Limitler:
/// - Dakikada 3 istek (spam önleme)
/// - Günde 5 ücretsiz AI sorgusu
/// - Pro kullanıcılar için sınırsız
class RateLimiter {
  static final RateLimiter _instance = RateLimiter._internal();
  factory RateLimiter() => _instance;
  RateLimiter._internal();

  SharedPreferences? _prefs;

  // Limitler
  static const int _maxRequestsPerMinute = 3;
  static const int _maxRequestsPerDay = 5; // Ücretsiz kullanıcı
  static const Duration _rateLimitWindow = Duration(minutes: 1);

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// AI sorgusu yapılabilir mi kontrol et
  Future<RateLimitResult> canMakeRequest() async {
    await initialize();

    // Dakikalık limit kontrolü (spam önleme)
    final minuteCheck = await _checkMinuteLimit();
    if (!minuteCheck.allowed) {
      return minuteCheck;
    }

    // Günlük limit kontrolü (quota)
    final dayCheck = await _checkDailyLimit();
    return dayCheck;
  }

  /// İstek kaydı yap
  Future<void> recordRequest() async {
    await initialize();

    final now = DateTime.now().millisecondsSinceEpoch;

    // Dakikalık istekleri kaydet
    final minuteRequests = _prefs!.getStringList('minute_requests') ?? [];
    minuteRequests.add(now.toString());
    await _prefs!.setStringList('minute_requests', minuteRequests);

    // Günlük sayacı artır
    final today = _getTodayKey();
    final dailyCount = _prefs!.getInt('daily_count_$today') ?? 0;
    await _prefs!.setInt('daily_count_$today', dailyCount + 1);

    debugPrint(
        '📊 AI İstek kaydedildi: Günlük ${dailyCount + 1}/$_maxRequestsPerDay');
  }

  /// Dakikalık limit kontrolü
  Future<RateLimitResult> _checkMinuteLimit() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final minuteRequests = _prefs!.getStringList('minute_requests') ?? [];

    // Eski istekleri temizle
    final validRequests = minuteRequests
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .where((timestamp) => now - timestamp < _rateLimitWindow.inMilliseconds)
        .toList();

    await _prefs!.setStringList(
        'minute_requests', validRequests.map((e) => e.toString()).toList());

    if (validRequests.length >= _maxRequestsPerMinute) {
      final oldestRequest = validRequests.first;
      final waitSeconds =
          ((_rateLimitWindow.inMilliseconds - (now - oldestRequest)) / 1000)
              .ceil();

      return RateLimitResult(
        allowed: false,
        reason: '⏱️ Çok hızlı sorgu gönderiyorsunuz.\n'
            'Lütfen $waitSeconds saniye bekleyin.',
        remainingMinute: 0,
        remainingDaily: await _getRemainingDailyQuota(),
      );
    }

    return RateLimitResult(
      allowed: true,
      remainingMinute: _maxRequestsPerMinute - validRequests.length,
      remainingDaily: await _getRemainingDailyQuota(),
    );
  }

  /// Günlük limit kontrolü
  Future<RateLimitResult> _checkDailyLimit() async {
    // Pro kullanıcı kontrolü (şimdilik false, ileride premium eklenebilir)
    final isPro = await _isProUser();
    if (isPro) {
      return RateLimitResult(
        allowed: true,
        remainingMinute: _maxRequestsPerMinute,
        remainingDaily: 999, // Sınırsız
      );
    }

    final today = _getTodayKey();
    final dailyCount = _prefs!.getInt('daily_count_$today') ?? 0;

    if (dailyCount >= _maxRequestsPerDay) {
      return RateLimitResult(
        allowed: false,
        reason: '🚫 Günlük ücretsiz AI kotanız doldu.\n\n'
            'Bugün $_maxRequestsPerDay sorgu hakkınızı kullandınız.\n'
            'Yarın yeniden kullanabilirsiniz.\n\n'
            '💡 Veya manuel arama yapabilirsiniz:\n'
            '• "Nereye Gitmek İstiyorsunuz?" sayfası\n'
            '• Yakındaki Duraklar\n'
            '• Tüm Hatlar',
        remainingMinute: _maxRequestsPerMinute,
        remainingDaily: 0,
      );
    }

    return RateLimitResult(
      allowed: true,
      remainingMinute: _maxRequestsPerMinute,
      remainingDaily: _maxRequestsPerDay - dailyCount,
    );
  }

  /// Kalan günlük quota
  Future<int> _getRemainingDailyQuota() async {
    final isPro = await _isProUser();
    if (isPro) return 999;

    final today = _getTodayKey();
    final dailyCount = _prefs!.getInt('daily_count_$today') ?? 0;
    final remaining = _maxRequestsPerDay - dailyCount;
    return remaining < 0
        ? 0
        : (remaining > _maxRequestsPerDay ? _maxRequestsPerDay : remaining);
  }

  /// Pro kullanıcı mı kontrolü
  Future<bool> _isProUser() async {
    // TODO: Gerçek premium kontrol sistemi
    // Şimdilik false, ileride:
    // - Firebase Remote Config
    // - In-app purchase
    // - Backend API kontrolü
    return _prefs!.getBool('is_pro_user') ?? false;
  }

  /// Bugünün anahtarı (YYYY-MM-DD)
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// İstatistikleri sıfırla (yeni gün başlangıcı)
  Future<void> resetDailyStats() async {
    await initialize();

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    await _prefs!.remove('daily_count_$yesterdayKey');
    debugPrint('🗑️ Dünün istatistikleri temizlendi');
  }

  /// Kullanıcı istatistikleri
  Future<UsageStats> getUsageStats() async {
    await initialize();

    final today = _getTodayKey();
    final dailyCount = _prefs!.getInt('daily_count_$today') ?? 0;
    final isPro = await _isProUser();

    return UsageStats(
      dailyUsed: dailyCount,
      dailyLimit: isPro ? 999 : _maxRequestsPerDay,
      isPro: isPro,
    );
  }
}

/// Rate limit sonucu
class RateLimitResult {
  final bool allowed;
  final String? reason;
  final int remainingMinute;
  final int remainingDaily;

  RateLimitResult({
    required this.allowed,
    this.reason,
    required this.remainingMinute,
    required this.remainingDaily,
  });
}

/// Kullanım istatistikleri
class UsageStats {
  final int dailyUsed;
  final int dailyLimit;
  final bool isPro;

  UsageStats({
    required this.dailyUsed,
    required this.dailyLimit,
    required this.isPro,
  });

  int get remaining =>
      math.max(0, math.min(dailyLimit - dailyUsed, dailyLimit));

  double get percentageUsed {
    if (dailyLimit == 0) return 0.0;
    final pct = dailyUsed / dailyLimit;
    return pct < 0.0 ? 0.0 : (pct > 1.0 ? 1.0 : pct);
  }

  bool get hasReachedLimit => remaining == 0 && !isPro;
}
