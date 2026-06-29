import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

/// Text-to-Speech servisi
/// Sesli geri bildirim için kullanılır
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String? _currentEngine;
  String _currentLanguage = 'tr-TR';

  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;
  String? get currentEngine => _currentEngine;
  String get currentLanguage => _currentLanguage;

  /// TTS'i başlat
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('🔊 TTS başlatılıyor...');

      // Android için TTS motorunu ayarla
      if (Platform.isAndroid) {
        // Mevcut motorları listele
        try {
          final engines = await _flutterTts.getEngines;
          debugPrint('📋 Mevcut TTS motorları: $engines');

          // Google TTS tercih et (daha iyi Türkçe desteği)
          if (engines != null && engines.isNotEmpty) {
            for (var engine in engines) {
              final engineStr = engine.toString().toLowerCase();
              if (engineStr.contains('google')) {
                await _flutterTts.setEngine(engine.toString());
                _currentEngine = engine.toString();
                debugPrint('✅ TTS motoru seçildi: $_currentEngine');
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ TTS motor listesi alınamadı: $e');
        }

        // Sıra modu
        try {
          await _flutterTts.setQueueMode(1);
        } catch (e) {
          debugPrint('⚠️ Queue mode ayarlanamadı: $e');
        }
      }

      // Türkçe dil ayarı
      try {
        final languages = await _flutterTts.getLanguages;
        debugPrint('🌍 Mevcut diller: ${languages?.length ?? 0}');

        bool langSet = false;
        if (languages != null) {
          for (var lang in languages) {
            final langStr = lang.toString().toLowerCase();
            if (langStr == 'tr-tr' || langStr == 'tr_tr') {
              await _flutterTts.setLanguage(lang.toString());
              _currentLanguage = lang.toString();
              langSet = true;
              debugPrint('✅ Dil ayarlandı: $_currentLanguage');
              break;
            }
          }
          if (!langSet) {
            for (var lang in languages) {
              final langStr = lang.toString().toLowerCase();
              if (langStr.startsWith('tr')) {
                await _flutterTts.setLanguage(lang.toString());
                _currentLanguage = lang.toString();
                langSet = true;
                debugPrint('✅ Dil ayarlandı (alternatif): $_currentLanguage');
                break;
              }
            }
          }
        }

        if (!langSet) {
          // Varsayılan olarak tr-TR dene
          await _flutterTts.setLanguage('tr-TR');
          _currentLanguage = 'tr-TR';
          debugPrint('⚠️ Varsayılan dil kullanılıyor: tr-TR');
        }
      } catch (e) {
        debugPrint('⚠️ Dil ayarlanamadı: $e');
        // Yine de devam et
      }

      // Konuşma hızı - Türkçe için optimize
      await _flutterTts.setSpeechRate(Platform.isAndroid ? 0.45 : 0.5);

      // Ses seviyesi
      await _flutterTts.setVolume(1.0);

      // Ses tonu
      await _flutterTts.setPitch(1.0);

      // Android için ek ayarlar
      if (Platform.isAndroid) {
        try {
          await _flutterTts.awaitSpeakCompletion(true);
        } catch (e) {
          debugPrint('⚠️ awaitSpeakCompletion ayarlanamadı: $e');
        }
      }

      // iOS için ek ayarlar
      if (Platform.isIOS) {
        try {
          await _flutterTts.setSharedInstance(true);
          await _flutterTts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.ambient,
            [
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
              IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            ],
            IosTextToSpeechAudioMode.voicePrompt,
          );
        } catch (e) {
          debugPrint('⚠️ iOS audio ayarları yapılamadı: $e');
        }
      }

      // Event handlers
      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        debugPrint('🔊 Konuşma başladı');
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        debugPrint('🔊 Konuşma bitti');
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        debugPrint('❌ TTS Hatası: $msg');
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        debugPrint('🔊 Konuşma iptal edildi');
      });

      _isInitialized = true;
      debugPrint(
          '✅ TTS başlatıldı! Motor: $_currentEngine, Dil: $_currentLanguage');
      return true;
    } catch (e) {
      debugPrint('❌ TTS başlatılamadı: $e');
      return false;
    }
  }

  /// Metni sesli oku
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    // Henüz başlatılmamışsa başlat
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) {
        debugPrint('❌ TTS başlatılamadığı için konuşulamıyor');
        return;
      }
    }

    try {
      // Önceki konuşmayı durdur
      if (_isSpeaking) {
        await stop();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Metni temizle ve düzelt
      final cleanText = _prepareText(text);
      debugPrint('🔊 TTS: "$cleanText"');

      final result = await _flutterTts.speak(cleanText);
      debugPrint('🔊 speak() sonucu: $result');
    } catch (e) {
      debugPrint('❌ TTS speak hatası: $e');
    }
  }

  /// Metni TTS için hazırla
  String _prepareText(String text) {
    String result = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Özel karakterleri düzelt
    result = result
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll('(', ', ')
        .replaceAll(')', ', ')
        .replaceAll('[', ', ')
        .replaceAll(']', ', ');

    // Kısaltmaları aç
    result = result
        .replaceAll('CBÜ', 'Celal Bayar Üniversitesi')
        .replaceAll('AVM', 'Alışveriş Merkezi')
        .replaceAll('YHT', 'Yüksek Hızlı Tren')
        .replaceAll('OSB', 'Organize Sanayi Bölgesi')
        .replaceAll('TOKİ', 'Toplu Konut')
        .replaceAll('Mh.', 'Mahallesi')
        .replaceAll('Mah.', 'Mahallesi')
        .replaceAll('Cd.', 'Caddesi')
        .replaceAll('Cad.', 'Caddesi')
        .replaceAll('Sk.', 'Sokak')
        .replaceAll('Sok.', 'Sokak')
        .replaceAll('Blv.', 'Bulvarı')
        .replaceAll('No:', 'Numara ')
        .replaceAll('dk.', 'dakika')
        .replaceAll('dk', 'dakika')
        .replaceAll('sn.', 'saniye')
        .replaceAll('sn', 'saniye')
        .replaceAll(' km', ' kilometre')
        .replaceAll(' m ', ' metre ')
        .replaceAll(' m.', ' metre.')
        .replaceAll(' m,', ' metre,');

    // Sayıları daha okunabilir yap
    result = result.replaceAllMapped(
      RegExp(r'(\d+)\.(\d+)'),
      (match) => '${match.group(1)} nokta ${match.group(2)}',
    );

    // Fazla boşlukları temizle
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    return result;
  }

  /// Okumayı durdur
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
    } catch (e) {
      debugPrint('❌ TTS stop hatası: $e');
    }
  }

  /// Ses seviyesini ayarla (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _flutterTts.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Konuşma hızını ayarla (0.0 - 1.0)
  Future<void> setRate(double rate) async {
    await _flutterTts.setSpeechRate(rate.clamp(0.2, 0.8));
  }

  /// Ses tonunu ayarla (0.5 - 2.0)
  Future<void> setPitch(double pitch) async {
    await _flutterTts.setPitch(pitch.clamp(0.5, 2.0));
  }

  // ==================== YARDIMCI METOTLAR ====================

  /// Ekran bildirimi
  Future<void> announceScreen(String screenName, String description) async {
    await speak('$screenName. $description');
  }

  /// Durak bildirimi
  Future<void> announceStop(String stopName, {String? distance}) async {
    if (distance != null) {
      await speak('$stopName durağı. $distance uzaklıkta.');
    } else {
      await speak('$stopName durağı.');
    }
  }

  /// Hat bildirimi
  Future<void> announceRoute(String routeNumber, String routeName) async {
    await speak('$routeNumber numaralı hat. $routeName');
  }

  /// Sonuç bildirimi
  Future<void> announceResults(int count, String itemType) async {
    if (count == 0) {
      await speak('$itemType bulunamadı.');
    } else if (count == 1) {
      await speak('Bir $itemType bulundu.');
    } else {
      await speak('$count $itemType bulundu.');
    }
  }

  /// Hata bildirimi
  Future<void> announceError(String message) async {
    await speak('Hata. $message');
  }

  /// Başarı bildirimi
  Future<void> announceSuccess(String message) async {
    await speak('Başarılı. $message');
  }

  /// Yükleniyor bildirimi
  Future<void> announceLoading() async {
    await speak('Yükleniyor, lütfen bekleyin.');
  }

  /// İniş uyarısı
  Future<void> announceAlighting(String stopName) async {
    await speak('Dikkat! $stopName durağında ininiz.');
  }

  /// TTS test et
  Future<bool> test() async {
    try {
      await speak('Sesli okuma çalışıyor.');
      return true;
    } catch (e) {
      debugPrint('❌ TTS test hatası: $e');
      return false;
    }
  }

  /// Dil mevcut mu kontrol et
  Future<bool> isLanguageAvailable(String language) async {
    try {
      final result = await _flutterTts.isLanguageAvailable(language);
      return result == 1;
    } catch (e) {
      return false;
    }
  }
}
