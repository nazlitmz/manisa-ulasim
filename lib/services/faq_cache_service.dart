import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// FAQ Cache Service - Sık sorulan soruların cevaplarını saklar
///
/// Amaç: Aynı sorular tekrar API'ye gitmez, direkt cache'ten döner
/// Bu sayede %60-80 maliyet tasarrufu sağlanır
class FaqCacheService {
  static final FaqCacheService _instance = FaqCacheService._internal();
  factory FaqCacheService() => _instance;
  FaqCacheService._internal();

  Database? _database;

  Future<void> initialize() async {
    if (_database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'faq_cache.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
      );

      debugPrint('✅ FAQ Cache başlatıldı');

      // İlk açılışta popüler soruları ekle
      await _seedFrequentQuestions();
    } catch (e) {
      debugPrint('❌ FAQ Cache hatası: $e');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // FAQ cache tablosu
    await db.execute('''
      CREATE TABLE faq_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query_hash TEXT UNIQUE NOT NULL,
        normalized_query TEXT NOT NULL,
        response TEXT NOT NULL,
        hit_count INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_accessed INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_query_hash ON faq_cache(query_hash)');
    await db.execute('CREATE INDEX idx_hit_count ON faq_cache(hit_count DESC)');
  }

  /// Sık sorulan soruları hazır olarak ekle (AI'sız cevaplar)
  Future<void> _seedFrequentQuestions() async {
    if (_database == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    final frequentQA = [
      {
        'query': 'yakındaki duraklar nerede',
        'response': '📍 Yakındaki durakları görmek için:\n\n'
            '1. Ana sayfadaki "Yakındaki Duraklar" butonuna tıklayın\n'
            '2. Veya bana "yakındaki duraklar" yazın\n\n'
            'Konum izninizin açık olması gerekiyor.'
      },
      {
        'query': 'hangi hatlar var',
        'response': '🚌 Tüm hatları görmek için:\n\n'
            '1. Ana sayfadaki "Tüm Hatlar" butonuna tıklayın\n'
            '2. Veya "tüm hatlar" yazabilirsiniz\n\n'
            'Manisa\'da 30+ aktif hat bulunuyor.'
      },
      {
        'query': 'nasıl kullanırım',
        'response': '📱 Uygulama kullanımı:\n\n'
            '• Hedefinizi arama çubuğuna yazın\n'
            '• Veya sesli komut kullanın (🎤 butonu)\n'
            '• Ya da bana doğal dille sorun!\n\n'
            'Örnek: "CBÜ\'ye nasıl giderim?"'
      },
      {
        'query': 'sefer saatleri',
        'response': '🕐 Sefer saati öğrenmek için:\n\n'
            '"[Hat numarası] ne zaman gelir?"\n\n'
            'Örnek:\n'
            '• "1 numaralı hat ne zaman gelir?"\n'
            '• "19 hat kaç dakikada gelir?"'
      },
    ];

    for (final qa in frequentQA) {
      final hash = _hashQuery(qa['query']!);
      try {
        await _database!.insert(
          'faq_cache',
          {
            'query_hash': hash,
            'normalized_query': qa['query'],
            'response': qa['response'],
            'hit_count': 100, // Yüksek hit count = popüler soru
            'created_at': now,
            'last_accessed': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (e) {
        // Zaten varsa geç
      }
    }
  }

  /// Cache'den cevap getir
  Future<String?> getCachedResponse(String query) async {
    if (_database == null) await initialize();

    final normalized = _normalizeQuery(query);
    final hash = _hashQuery(normalized);

    try {
      final result = await _database!.query(
        'faq_cache',
        where: 'query_hash = ?',
        whereArgs: [hash],
      );

      if (result.isEmpty) return null;

      // Hit count artır
      await _database!.update(
        'faq_cache',
        {
          'hit_count': (result.first['hit_count'] as int) + 1,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'query_hash = ?',
        whereArgs: [hash],
      );

      debugPrint('💾 FAQ Cache HIT: $normalized');
      return result.first['response'] as String;
    } catch (e) {
      debugPrint('⚠️ Cache okuma hatası: $e');
      return null;
    }
  }

  /// Yeni cevabı cache'e ekle
  Future<void> cacheResponse(String query, String response) async {
    if (_database == null) await initialize();

    final normalized = _normalizeQuery(query);
    final hash = _hashQuery(normalized);
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      await _database!.insert(
        'faq_cache',
        {
          'query_hash': hash,
          'normalized_query': normalized,
          'response': response,
          'hit_count': 1,
          'created_at': now,
          'last_accessed': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('⚠️ Cache yazma hatası: $e');
    }
  }

  /// En çok sorulan soruları getir (istatistik için)
  Future<List<Map<String, dynamic>>> getMostAskedQuestions(
      {int limit = 10}) async {
    if (_database == null) await initialize();

    try {
      return await _database!.query(
        'faq_cache',
        orderBy: 'hit_count DESC',
        limit: limit,
      );
    } catch (e) {
      return [];
    }
  }

  /// Eski cache kayıtlarını temizle (90 günden eski)
  Future<void> cleanOldCache() async {
    if (_database == null) return;

    final cutoff = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;

    try {
      final deleted = await _database!.delete(
        'faq_cache',
        where: 'last_accessed < ? AND hit_count < 3',
        whereArgs: [cutoff],
      );
      debugPrint('🗑️ $deleted eski cache kaydı silindi');
    } catch (e) {
      debugPrint('⚠️ Cache temizlik hatası: $e');
    }
  }

  String _normalizeQuery(String query) {
    return query
        .toLowerCase()
        .trim()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^\w\s]'), '') // Noktalama kaldır
        .replaceAll(RegExp(r'\s+'), ' '); // Fazla boşluk
  }

  String _hashQuery(String query) {
    // Basit hash fonksiyonu
    int hash = 0;
    for (int i = 0; i < query.length; i++) {
      hash = ((hash << 5) - hash) + query.codeUnitAt(i);
      hash = hash & hash; // 32-bit integer
    }
    return hash.abs().toString();
  }
}
