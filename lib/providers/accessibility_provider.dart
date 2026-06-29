import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Erişilebilirlik ayarları provider'ı
class AccessibilityProvider extends ChangeNotifier {
  // Ayar anahtarları
  static const String _keyLargeText = 'large_text';
  static const String _keyHighContrast = 'high_contrast';
  static const String _keyScreenReader = 'screen_reader';
  static const String _keyDarkMode = 'dark_mode';

  // Ayar değerleri
  bool _largeText = false;
  bool _highContrast = false;
  bool _screenReaderEnabled = false;
  bool _darkMode = false;

  // Getters
  bool get largeText => _largeText;
  bool get highContrast => _highContrast;
  bool get screenReaderEnabled => _screenReaderEnabled;
  bool get darkMode => _darkMode;

  // Uyumluluk için alternatif getter'lar
  bool get largeTextMode => _largeText;
  bool get highContrastMode => _highContrast;

  // Boyut hesaplamaları
  double get buttonHeight => _largeText ? 56.0 : 48.0;
  double get iconSize => _largeText ? 28.0 : 24.0;
  double get fontSize => _largeText ? 18.0 : 16.0;
  double get textScaleFactor => _largeText ? 1.3 : 1.0;

  AccessibilityProvider() {
    _loadSettings();
  }

  /// Ayarları yükle
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _largeText = prefs.getBool(_keyLargeText) ?? false;
      _highContrast = prefs.getBool(_keyHighContrast) ?? false;
      _screenReaderEnabled = prefs.getBool(_keyScreenReader) ?? false;
      _darkMode = prefs.getBool(_keyDarkMode) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('Ayarlar yüklenemedi: $e');
    }
  }

  /// Ayarları manuel yükle (main.dart için)
  Future<void> loadSettings() async {
    await _loadSettings();
  }

  /// Büyük yazı ayarı
  Future<void> setLargeText(bool value) async {
    _largeText = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLargeText, value);
    } catch (e) {
      debugPrint('Ayar kaydedilemedi: $e');
    }
  }

  /// Yüksek kontrast ayarı
  Future<void> setHighContrast(bool value) async {
    _highContrast = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHighContrast, value);
    } catch (e) {
      debugPrint('Ayar kaydedilemedi: $e');
    }
  }

  /// Sesli okuma ayarı
  Future<void> setScreenReader(bool value) async {
    _screenReaderEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyScreenReader, value);
    } catch (e) {
      debugPrint('Ayar kaydedilemedi: $e');
    }
  }

  /// Karanlık mod ayarı
  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDarkMode, value);
    } catch (e) {
      debugPrint('Ayar kaydedilemedi: $e');
    }
  }

  /// Tüm ayarları sıfırla
  Future<void> resetSettings() async {
    _largeText = false;
    _highContrast = false;
    _screenReaderEnabled = false;
    _darkMode = false;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLargeText);
      await prefs.remove(_keyHighContrast);
      await prefs.remove(_keyScreenReader);
      await prefs.remove(_keyDarkMode);
    } catch (e) {
      debugPrint('Ayarlar sıfırlanamadı: $e');
    }
  }

  /// Toggle metotları
  void toggleLargeText() => setLargeText(!_largeText);
  void toggleHighContrast() => setHighContrast(!_highContrast);
  void toggleScreenReader() => setScreenReader(!_screenReaderEnabled);
  void toggleDarkMode() => setDarkMode(!_darkMode);
}
