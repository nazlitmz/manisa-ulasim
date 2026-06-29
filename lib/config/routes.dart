import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/nearby_stops_screen.dart';
import '../screens/destination_search_screen.dart';
import '../screens/route_results_screen.dart';
import '../screens/all_routes_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tts_test_screen.dart';
import '../screens/driver_notification_screen.dart';
import '../screens/route_map_screen.dart';
import '../screens/trip_navigation_screen.dart';
import '../models/route_model.dart';

/// Uygulama route isimleri ve oluşturucu
class AppRoutes {
  static const String home = '/';
  static const String nearbyStops = '/nearby-stops';
  static const String destinationSearch = '/destination-search';
  static const String routeResults = '/route-results';
  static const String allRoutes = '/all-routes';
  static const String settingsPage = '/settings';
  static const String ttsTest = '/tts-test';
  static const String driverNotification = '/driver-notification';
  static const String routeMap = '/route-map';
  static const String routeDetail = '/route-detail'; // ✨ YENİ
  static const String navigation = '/navigation';

  /// Route oluşturucu
  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());

      case nearbyStops:
        return MaterialPageRoute(builder: (_) => const NearbyStopsScreen());

      case destinationSearch:
        return MaterialPageRoute(
          builder: (_) => const DestinationSearchScreen(),
          settings: routeSettings,
        );

      case routeResults:
        return MaterialPageRoute(
          builder: (_) => const RouteResultsScreen(),
          settings: routeSettings,
        );

      case allRoutes:
        return MaterialPageRoute(builder: (_) => const AllRoutesScreen());

      case settingsPage:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());

      case ttsTest:
        return MaterialPageRoute(builder: (_) => const TtsTestScreen());

      case driverNotification:
        return MaterialPageRoute(
            builder: (_) => const DriverNotificationScreen());

      case routeMap:
        final route = routeSettings.arguments as TransitRoute;
        return MaterialPageRoute(
          builder: (_) => RouteMapScreen(route: route),
        );

      // ✨ YENİ: AI Chat'ten hat detayına yönlendirme
      // TransitRoute tipini BusRoute modeline göre güncelle
      case routeDetail:
        final route = routeSettings.arguments as TransitRoute;
        return MaterialPageRoute(
          builder: (_) => RouteMapScreen(route: route),
        );

      case navigation:
        return MaterialPageRoute(
          builder: (_) => const TripNavigationScreen(),
          settings: routeSettings,
        );

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Sayfa bulunamadı: ${routeSettings.name}'),
            ),
          ),
        );
    }
  }
}
