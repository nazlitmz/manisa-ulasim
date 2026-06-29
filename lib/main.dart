import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'providers/location_provider.dart';
import 'providers/stops_provider.dart';
import 'providers/routes_provider.dart';
import 'providers/accessibility_provider.dart';
import 'services/database_service.dart';
import 'services/gtfs_service_facade.dart';
import 'services/city_database_manager.dart';
import 'services/tts_service.dart';
import 'services/speech_service.dart';
import 'services/notification_service.dart';
import 'services/navigation_service.dart';
import 'config/routes.dart';
import 'config/app_theme.dart';
import 'providers/favorites_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  debugPrint('✅ .env yüklendi');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final databaseService = DatabaseService();
  await databaseService.initialize();

  GtfsService.instance
      .selectCity(SupportedCity.cyprus)
      .then((_) => debugPrint('✅ Kıbrıs GTFS hazır'))
      .catchError((e) => debugPrint('⚠️ Kıbrıs GTFS yüklenemedi: $e'));

  await NotificationService().initialize();
  debugPrint('✅ Notification servisi başlatıldı');

  TtsService().initialize().then((_) => debugPrint('✅ TTS servisi hazır'));
  SpeechService()
      .initialize()
      .then((_) => debugPrint('✅ Speech servisi hazır'));

  _requestNotificationPermission();

  // ✅ Provider'ları önce oluştur, sonra birbirine bağla
  final stopsProvider = StopsProvider();
  final routesProvider = RoutesProvider();
  final locationProvider = LocationProvider();

  // ✅ GPS şehri değiştirince durak ve hat önbelleklerini temizle
  locationProvider.addListener(() {
    stopsProvider.onCityChanged();
    routesProvider.onCityChanged();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccessibilityProvider()),
        ChangeNotifierProvider.value(value: locationProvider),
        ChangeNotifierProvider.value(value: stopsProvider),
        ChangeNotifierProvider.value(value: routesProvider),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => NavigationService()),
      ],
      child: const ManisaUlasimApp(),
    ),
  );
}

Future<void> _requestNotificationPermission() async {
  final status = await Permission.notification.status;
  if (status.isDenied) {
    debugPrint('📢 Bildirim izni isteniyor...');
    final result = await Permission.notification.request();
    if (result.isGranted) {
      debugPrint('✅ Bildirim izni VERİLDİ!');
    } else if (result.isDenied) {
      debugPrint('❌ Bildirim izni REDDEDİLDİ!');
    } else if (result.isPermanentlyDenied) {
      debugPrint('⚠️ Bildirim izni KALICI REDDEDİLDİ!');
    }
  } else if (status.isGranted) {
    debugPrint('✅ Bildirim izni ZATEN VERİLMİŞ!');
  } else if (status.isPermanentlyDenied) {
    debugPrint('⚠️ Bildirim izni daha önce kalıcı reddedilmiş.');
  }
}

class ManisaUlasimApp extends StatelessWidget {
  const ManisaUlasimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AccessibilityProvider>(
      builder: (context, accessibility, child) {
        SystemChrome.setSystemUIOverlayStyle(
          accessibility.darkMode
              ? const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.light,
                  systemNavigationBarContrastEnforced: false,
                )
              : const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.dark,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.dark,
                  systemNavigationBarContrastEnforced: false,
                ),
        );

        return MaterialApp(
          title: 'Manisa Ulaşım',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: accessibility.darkMode ? ThemeMode.dark : ThemeMode.light,
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.generateRoute,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final textScaleFactor = accessibility.largeText ? 1.3 : 1.0;
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(textScaleFactor),
                padding: mediaQuery.padding.copyWith(
                  bottom: mediaQuery.padding.bottom > 0
                      ? mediaQuery.padding.bottom
                      : mediaQuery.viewPadding.bottom,
                ),
              ),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: accessibility.darkMode
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                child: child ?? const SizedBox(),
              ),
            );
          },
        );
      },
    );
  }
}
