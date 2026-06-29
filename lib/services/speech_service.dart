import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Ses tanıma servisi - Singleton pattern
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String _turkishLocaleId = 'tr_TR'; // Varsayılan Türkçe
  List<LocaleName> _availableLocales = [];

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  List<LocaleName> get availableLocales => _availableLocales;

  /// Ses tanımayı başlat
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speechToText.initialize(
        onStatus: (status) {
          debugPrint('🎤 Speech status: $status');
        },
        onError: (error) {
          debugPrint('❌ Speech error: ${error.errorMsg}');
        },
        debugLogging: true,
      );

      if (_isInitialized) {
        debugPrint('✅ Ses tanıma başlatıldı');

        // Mevcut dilleri al
        _availableLocales = await _speechToText.locales();
        debugPrint('🌍 Mevcut diller: ${_availableLocales.length}');

        // Türkçe'yi bul
        bool foundTurkish = false;
        for (final locale in _availableLocales) {
          debugPrint('   - ${locale.localeId}: ${locale.name}');

          // Türkçe locale'lerini kontrol et
          final id = locale.localeId.toLowerCase();
          if (id.contains('tr') || id.contains('tur')) {
            _turkishLocaleId = locale.localeId;
            foundTurkish = true;
            debugPrint('✅ Türkçe bulundu: $_turkishLocaleId');
          }
        }

        if (!foundTurkish) {
          debugPrint(
              '⚠️ Türkçe dil paketi bulunamadı! Varsayılan tr_TR kullanılacak.');
          // Yine de tr_TR dene - belki sistem destekliyor
          _turkishLocaleId = 'tr_TR';
        }
      } else {
        debugPrint('⚠️ Ses tanıma başlatılamadı');
      }

      return _isInitialized;
    } catch (e) {
      debugPrint('❌ Ses tanıma hatası: $e');
      return false;
    }
  }

  /// Belirli bir dilde dinlemeye başla
  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartialResult,
    Function()? onListeningStarted,
    Function()? onListeningStopped,
    String? localeId,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('❌ Ses tanıma başlatılamadı');
        return;
      }
    }

    if (_isListening) {
      await stopListening();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isListening = true;
    onListeningStarted?.call();

    // HER ZAMAN Türkçe kullan
    final useLocale = localeId ?? _turkishLocaleId;
    debugPrint('🎤 Dinleme başlıyor, locale: $useLocale (Türkçe zorlanıyor)');

    try {
      await _speechToText.listen(
        onResult: (SpeechRecognitionResult result) {
          debugPrint(
              '🎤 Tanınan: "${result.recognizedWords}" (final: ${result.finalResult}, confidence: ${result.confidence})');

          if (result.finalResult) {
            _isListening = false;
            onResult(result.recognizedWords);
            onListeningStopped?.call();
          } else if (result.recognizedWords.isNotEmpty) {
            onPartialResult?.call(result.recognizedWords);
          }
        },
        localeId: useLocale,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('❌ Dinleme hatası: $e');
      _isListening = false;
      onListeningStopped?.call();
    }
  }

  /// Dinlemeyi durdur
  Future<void> stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
    }
  }

  /// Dinlemeyi iptal et
  Future<void> cancelListening() async {
    await _speechToText.cancel();
    _isListening = false;
  }

  /// Mikrofon izni var mı?
  Future<bool> hasPermission() async {
    if (!_isInitialized) {
      return await initialize();
    }
    return _isInitialized;
  }

  /// Türkçe mevcut mu?
  bool get hasTurkish =>
      _availableLocales.any((l) => l.localeId.toLowerCase().contains('tr'));

  /// Türkçe locale ID
  String get turkishLocaleId => _turkishLocaleId;
}
