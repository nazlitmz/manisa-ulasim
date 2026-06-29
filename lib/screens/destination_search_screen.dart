import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stop_model.dart';
import '../models/route_model.dart';
import '../models/operating_hours.dart';
import '../providers/location_provider.dart';
import '../providers/stops_provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/database_service.dart';
import '../services/navigation_service.dart';
import '../services/tts_service.dart';
import '../services/gtfs_query_service.dart';
import '../services/kktc_intercity_service.dart';
import '../widgets/operating_hours_widget.dart';
import '../config/routes.dart';
import '../config/popular_places_config.dart';

class RouteResult {
  final TransitRoute route;
  final Stop boardingStop;
  final Stop alightingStop;
  final double walkToStop;
  final double walkFromStop;
  final int rideDuration;
  final int totalDuration;
  final String? nextDeparture;
  final bool isOperating;

  RouteResult(
      {required this.route,
      required this.boardingStop,
      required this.alightingStop,
      required this.walkToStop,
      required this.walkFromStop,
      required this.rideDuration,
      required this.totalDuration,
      this.nextDeparture,
      this.isOperating = true});

  String get formattedWalkToStop => walkToStop < 1000
      ? '${walkToStop.toInt()} m'
      : '${(walkToStop / 1000).toStringAsFixed(1)} km';
  String get formattedWalkFromStop => walkFromStop < 1000
      ? '${walkFromStop.toInt()} m'
      : '${(walkFromStop / 1000).toStringAsFixed(1)} km';
}

enum _StopSelectorMode { none, boarding, alighting }

class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  State<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  final TtsService _ttsService = TtsService();

  List<PopularPlace> _filteredPlaces = [];
  List<Stop> _filteredStops = [];
  bool _isSearching = false;
  bool _isCalculating = false;

  List<RouteResult> _activeResults = [];
  List<RouteResult> _expiredResults = [];
  List<Map<String, dynamic>> _transferResults = [];
  List<Stop> _alternativeStops = [];
  String? _fallbackSuggestion;
  String? _destinationName;
  String? _errorMessage;

  Stop? _selectedBoardingStop;
  Stop? _selectedAlightingStop;

  _StopSelectorMode _selectorMode = _StopSelectorMode.none;

  List<Stop> _nearbyStops = [];
  List<Stop> _routeStopsForAlighting = [];
  List<Stop> _nearbyKibhasStops =
      []; // ✅ Seçilen KIBHAS durağına yakın diğer duraklar

  final TextEditingController _boardingSearchCtrl = TextEditingController();
  final TextEditingController _alightingSearchCtrl = TextEditingController();
  String _boardingSearchQuery = '';
  int _boardingTabIndex = 0; // 0=Yakın Duraklar, 1=KIBHAS
  String _alightingSearchQuery = '';

  double? _lastDestLat;
  double? _lastDestLon;

  List<RouteResult> get _routeResults =>
      [..._activeResults, ..._expiredResults];

  bool get _hasResults =>
      _activeResults.isNotEmpty ||
      _expiredResults.isNotEmpty ||
      _transferResults.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _filteredPlaces = List.from(PopularPlacesConfig.current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announceScreen();
      _checkForDirectRoute();
      _preloadNearbyStops();
    });
  }

  Future<void> _preloadNearbyStops() async {
    try {
      final locationProvider = context.read<LocationProvider>();
      final userLocation = locationProvider.effectiveLocation;
      final stops = await _databaseService.getNearbyStops(
        userLocation.latitude,
        userLocation.longitude,
        maxDistance: 2000,
      );
      if (mounted) setState(() => _nearbyStops = stops);
    } catch (_) {}
  }

  Future<void> _announceScreen() async {
    final accessibility = context.read<AccessibilityProvider>();
    if (!accessibility.screenReaderEnabled) return;
    final status = OperatingHours.getStatus();
    String announcement = 'Nereye gitmek istiyorsunuz ekranı. ';
    if (!status.isOperating) announcement += '${status.title}. ';
    announcement +=
        'Yukarıdaki arama kutusundan yer veya durak arayabilirsiniz.';
    await _ttsService.speak(announcement);
  }

  Future<void> _checkForDirectRoute() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map<String, dynamic>) {
      final name = args['name'] as String?;
      final lat = args['lat'] as double?;
      final lon = args['lon'] as double?;
      if (name != null && lat != null && lon != null) {
        await _calculateRoute(
            destinationLat: lat, destinationLon: lon, destinationName: name);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _boardingSearchCtrl.dispose();
    _alightingSearchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredPlaces = List.from(PopularPlacesConfig.current);
        _filteredStops = [];
      } else {
        final normalizedQuery = _normalizeText(query);
        _filteredPlaces = PopularPlacesConfig.current
            .where((place) =>
                _normalizeText(place.name).contains(normalizedQuery) ||
                _normalizeText(place.category).contains(normalizedQuery))
            .toList();
        final stopsProvider = context.read<StopsProvider>();
        _filteredStops = stopsProvider.allStops
            .where((stop) =>
                _normalizeText(stop.stopName).contains(normalizedQuery))
            .take(10)
            .toList();
      }
    });
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('İ', 'i')
        .replaceAll('Ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('Ş', 's')
        .replaceAll('Ö', 'o')
        .replaceAll('Ç', 'c');
  }

  Future<void> _onPlaceSelected(PopularPlace place) async {
    await _calculateRoute(
        destinationLat: place.latitude,
        destinationLon: place.longitude,
        destinationName: place.name);
  }

  Future<void> _onStopSelected(Stop stop) async {
    await _calculateRoute(
        destinationLat: stop.latitude,
        destinationLon: stop.longitude,
        destinationName: stop.stopName);
  }

  Future<void> _calculateRoute({
    required double destinationLat,
    required double destinationLon,
    required String destinationName,
    Stop? forceBoardingStop,
  }) async {
    final locationProvider = context.read<LocationProvider>();
    final userLocation = locationProvider.effectiveLocation;

    final directDistance = _calculateDistance(
      userLocation.latitude,
      userLocation.longitude,
      destinationLat,
      destinationLon,
    );

    if (directDistance < 500) {
      final walkingTime = (directDistance / 80).round();

      setState(() {
        _isCalculating = false;
        _activeResults = [];
        _expiredResults = [];
        _transferResults = [];
        _alternativeStops = [];
        _destinationName = destinationName;
        _lastDestLat = destinationLat;
        _lastDestLon = destinationLon;
        _errorMessage = null;

        _fallbackSuggestion = '🚶 Hedef çok yakın!\n\n'
            '$destinationName sadece ${directDistance.toInt()} metre uzakta.\n'
            'Yürüyerek yaklaşık $walkingTime dakikada ulaşabilirsiniz.\n\n'
            '💡 Otobüse binmek yerine yürümenizi öneririz.';
      });

      final accessibility = context.read<AccessibilityProvider>();
      if (accessibility.screenReaderEnabled) {
        _ttsService
            .speak('Hedef sadece ${directDistance.toInt()} metre uzakta. '
                'Yaklaşık $walkingTime dakikalık yürüme mesafesinde. '
                'Yürüyerek gitmenizi öneririz.');
      }

      return;
    }

    final isNewDestination = destinationName != _destinationName;
    setState(() {
      _isCalculating = true;
      _selectorMode = _StopSelectorMode.none;
      _activeResults = [];
      _expiredResults = [];
      _transferResults = [];
      _alternativeStops = [];
      _fallbackSuggestion = null;
      _errorMessage = null;
      _destinationName = destinationName;
      _lastDestLat = destinationLat;
      _lastDestLon = destinationLon;
      // ✅ DÜZELTİLDİ: forceBoardingStop ile çağrıldığında _selectedBoardingStop sıfırlanmaz
      if (isNewDestination && forceBoardingStop == null) {
        _selectedBoardingStop = null;
        _selectedAlightingStop = null;
      }
    });

    try {
      if (_nearbyStops.isEmpty) {
        _nearbyStops = await _databaseService.getNearbyStops(
          userLocation.latitude,
          userLocation.longitude,
          maxDistance: 2000,
        );
      }

      final activeBoardingStop = forceBoardingStop ?? _selectedBoardingStop;

      final fallback = await _databaseService.findRoutesWithFallback(
        userLat: userLocation.latitude,
        userLon: userLocation.longitude,
        destLat: destinationLat,
        destLon: destinationLon,
        maxWalkingDistance: 2000,
        forceBoardingStop: activeBoardingStop,
      );

      final smartRoutes = fallback['direct'] as List<Map<String, dynamic>>;
      final transferRoutes = fallback['transfer'] as List<Map<String, dynamic>>;
      final altStops = fallback['alternativeStops'] as List<Stop>;
      final suggestion = fallback['suggestion'] as String?;

      if (smartRoutes.isEmpty && transferRoutes.isEmpty) {
        setState(() {
          _isCalculating = false;
          _alternativeStops = altStops;
          _fallbackSuggestion = suggestion;
          _errorMessage = suggestion ??
              (activeBoardingStop != null
                  ? '${activeBoardingStop.stopName} durağından bu hedefe giden hat bulunamadı.'
                  : 'Bu güzergah için uygun hat bulunamadı.');
        });
        return;
      }

      final active = <RouteResult>[];
      final expired = <RouteResult>[];

      // Mevcut iniş seçimi varsa koru, yoksa DB'den gelen değeri kullan
      final currentAlighting = _selectedAlightingStop;

      for (final data in smartRoutes) {
        final isOp = data['isOperating'] as bool? ?? true;
        final dbAlighting = data['alightingStop'] as Stop;
        final alighting = currentAlighting ?? dbAlighting;

        final result = RouteResult(
          route: data['route'] as TransitRoute,
          boardingStop: data['boardingStop'] as Stop,
          alightingStop: alighting,
          walkToStop: data['walkToStop'] as double,
          walkFromStop: currentAlighting != null
              ? _calculateDistance(
                  alighting.latitude,
                  alighting.longitude,
                  destinationLat,
                  destinationLon,
                )
              : data['walkFromStop'] as double,
          rideDuration: data['rideDuration'] as int,
          totalDuration: data['totalDuration'] as int,
          nextDeparture: data['nextDeparture'] as String?,
          isOperating: isOp,
        );
        if (isOp && result.nextDeparture != null) {
          active.add(result);
        } else {
          expired.add(result);
        }
      }

      active.sort((a, b) {
        if (a.nextDeparture != null && b.nextDeparture != null) {
          final timeCompare = a.nextDeparture!.compareTo(b.nextDeparture!);
          if (timeCompare != 0) return timeCompare;
        }
        return a.totalDuration.compareTo(b.totalDuration);
      });

      if (active.isNotEmpty) {
        _loadRouteStopsForAlighting(active.first.route.routeId);
      }

      // ✅ KIBHAS alternatif durakları al (Sabancı → DAÜ, Üst Geçit gibi)
      List<Stop> nearbyKibhas = [];
      if (smartRoutes.isNotEmpty) {
        final altRaw = smartRoutes.first['alternativeKibhasStops'];
        if (altRaw != null && altRaw is List) {
          nearbyKibhas = altRaw.cast<Stop>();
        }
      }

      setState(() {
        _isCalculating = false;
        _activeResults = active;
        _expiredResults = expired;
        _transferResults = transferRoutes;
        _alternativeStops = altStops;
        _fallbackSuggestion = suggestion;
        _nearbyKibhasStops = nearbyKibhas;
      });
    } catch (e) {
      setState(() {
        _isCalculating = false;
        _errorMessage = 'Rota hesaplanırken hata oluştu.';
      });
    }
  }

  // ✅ DÜZELTİLDİ: KIBHAS/İtimat/Kombos rotaları için terminal duraklarını fallback olarak ekle
  Future<void> _loadRouteStopsForAlighting(String routeId) async {
    try {
      final seen = <String>{};
      final combined = <Stop>[];

      // Kıbrıs: GtfsQueryService üzerinden her iki yönü çek
      final gtqs = GtfsQueryService.instance;
      final dir0 = await gtqs.getStopsForRoute(routeId, direction: 0);
      final dir1 = await gtqs.getStopsForRoute(routeId, direction: 1);

      if (dir0.isNotEmpty || dir1.isNotEmpty) {
        for (final s in [...dir0, ...dir1]) {
          final stopId = s['stop_id']?.toString() ?? '';
          if (stopId.isEmpty || !seen.add(stopId)) continue;
          combined.add(Stop(
            stopId: stopId,
            stopName: s['stop_name']?.toString() ?? '',
            latitude: (s['stop_lat'] as num).toDouble(),
            longitude: (s['stop_lon'] as num).toDouble(),
          ));
        }
      } else {
        // ✅ YENİ: KIBHAS/İtimat/Kombos rotası mı? kKktcBusLines'dan terminal duraklarını çek
        final kktcLine =
            kKktcBusLines.where((l) => l.id == routeId).firstOrNull;

        if (kktcLine != null) {
          // Biniş terminalini ekle
          combined.add(Stop(
            stopId: '${routeId}_from',
            stopName: kktcLine.from,
            latitude: kktcLine.fromLat,
            longitude: kktcLine.fromLon,
          ));
          // İniş terminalini ekle
          combined.add(Stop(
            stopId: '${routeId}_to',
            stopName: kktcLine.to,
            latitude: kktcLine.toLat,
            longitude: kktcLine.toLon,
          ));
          // Aynı güzergahta ara durak varsa diğer hatlardan da ekle
          // (örn. Mağusa→Ercan hattı Lefkoşa üzerinden geçiyorsa)
          for (final otherLine in kKktcBusLines) {
            if (otherLine.id == routeId) continue;
            if (otherLine.fromCity == kktcLine.fromCity ||
                otherLine.toCity == kktcLine.toCity ||
                otherLine.fromCity == kktcLine.toCity ||
                otherLine.toCity == kktcLine.fromCity) {
              final fromId = '${otherLine.id}_from';
              final toId = '${otherLine.id}_to';
              if (seen.add(fromId)) {
                combined.add(Stop(
                  stopId: fromId,
                  stopName: otherLine.from,
                  latitude: otherLine.fromLat,
                  longitude: otherLine.fromLon,
                ));
              }
              if (seen.add(toId)) {
                combined.add(Stop(
                  stopId: toId,
                  stopName: otherLine.to,
                  latitude: otherLine.toLat,
                  longitude: otherLine.toLon,
                ));
              }
            }
          }
        } else {
          // Manisa: orijinal DB'den çek
          final d1 = await _databaseService.getStopsForRouteDirection(
            routeId,
            direction: 1,
          );
          final d2 = await _databaseService.getStopsForRouteDirection(
            routeId,
            direction: 2,
          );
          for (final s in [...d1, ...d2]) {
            if (seen.add(s.stopId)) combined.add(s);
          }
        }
      }

      if (mounted) setState(() => _routeStopsForAlighting = combined);
    } catch (_) {}
  }

  // ✅ DÜZELTİLDİ: setState içinde _selectedBoardingStop kalıcı olarak set ediliyor
  // ve _calculateRoute'a forceBoardingStop olarak geçiliyor.
  // Böylece _buildRouteSummaryCard'daki displayBoardingName doğru gösteriyor.
  void _changeBoardingStop(Stop stop) {
    _boardingSearchCtrl.clear();
    setState(() {
      _selectedBoardingStop = stop;
      _selectorMode = _StopSelectorMode.none;
      _boardingSearchQuery = '';
    });

    if (_lastDestLat != null &&
        _lastDestLon != null &&
        _destinationName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateRoute(
          destinationLat: _lastDestLat!,
          destinationLon: _lastDestLon!,
          destinationName: _destinationName!,
          forceBoardingStop: stop,
        );
      });
    }
  }

  void _resetBoardingStop() {
    setState(() {
      _selectedBoardingStop = null;
      _selectorMode = _StopSelectorMode.none;
    });
    if (_lastDestLat != null &&
        _lastDestLon != null &&
        _destinationName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateRoute(
          destinationLat: _lastDestLat!,
          destinationLon: _lastDestLon!,
          destinationName: _destinationName!,
        );
      });
    }
  }

  void _changeAlightingStop(Stop stop) {
    _alightingSearchCtrl.clear();
    setState(() {
      _selectedAlightingStop = stop;
      _selectorMode = _StopSelectorMode.none;
      _alightingSearchQuery = '';

      RouteResult _rebuildWithAlighting(RouteResult r) {
        final walkFrom = _calculateDistance(
          stop.latitude,
          stop.longitude,
          _lastDestLat ?? stop.latitude,
          _lastDestLon ?? stop.longitude,
        );
        return RouteResult(
          route: r.route,
          boardingStop: r.boardingStop,
          alightingStop: stop,
          walkToStop: r.walkToStop,
          walkFromStop: walkFrom,
          rideDuration: r.rideDuration,
          totalDuration: r.totalDuration,
          nextDeparture: r.nextDeparture,
          isOperating: r.isOperating,
        );
      }

      _activeResults = _activeResults.map(_rebuildWithAlighting).toList();
      _expiredResults = _expiredResults.map(_rebuildWithAlighting).toList();
    });
  }

  void _resetAlightingStop() {
    setState(() {
      _selectedAlightingStop = null;
      _selectorMode = _StopSelectorMode.none;
    });
    if (_lastDestLat != null &&
        _lastDestLon != null &&
        _destinationName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateRoute(
          destinationLat: _lastDestLat!,
          destinationLon: _lastDestLon!,
          destinationName: _destinationName!,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = OperatingHours.getStatus();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nereye Gitmek İstiyorsunuz?'),
        actions: [
          if (!status.isOperating || status.showWarning)
            IconButton(
              icon: Icon(
                  status.isOperating
                      ? Icons.warning_amber_rounded
                      : Icons.nightlight_round,
                  color: status.color == 'red' ? Colors.red : Colors.orange),
              onPressed: () => showOperatingHoursDialog(context),
            ),
        ],
      ),
      body: Column(
        children: [
          const OperatingHoursWarning(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Yer veya durak ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          setState(() {
                            _activeResults = [];
                            _expiredResults = [];
                            _errorMessage = null;
                            _selectorMode = _StopSelectorMode.none;
                          });
                        })
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _isCalculating
                ? const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('En iyi rotalar hesaplanıyor...')
                      ]))
                : _hasResults
                    ? _buildRouteResults(theme)
                    : _errorMessage != null || _fallbackSuggestion != null
                        ? _buildErrorView(theme)
                        : _buildSearchResults(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    final isWalkingSuggestion =
        _fallbackSuggestion != null && _fallbackSuggestion!.contains('🚶');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 32),
        Card(
            color: isWalkingSuggestion
                ? Colors.green.withOpacity(0.1)
                : Colors.orange.withOpacity(0.1),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          isWalkingSuggestion
                              ? Icons.directions_walk
                              : Icons.info_outline,
                          color: isWalkingSuggestion
                              ? Colors.green
                              : Colors.orange,
                          size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                        _fallbackSuggestion ??
                            _errorMessage ??
                            'Bir hata oluştu',
                        style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: isWalkingSuggestion
                                ? Colors.green.shade800
                                : Colors.orange.shade800),
                      ))
                    ]))),
        const SizedBox(height: 24),
        if (isWalkingSuggestion) ...[
          OutlinedButton.icon(
              onPressed: () => setState(() {
                    _errorMessage = null;
                    _fallbackSuggestion = null;
                    _activeResults = [];
                    _expiredResults = [];
                  }),
              icon: const Icon(Icons.search),
              label: const Text('Farklı Yer Ara')),
        ] else
          OutlinedButton.icon(
              onPressed: () => setState(() {
                    _errorMessage = null;
                    _fallbackSuggestion = null;
                    _activeResults = [];
                    _expiredResults = [];
                  }),
              icon: const Icon(Icons.search),
              label: const Text('Yeni Arama')),
      ]),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    final navBottom = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, navBottom),
      children: [
        Consumer<FavoritesProvider>(
          builder: (context, favorites, _) {
            if (favorites.favoritePlaces.isEmpty)
              return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(Icons.star_rounded,
                        size: 18, color: Colors.amber.shade600),
                    const SizedBox(width: 8),
                    Text('Favori Yerlerim',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.amber.shade700,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: favorites.favoritePlaces.length,
                    itemBuilder: (context, index) {
                      final place = favorites.favoritePlaces[index];
                      return GestureDetector(
                        onTap: () => _calculateRoute(
                            destinationLat: place.latitude,
                            destinationLon: place.longitude,
                            destinationName: place.name),
                        child: Container(
                          width: 120,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.star_rounded,
                                  size: 20, color: Colors.amber.shade600),
                              const Spacer(),
                              Text(place.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        if (_filteredPlaces.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_isSearching ? 'Bulunan Yerler' : 'Popüler Yerler',
                style:
                    theme.textTheme.titleSmall?.copyWith(color: Colors.grey)),
          ),
          ..._filteredPlaces.map((place) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.primary.withOpacity(0.1),
                      child:
                          Icon(place.icon, color: theme.colorScheme.primary)),
                  title: Text(place.name),
                  subtitle: Text(place.category),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Consumer<FavoritesProvider>(
                        builder: (context, favorites, _) {
                          final isFavorite =
                              favorites.isPlaceFavorite(place.id);
                          return IconButton(
                            icon: Icon(
                                isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: isFavorite
                                    ? Colors.amber
                                    : Colors.grey.shade400),
                            onPressed: () {
                              favorites.togglePlaceFavorite(
                                  id: place.id,
                                  name: place.name,
                                  category: place.category,
                                  latitude: place.latitude,
                                  longitude: place.longitude);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(isFavorite
                                    ? '${place.name} favorilerden kaldırıldı'
                                    : '${place.name} favorilere eklendi'),
                                duration: const Duration(seconds: 2),
                              ));
                            },
                          );
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _onPlaceSelected(place),
                ),
              )),
        ],
        if (_filteredStops.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Duraklar',
                style:
                    theme.textTheme.titleSmall?.copyWith(color: Colors.grey)),
          ),
          ..._filteredStops.map((stop) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.secondary.withOpacity(0.1),
                      child: Icon(Icons.directions_bus,
                          color: theme.colorScheme.secondary)),
                  title: Text(stop.stopName,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Durak'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Consumer<FavoritesProvider>(
                        builder: (context, favorites, _) {
                          final isFavorite =
                              favorites.isStopFavorite(stop.stopId);
                          return IconButton(
                            icon: Icon(
                                isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: isFavorite
                                    ? Colors.amber
                                    : Colors.grey.shade400),
                            onPressed: () {
                              favorites.toggleStopFavorite(stop);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(isFavorite
                                    ? '${stop.stopName} favorilerden kaldırıldı'
                                    : '${stop.stopName} favorilere eklendi'),
                                duration: const Duration(seconds: 2),
                              ));
                            },
                          );
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _onStopSelected(stop),
                ),
              )),
        ],
        if (_isSearching && _filteredPlaces.isEmpty && _filteredStops.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.search_off, size: 48, color: theme.disabledColor),
              const SizedBox(height: 16),
              const Text('Sonuç bulunamadı'),
            ]),
          ),
      ],
    );
  }

  Widget _buildRouteResults(ThemeData theme) {
    final status = OperatingHours.getStatus();
    final navBottom = MediaQuery.of(context).padding.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBottom + 16),
      children: [
        if (!status.isOperating)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'Bu rotalar bilgi amaçlıdır. Şu an otobüsler çalışmıyor.',
                      style: TextStyle(
                          color: Colors.orange.shade700, fontSize: 13))),
            ]),
          ),
        if (_selectorMode == _StopSelectorMode.boarding)
          _buildBoardingStopSelector(theme)
        else if (_selectorMode == _StopSelectorMode.alighting)
          _buildStopSelectorCard(
            theme: theme,
            title: 'İniş Durağı Seçin',
            icon: Icons.exit_to_app,
            stops: _routeStopsForAlighting,
            selectedStop: _selectedAlightingStop,
            onStopTap: _changeAlightingStop,
            onReset:
                _selectedAlightingStop != null ? _resetAlightingStop : null,
            searchController: _alightingSearchCtrl,
            searchQuery: _alightingSearchQuery,
            onSearchChanged: (q) => setState(() => _alightingSearchQuery = q),
            onClose: () => setState(() {
              _selectorMode = _StopSelectorMode.none;
              _alightingSearchQuery = '';
              _alightingSearchCtrl.clear();
            }),
            // ✅ DÜZELTİLDİ: Liste boş değilse yükleniyor mesajı gösterme
            emptyMessage: _routeStopsForAlighting.isEmpty
                ? 'Güzergah durakları yükleniyor...'
                : 'Durak bulunamadı.',
          )
        else if (_routeResults.isNotEmpty)
          _buildRouteSummaryCard(theme),
        const SizedBox(height: 16),
        // ✅ Seçilen KIBHAS durağına yakın diğer duraklar (Sabancı → DAÜ, Üst Geçit)
        if (_nearbyKibhasStops.isNotEmpty &&
            _selectedBoardingStop != null &&
            KktcBusService.instance
                .isKibhasStop(_selectedBoardingStop!.stopId)) ...[
          _KibhasNearbyStopsBar(
            stops: _nearbyKibhasStops,
            onStopTap: _changeBoardingStop,
          ),
          const SizedBox(height: 12),
        ],
        if (_activeResults.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.directions_bus,
            title: 'Aktif Seferler',
            count: _activeResults.length,
            color: Colors.green,
          ),
          const SizedBox(height: 10),
          ..._activeResults.map((result) => _RouteResultCard(
              result: result,
              isOperating: true,
              onTap: () => _showRouteDetail(result))),
        ],
        if (_expiredResults.isNotEmpty) ...[
          if (_activeResults.isNotEmpty) ...[
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                  child: Divider(color: Colors.grey.shade400, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.history,
                      size: 20, color: Colors.grey.shade600),
                ),
              ),
              Expanded(
                  child: Divider(color: Colors.grey.shade400, thickness: 1)),
            ]),
            const SizedBox(height: 16),
          ],
          _SectionHeader(
            icon: Icons.schedule_outlined,
            title: 'Maalesef Şu An Sefer Yok',
            count: _expiredResults.length,
            color: Colors.red,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Aşağıdaki hatların bugünkü son seferleri tamamlanmıştır.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.red.shade600),
            ),
          ),
          ..._expiredResults.map((result) => _ExpiredRouteCard(result: result)),
        ],
        if (_transferResults.isNotEmpty) ...[
          if (_activeResults.isNotEmpty || _expiredResults.isNotEmpty) ...[
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                  child: Divider(color: Colors.blue.shade200, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.swap_horiz,
                      size: 20, color: Colors.blue.shade600),
                ),
              ),
              Expanded(
                  child: Divider(color: Colors.blue.shade200, thickness: 1)),
            ]),
            const SizedBox(height: 16),
          ],
          _SectionHeader(
            icon: Icons.swap_horiz,
            title: 'Aktarmalı Seçenekler',
            count: _transferResults.length,
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Bir aktarma yaparak hedefinize ulaşabilirsiniz.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.blue.shade700),
            ),
          ),
          ..._transferResults.map((t) => _TransferRouteCard(data: t)),
        ],
        if (_alternativeStops.isNotEmpty &&
            _activeResults.isEmpty &&
            _transferResults.isEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lightbulb_outline,
                      color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text('Yakın Durak Önerisi',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800)),
                ]),
                const SizedBox(height: 8),
                Text(
                  _fallbackSuggestion ??
                      'Bu durağa sefer yok, yakındaki alternatifleri deneyin:',
                  style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                ),
                const SizedBox(height: 12),
                ..._alternativeStops.map((stop) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.amber.shade100,
                        child: Icon(Icons.directions_bus,
                            color: Colors.amber.shade700, size: 18),
                      ),
                      title: Text(stop.stopName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        stop.distanceFromUser != null
                            ? '${stop.distanceFromUser!.toInt()} m yürüme'
                            : '',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () => _changeBoardingStop(stop),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child:
                            const Text('Seç', style: TextStyle(fontSize: 12)),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRouteSummaryCard(ThemeData theme) {
    final firstResult = _activeResults.isNotEmpty
        ? _activeResults.first
        : _expiredResults.first;

    // ✅ DÜZELTİLDİ: Manuel seçildiyse _selectedBoardingStop'u göster,
    // yoksa DB'den gelen boardingStop'u göster
    final displayBoardingName =
        _selectedBoardingStop?.stopName ?? firstResult.boardingStop.stopName;
    final displayAlightingName =
        _selectedAlightingStop?.stopName ?? firstResult.alightingStop.stopName;

    return Card(
      color: theme.colorScheme.primary.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.primary.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StopRow(
              icon: Icons.my_location,
              iconColor: theme.colorScheme.primary,
              label: 'Biniş Durağı',
              stopName: displayBoardingName,
              isManual: _selectedBoardingStop != null,
              onTap: () =>
                  setState(() => _selectorMode = _StopSelectorMode.boarding),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
              child: Icon(Icons.arrow_downward,
                  size: 18, color: Colors.grey.shade400),
            ),
            _StopRow(
              icon: Icons.flag,
              iconColor: Colors.red,
              label: 'İniş Durağı',
              stopName: displayAlightingName,
              isManual: _selectedAlightingStop != null,
              onTap: () => setState(() {
                _selectorMode = _StopSelectorMode.alighting;
                // ✅ DÜZELTİLDİ: İniş durağı paneli açılınca liste zaten yüklü,
                // yoksa ilk rota için yükle
                if (_routeStopsForAlighting.isEmpty &&
                    _activeResults.isNotEmpty) {
                  _loadRouteStopsForAlighting(
                      _activeResults.first.route.routeId);
                }
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
              child: Icon(Icons.arrow_downward,
                  size: 18, color: Colors.grey.shade400),
            ),
            Row(children: [
              const Icon(Icons.location_on, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hedef',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(_destinationName ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ✅ YENİ: Biniş durağı seçici — 2 sekme: Yakın Duraklar / KIBHAS
  Widget _buildBoardingStopSelector(ThemeData theme) {
    // Tüm KIBHAS durakları: kAllKibhasStops + seçili hattın durakları
    final allKibhasStops = <Stop>[];
    final seenIds = <String>{};
    // kAllKibhasStops'tan terminal duraklar
    for (final ks in kAllKibhasStops) {
      if (seenIds.add(ks.stopId)) {
        allKibhasStops.add(Stop(
          stopId: ks.stopId,
          stopName: ks.stopName,
          latitude: ks.lat,
          longitude: ks.lon,
        ));
      }
    }
    // Aktif rotanın tam durak listesi (güzergah bazlı)
    if (_activeResults.isNotEmpty) {
      final routeId = _activeResults.first.route.routeId;
      final line = kKktcBusLines.where((l) => l.id == routeId).firstOrNull;
      if (line != null) {
        for (final ks in line.stops) {
          if (seenIds.add(ks.stopId)) {
            allKibhasStops.add(Stop(
              stopId: ks.stopId,
              stopName: ks.stopName,
              latitude: ks.lat,
              longitude: ks.lon,
            ));
          }
        }
      }
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Row(children: [
              Icon(Icons.directions_walk, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Biniş Durağı Seçin',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectorMode = _StopSelectorMode.none;
                  _boardingSearchQuery = '';
                  _boardingSearchCtrl.clear();
                }),
              ),
            ]),
            const Divider(),
            // ✅ 2 Sekme
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _boardingTabIndex = 0;
                    _boardingSearchQuery = '';
                    _boardingSearchCtrl.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _boardingTabIndex == 0
                          ? theme.colorScheme.primary
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_on,
                            size: 16,
                            color: _boardingTabIndex == 0
                                ? Colors.white
                                : Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('Yakın Duraklar',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _boardingTabIndex == 0
                                    ? Colors.white
                                    : Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _boardingTabIndex = 1;
                    _boardingSearchQuery = '';
                    _boardingSearchCtrl.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _boardingTabIndex == 1
                          ? const Color(0xFF1565C0)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_bus,
                            size: 16,
                            color: _boardingTabIndex == 1
                                ? Colors.white
                                : Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('KIBHAS',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _boardingTabIndex == 1
                                    ? Colors.white
                                    : Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // Otomatik seç butonu
            if (_selectedBoardingStop != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton.icon(
                  onPressed: _resetBoardingStop,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Otomatik Seç (Önerilen)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
            // Arama kutusu
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _boardingSearchCtrl,
                decoration: InputDecoration(
                  hintText: _boardingTabIndex == 0
                      ? 'Durak adı ara...'
                      : 'KIBHAS durağı ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _boardingSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _boardingSearchCtrl.clear();
                            setState(() => _boardingSearchQuery = '');
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  isDense: true,
                ),
                onChanged: (q) => setState(() => _boardingSearchQuery = q),
              ),
            ),
            // Liste
            Builder(builder: (context) {
              final stops =
                  _boardingTabIndex == 0 ? _nearbyStops : allKibhasStops;
              final q = _boardingSearchQuery
                  .trim()
                  .toLowerCase()
                  .replaceAll('ı', 'i')
                  .replaceAll('ğ', 'g')
                  .replaceAll('ü', 'u')
                  .replaceAll('ş', 's')
                  .replaceAll('ö', 'o')
                  .replaceAll('ç', 'c');
              final filtered = q.isEmpty
                  ? stops
                  : stops.where((s) {
                      final n = s.stopName
                          .toLowerCase()
                          .replaceAll('ı', 'i')
                          .replaceAll('ğ', 'g')
                          .replaceAll('ü', 'u')
                          .replaceAll('ş', 's')
                          .replaceAll('ö', 'o')
                          .replaceAll('ç', 'c');
                      return n.contains(q);
                    }).toList();

              if (stops.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      _boardingTabIndex == 0
                          ? 'Yakında durak bulunamadı.'
                          : 'KIBHAS durağı bulunamadı.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.search_off,
                          size: 32, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('"$_boardingSearchQuery" ile eşleşen durak yok',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13)),
                    ]),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.isEmpty
                        ? 'Duraklar (${filtered.length})'
                        : '${filtered.length} sonuç',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final stop = filtered[index];
                        final isSelected =
                            _selectedBoardingStop?.stopId == stop.stopId;
                        final distance = stop.distanceFromUser ?? 0;
                        final isKibhas =
                            KktcBusService.instance.isKibhasStop(stop.stopId);
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor:
                              theme.colorScheme.primary.withOpacity(0.1),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected
                                ? theme.colorScheme.primary
                                : isKibhas
                                    ? const Color(0xFF1565C0).withOpacity(0.15)
                                    : Colors.grey.shade200,
                            child: Icon(
                                isKibhas
                                    ? Icons.directions_bus
                                    : Icons.location_on,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : isKibhas
                                        ? const Color(0xFF1565C0)
                                        : Colors.grey),
                          ),
                          title: Text(
                            stop.stopName.replaceAll('KIBHAS — ', ''),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: distance > 0
                              ? Text(
                                  distance < 1000
                                      ? '${distance.toInt()} m'
                                      : '${(distance / 1000).toStringAsFixed(1)} km',
                                  style: const TextStyle(fontSize: 11),
                                )
                              : isKibhas
                                  ? Text('KIBHAS',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: const Color(0xFF1565C0)))
                                  : null,
                          trailing: isSelected
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : null,
                          onTap: () => _changeBoardingStop(stop),
                        );
                      },
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStopSelectorCard({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required List<Stop> stops,
    required Stop? selectedStop,
    required void Function(Stop) onStopTap,
    required VoidCallback? onReset,
    required VoidCallback onClose,
    required String emptyMessage,
    required TextEditingController searchController,
    required String searchQuery,
    required void Function(String) onSearchChanged,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ]),
            const Divider(),
            if (onReset != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Otomatik Seç (Önerilen)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Durak adı ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  isDense: true,
                ),
                onChanged: onSearchChanged,
              ),
            ),
            Builder(builder: (context) {
              final q = searchQuery
                  .trim()
                  .toLowerCase()
                  .replaceAll('ı', 'i')
                  .replaceAll('ğ', 'g')
                  .replaceAll('ü', 'u')
                  .replaceAll('ş', 's')
                  .replaceAll('ö', 'o')
                  .replaceAll('ç', 'c');
              final filtered = q.isEmpty
                  ? stops
                  : stops.where((s) {
                      final n = s.stopName
                          .toLowerCase()
                          .replaceAll('ı', 'i')
                          .replaceAll('ğ', 'g')
                          .replaceAll('ü', 'u')
                          .replaceAll('ş', 's')
                          .replaceAll('ö', 'o')
                          .replaceAll('ç', 'c');
                      return n.contains(q);
                    }).toList();

              if (stops.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: Text(emptyMessage,
                          style: const TextStyle(color: Colors.grey))),
                );
              }
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.search_off,
                          size: 32, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('"$searchQuery" ile eşleşen durak yok',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13)),
                    ]),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.isEmpty
                        ? 'Duraklar (${filtered.length})'
                        : '${filtered.length} sonuç',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final stop = filtered[index];
                        final isSelected = selectedStop?.stopId == stop.stopId;
                        final distance = stop.distanceFromUser ?? 0;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor:
                              theme.colorScheme.primary.withOpacity(0.1),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected
                                ? theme.colorScheme.primary
                                : Colors.grey.shade200,
                            child: Icon(Icons.directions_bus,
                                size: 16,
                                color: isSelected ? Colors.white : Colors.grey),
                          ),
                          title: Text(stop.stopName,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: distance > 0
                              ? Text(
                                  distance < 1000
                                      ? '${distance.toInt()} m'
                                      : '${(distance / 1000).toStringAsFixed(1)} km',
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          trailing: isSelected
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : null,
                          onTap: () => onStopTap(stop),
                        );
                      },
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showRouteDetail(RouteResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _RouteDetailSheet(
          result: result, destinationName: _destinationName ?? ''),
    );
  }

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
}

class _StopRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String stopName;
  final bool isManual;
  final VoidCallback onTap;

  const _StopRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.stopName,
    required this.isManual,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 12, color: Colors.grey.shade500),
              ]),
              Text(stopName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (isManual)
                Text('Manuel seçim',
                    style: TextStyle(
                        fontSize: 10, color: theme.colorScheme.primary)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.swap_horiz,
                  size: 13, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text('Değiştir',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final MaterialColor color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(children: [
        Icon(icon, size: 22, color: color.shade700),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold, color: color.shade700)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: color.shade700, borderRadius: BorderRadius.circular(12)),
          child: Text('$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
      ]),
    );
  }
}

class _ExpiredRouteCard extends StatelessWidget {
  final RouteResult result;
  const _ExpiredRouteCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Opacity(
        opacity: 0.65,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(result.route.routeShortName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.route.routeLongName,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                      '${result.boardingStop.stopName} → ${result.alightingStop.stopName}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.block, size: 13, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Text('Bugünkü seferler sona erdi',
                        style: TextStyle(
                            fontSize: 11, color: Colors.red.shade400)),
                  ]),
                ],
              ),
            ),
            Icon(Icons.schedule, color: Colors.grey.shade400, size: 24),
          ]),
        ),
      ),
    );
  }
}

class _RouteResultCard extends StatelessWidget {
  final RouteResult result;
  final bool isOperating;
  final VoidCallback onTap;

  const _RouteResultCard(
      {required this.result, required this.isOperating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: result.route.color,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(result.route.routeShortName,
                      style: TextStyle(
                          color: result.route.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(result.route.routeLongName,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          '${result.boardingStop.stopName} → ${result.alightingStop.stopName}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ])),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(children: [
                _InfoChip(
                    icon: Icons.timer,
                    label: '${result.totalDuration} dk',
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                _InfoChip(
                    icon: Icons.directions_walk,
                    label: result.formattedWalkToStop,
                    color: Colors.blue),
                const SizedBox(width: 8),
                if (result.nextDeparture != null)
                  _InfoChip(
                      icon: Icons.access_time,
                      label: result.nextDeparture!,
                      color: Colors.green),
                const Spacer(),
                Icon(Icons.chevron_right, color: theme.disabledColor),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w500, fontSize: 12)),
      ]),
    );
  }
}

class _RouteDetailSheet extends StatelessWidget {
  final RouteResult result;
  final String destinationName;

  const _RouteDetailSheet(
      {required this.result, required this.destinationName});

  void _startNavigation(BuildContext context) {
    final trip = ActiveTrip(
      route: result.route,
      boardingStop: result.boardingStop,
      alightingStop: result.alightingStop,
      destinationName: destinationName,
      nextDeparture: result.nextDeparture,
    );
    Navigator.pop(context);
    Navigator.pushNamed(
      context,
      AppRoutes.navigation,
      arguments: {'trip': trip},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final walkingTimeToStop = (result.walkToStop / 80).round();
    final walkingTimeFromStop = (result.walkFromStop / 80).round();
    final status = OperatingHours.getStatus();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final navBottom = MediaQuery.of(context).padding.bottom;
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + navBottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                if (!status.isOperating)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300)),
                    child: Row(children: [
                      Icon(Icons.nightlight_round,
                          color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(status.title,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700)),
                            Text(status.message,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade600)),
                          ])),
                    ]),
                  ),
                Row(children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          color: result.route.color,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(result.route.routeShortName,
                          style: TextStyle(
                              color: result.route.textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 20))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(result.route.routeLongName,
                          style: theme.textTheme.titleMedium)),
                ]),
                const SizedBox(height: 24),
                _StepItem(
                    icon: Icons.directions_walk,
                    iconColor: Colors.blue,
                    title: 'Yürüyün',
                    subtitle: '${result.boardingStop.stopName} durağına gidin',
                    detail:
                        '${result.formattedWalkToStop} • ~$walkingTimeToStop dk'),
                _StepItem(
                    icon: Icons.directions_bus,
                    iconColor: result.route.color,
                    title: '${result.route.routeShortName} hattına binin',
                    subtitle: result.nextDeparture != null && status.isOperating
                        ? 'Sonraki kalkış: ${result.nextDeparture}'
                        : 'Sefer bilgisi yok',
                    detail: '~${result.rideDuration} dk otobüs yolculuğu'),
                _StepItem(
                    icon: Icons.exit_to_app,
                    iconColor: Colors.orange,
                    title: '${result.alightingStop.stopName} durağında inin',
                    subtitle: 'İniş durağınız',
                    detail: null),
                if (result.walkFromStop > 50)
                  _StepItem(
                      icon: Icons.directions_walk,
                      iconColor: Colors.blue,
                      title: 'Hedefe yürüyün',
                      subtitle: destinationName,
                      detail:
                          '${result.formattedWalkFromStop} • ~$walkingTimeFromStop dk',
                      isLast: true)
                else
                  _StepItem(
                      icon: Icons.location_on,
                      iconColor: Colors.red,
                      title: 'Hedefinize ulaştınız',
                      subtitle: destinationName,
                      detail: null,
                      isLast: true),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _SummaryItem(
                            icon: Icons.timer,
                            label: 'Toplam',
                            value: '~${result.totalDuration} dk'),
                        _SummaryItem(
                            icon: Icons.directions_walk,
                            label: 'Yürüme',
                            value: result.formattedWalkToStop),
                        _SummaryItem(
                            icon: Icons.directions_bus,
                            label: 'Otobüs',
                            value: '~${result.rideDuration} dk'),
                      ]),
                ),
                const SizedBox(height: 24),
                if (result.isOperating && result.nextDeparture != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _startNavigation(context),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Navigasyonu Başlat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (result.isOperating && result.nextDeparture != null)
                  const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tamam'))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StepItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? detail;
  final bool isLast;

  const _StepItem(
      {required this.icon,
      required this.iconColor,
      required this.title,
      required this.subtitle,
      this.detail,
      this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20)),
          if (!isLast) Container(width: 2, height: 50, color: Colors.grey[300]),
        ]),
        const SizedBox(width: 12),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: const TextStyle(color: Colors.grey)),
                      if (detail != null)
                        Text(detail!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ]))),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    ]);
  }
}

class _TransferRouteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TransferRouteCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstRoute = data['firstRoute'] as TransitRoute;
    final secondRoute = data['secondRoute'] as TransitRoute;
    final boardingStop = data['boardingStop'] as Stop;
    final transferStop = data['transferStop'] as Stop;
    final alightingStop = data['alightingStop'] as Stop;
    final totalDuration = data['totalDuration'] as int;
    final dep1 = data['nextDeparture1'] as String?;
    final dep2 = data['nextDeparture2'] as String?;
    final isOp1 = data['isOperating1'] as bool? ?? false;
    final isOp2 = data['isOperating2'] as bool? ?? false;
    final isActive = isOp1 && isOp2;
    final walkToStop = data['walkToStop'] as double;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: isActive ? Colors.blue.shade200 : Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _RouteChip(route: firstRoute, isActive: isActive),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              _RouteChip(route: secondRoute, isActive: isActive),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$totalDuration dk',
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 10),
            _TransferStep(
              icon: Icons.directions_walk,
              color: Colors.blue,
              label: boardingStop.stopName,
              sub: walkToStop < 1000
                  ? '${walkToStop.toInt()} m yürüme'
                  : '${(walkToStop / 1000).toStringAsFixed(1)} km yürüme',
            ),
            _TransferStep(
              icon: Icons.directions_bus,
              color: firstRoute.color,
              label:
                  'Hat ${firstRoute.routeShortName} → ${transferStop.stopName}',
              sub: dep1 != null && isOp1 ? 'Kalkış: $dep1' : 'Sefer yok',
              subColor: isOp1 ? Colors.green.shade700 : Colors.red.shade400,
            ),
            _TransferStep(
              icon: Icons.swap_horiz,
              color: Colors.orange,
              label: 'Aktarma: ${transferStop.stopName}',
              sub: dep2 != null && isOp2
                  ? 'Hat ${secondRoute.routeShortName} — $dep2'
                  : 'Hat ${secondRoute.routeShortName} — sefer yok',
              subColor: isOp2 ? Colors.green.shade700 : Colors.red.shade400,
            ),
            _TransferStep(
              icon: Icons.flag,
              color: Colors.red,
              label: alightingStop.stopName,
              sub: 'İniş durağı',
              isLast: true,
            ),
            if (!isActive)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    !isOp1
                        ? 'Hat ${firstRoute.routeShortName} için bugün sefer yok'
                        : 'Hat ${secondRoute.routeShortName} için bugün sefer yok',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade700),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  final TransitRoute route;
  final bool isActive;
  const _RouteChip({required this.route, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive ? route.color : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(route.routeShortName,
          style: TextStyle(
              color: isActive ? route.textColor : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14)),
    );
  }
}

class _TransferStep extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sub;
  final Color? subColor;
  final bool isLast;

  const _TransferStep({
    required this.icon,
    required this.color,
    required this.label,
    required this.sub,
    this.subColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 15),
          ),
          if (!isLast)
            Container(width: 2, height: 30, color: Colors.grey.shade200),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11, color: subColor ?? Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// Seçilen KIBHAS durağına yakın diğer durakları gösteren yatay bant
// ──────────────────────────────────────────────────────────────────
class _KibhasNearbyStopsBar extends StatelessWidget {
  final List<Stop> stops;
  final void Function(Stop) onStopTap;

  const _KibhasNearbyStopsBar({
    required this.stops,
    required this.onStopTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stops.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.directions_bus_filled,
                size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Text(
              'Bu hattaki diğer duraklar',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stops.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final stop = stops[index];
              final dist = stop.distanceFromUser ?? 0;
              final distLabel = dist < 1000
                  ? '${dist.toInt()} m'
                  : '${(dist / 1000).toStringAsFixed(1)} km';
              return GestureDetector(
                onTap: () => onStopTap(stop),
                child: Container(
                  width: 130,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stop.stopName
                            .replaceAll('KIBHAS — ', '')
                            .replaceAll('KIBHAS - ', ''),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        distLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
