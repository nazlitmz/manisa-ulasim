import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/stop_model.dart';
import '../models/route_model.dart';
import '../providers/location_provider.dart';
import '../providers/stops_provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/tts_service.dart';
import '../services/database_service.dart';
import '../config/constants.dart';
import '../config/api_config.dart';

class NearbyStopsScreen extends StatefulWidget {
  const NearbyStopsScreen({super.key});

  @override
  State<NearbyStopsScreen> createState() => _NearbyStopsScreenState();
}

class _NearbyStopsScreenState extends State<NearbyStopsScreen> {
  final TtsService _ttsService = TtsService();
  final DatabaseService _databaseService = DatabaseService();
  final MapController _mapController = MapController();

  bool _isLoading = true;
  bool _isMapView = false;
  int _selectedRadius = 500;

  final List<int> _radiusOptions = [250, 500, 750, 1000, 1500];

  Stop? _selectedStop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearbyStops());
  }

  Future<void> _loadNearbyStops() async {
    setState(() => _isLoading = true);

    try {
      final locationProvider = context.read<LocationProvider>();
      final stopsProvider = context.read<StopsProvider>();

      final location = locationProvider.effectiveLocation;
      await stopsProvider.findNearbyStops(
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters: _selectedRadius.toDouble(),
      );

      setState(() => _isLoading = false);
      _announceResults();
    } catch (e) {
      debugPrint('❌ Duraklar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _announceResults() async {
    final accessibility = context.read<AccessibilityProvider>();
    if (!accessibility.screenReaderEnabled) return;

    final stopsProvider = context.read<StopsProvider>();
    final count = stopsProvider.nearbyStops.length;

    if (count > 0) {
      final firstStop = stopsProvider.nearbyStops.first;
      final distance = firstStop.distanceFromUser?.toInt() ?? 0;
      await _ttsService.speak(
          'Yakındaki duraklar ekranı. $_selectedRadius metre içinde $count durak bulundu. '
          'En yakın durak ${firstStop.stopName}, $distance metre uzaklıkta.');
    } else {
      await _ttsService.speak(
          'Yakındaki duraklar ekranı. $_selectedRadius metre içinde durak bulunamadı.');
    }
  }

  Future<void> _openInGoogleMaps(dynamic stop) async {
    final locationProvider = context.read<LocationProvider>();
    final userLocation = locationProvider.effectiveLocation;

    final double destLat = stop.latitude;
    final double destLon = stop.longitude;

    final url = Uri.parse('${ApiConfig.googleMapsDirectionsUrl}'
        '&origin=${userLocation.latitude},${userLocation.longitude}'
        '&destination=$destLat,$destLon'
        '&travelmode=walking');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final fallbackUrl = Uri.parse(
            '${ApiConfig.googleMapsSearchUrl}&query=$destLat,$destLon');
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harita uygulaması açılamadı')),
        );
      }
    }
  }

  void _fitMapToStops() {
    final stopsProvider = context.read<StopsProvider>();
    final locationProvider = context.read<LocationProvider>();
    final stops = stopsProvider.nearbyStops;

    if (stops.isEmpty) return;

    final userLocation = locationProvider.effectiveLocation;

    double minLat = userLocation.latitude;
    double maxLat = userLocation.latitude;
    double minLon = userLocation.longitude;
    double maxLon = userLocation.longitude;

    for (final stop in stops) {
      if (stop.latitude < minLat) minLat = stop.latitude;
      if (stop.latitude > maxLat) maxLat = stop.latitude;
      if (stop.longitude < minLon) minLon = stop.longitude;
      if (stop.longitude > maxLon) maxLon = stop.longitude;
    }

    const padding = 0.002;
    final bounds = LatLngBounds(
      LatLng(minLat - padding, minLon - padding),
      LatLng(maxLat + padding, maxLon + padding),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
    });
  }

  void _showRouteTimes(
      TransitRoute route, Stop stop, ThemeData theme, bool isDarkMode) async {
    Navigator.pop(context);

    final departureTimes = await _databaseService.getUpcomingDeparturesForStop(
      route.routeShortName,
      stop.stopId,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        // ✅ navBar yüksekliğini al
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            // ✅ alt padding: içerik navBar'ın altına kaymaz
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: route.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        route.routeShortName,
                        style: TextStyle(
                          color: route.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        route.routeLongName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        stop.stopName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Sonraki Seferler${departureTimes.isNotEmpty ? ' (${departureTimes.length})' : ''}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (departureTimes.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.schedule,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Şu anda aktif sefer bulunamadı.',
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sefer saatleri dışında olabilirsiniz.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: departureTimes.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: theme.colorScheme.primary.withOpacity(0.1),
                      ),
                      itemBuilder: (context, index) {
                        final time = departureTimes[index];
                        final isFirst = index == 0;

                        String remainingTime = '';
                        try {
                          final now = DateTime.now();
                          final parts = time.split(':');
                          if (parts.length >= 2) {
                            final hour = int.tryParse(parts[0]) ?? 0;
                            final minute = int.tryParse(parts[1]) ?? 0;
                            var adjustedHour = hour;
                            if (hour >= 24) adjustedHour = hour - 24;
                            final departureTime = DateTime(
                              now.year,
                              now.month,
                              now.day,
                              adjustedHour,
                              minute,
                            );
                            final difference = departureTime.difference(now);
                            if (difference.isNegative) {
                              remainingTime = 'Geçti';
                            } else {
                              final minutes = difference.inMinutes;
                              if (minutes < 60) {
                                remainingTime = '$minutes dk';
                              } else {
                                final hours = minutes ~/ 60;
                                final mins = minutes % 60;
                                remainingTime = '${hours}s ${mins}dk';
                              }
                            }
                          }
                        } catch (e) {
                          debugPrint('Zaman hesaplama hatası: $e');
                        }

                        return Container(
                          color: isFirst
                              ? theme.colorScheme.primary.withOpacity(0.05)
                              : null,
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isFirst
                                      ? theme.colorScheme.primary
                                      : (isDarkMode
                                          ? Colors.grey.shade800
                                          : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.access_time,
                                  color: isFirst
                                      ? Colors.white
                                      : theme.colorScheme.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      time,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isFirst
                                            ? theme.colorScheme.primary
                                            : null,
                                      ),
                                    ),
                                    if (remainingTime.isNotEmpty &&
                                        remainingTime != 'Geçti')
                                      Text(
                                        remainingTime,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: isFirst
                                              ? theme.colorScheme.primary
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isFirst)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'En yakın sefer',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sefer saatleri tahminidir. Gerçek kalkış saatleri trafik durumuna göre değişebilir.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final stopsProvider = context.watch<StopsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yakındaki Duraklar'),
        actions: [
          IconButton(
            icon: Icon(_isMapView ? Icons.list : Icons.map),
            tooltip: _isMapView ? 'Liste Görünümü' : 'Harita Görünümü',
            onPressed: () {
              setState(() => _isMapView = !_isMapView);
              if (_isMapView) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _fitMapToStops());
              }
            },
          ),
          Consumer<FavoritesProvider>(
            builder: (context, favorites, _) {
              if (favorites.favoriteStops.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: Badge(
                  label: Text('${favorites.favoriteStops.length}'),
                  child: const Icon(Icons.star_rounded),
                ),
                tooltip: 'Favori duraklar',
                onPressed: () => _showFavoriteStops(context, favorites),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNearbyStops,
            tooltip: 'Yenile',
          ),
        ],
      ),
      // ✅ SafeArea: ana ekran navBar'dan korunuyor
      body: SafeArea(
        child: Column(
          children: [
            _buildRadiusSelector(theme, isDarkMode),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : stopsProvider.nearbyStops.isEmpty
                      ? _buildEmptyState(theme)
                      : _isMapView
                          ? _buildMapView(theme, isDarkMode, stopsProvider)
                          : _buildListView(theme, isDarkMode, stopsProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadiusSelector(ThemeData theme, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Arama Mesafesi',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$_selectedRadius m',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _radiusOptions.map((radius) {
              final isSelected = radius == _selectedRadius;
              return GestureDetector(
                onTap: () {
                  if (radius != _selectedRadius) {
                    setState(() => _selectedRadius = radius);
                    _loadNearbyStops();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : (isDarkMode
                            ? Colors.grey.shade800
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    '${radius}m',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDarkMode
                              ? Colors.white70
                              : Colors.grey.shade700),
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off, size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text('$_selectedRadius m içinde durak bulunamadı'),
          const SizedBox(height: 8),
          const Text('Mesafeyi artırmayı deneyin',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadNearbyStops,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(
      ThemeData theme, bool isDarkMode, StopsProvider stopsProvider) {
    return RefreshIndicator(
      onRefresh: _loadNearbyStops,
      child: ListView.builder(
        // ✅ Liste son item'ı navBar'ın altına kaymaz
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        itemCount: stopsProvider.nearbyStops.length,
        itemBuilder: (context, index) {
          final stop = stopsProvider.nearbyStops[index];
          return _StopCard(
            stop: stop,
            isDarkMode: isDarkMode,
            onTap: () => _showStopDetail(stop),
            onNavigate: () => _openInGoogleMaps(stop),
          );
        },
      ),
    );
  }

  Widget _buildMapView(
      ThemeData theme, bool isDarkMode, StopsProvider stopsProvider) {
    final locationProvider = context.watch<LocationProvider>();
    final userLocation = locationProvider.effectiveLocation;
    // ✅ harita görünümünde seçili durak kartı navBar'a çarpmaz
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter:
                LatLng(userLocation.latitude, userLocation.longitude),
            initialZoom: 15,
            minZoom: AppConstants.minZoom,
            maxZoom: AppConstants.maxZoom,
            onTap: (_, __) {
              if (_selectedStop != null) {
                setState(() => _selectedStop = null);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: AppConstants.osmTileUrl,
              userAgentPackageName: 'com.manisa.ulasim',
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(userLocation.latitude, userLocation.longitude),
                  radius: _selectedRadius.toDouble(),
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderColor: theme.colorScheme.primary.withOpacity(0.5),
                  borderStrokeWidth: 2,
                  useRadiusInMeter: true,
                ),
              ],
            ),
            MarkerLayer(
              markers: stopsProvider.nearbyStops.map((stop) {
                final isSelected = _selectedStop?.stopId == stop.stopId;
                final distance = stop.distanceFromUser?.toInt() ?? 0;

                return Marker(
                  point: LatLng(stop.latitude, stop.longitude),
                  width: isSelected ? 50 : 40,
                  height: isSelected ? 50 : 40,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedStop = stop),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : _getDistanceColor(distance),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white, width: isSelected ? 3 : 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isSelected ? 0.4 : 0.2),
                            blurRadius: isSelected ? 8 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                        size: isSelected ? 24 : 20,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(userLocation.latitude, userLocation.longitude),
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        // ✅ Seçili durak kartı navBar'ın üzerinde durur
        if (_selectedStop != null)
          Positioned(
            bottom: bottomPadding + 16,
            left: 16,
            right: 16,
            child: _buildSelectedStopCard(theme, isDarkMode),
          ),
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'fit',
            onPressed: _fitMapToStops,
            backgroundColor:
                isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
            child: Icon(Icons.fit_screen,
                color: isDarkMode ? Colors.white : Colors.black87),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '${stopsProvider.nearbyStops.length} durak',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedStopCard(ThemeData theme, bool isDarkMode) {
    final stop = _selectedStop!;
    final distance = stop.distanceFromUser?.toInt() ?? 0;

    return Card(
      color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _getDistanceColor(distance).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_walk,
                          color: _getDistanceColor(distance), size: 18),
                      Text(
                        '${distance}m',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getDistanceColor(distance),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.stopName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '~${(distance / 80).round()} dk yürüme',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Consumer<FavoritesProvider>(
                  builder: (context, favorites, _) {
                    final isFavorite = favorites.isStopFavorite(stop.stopId);
                    return IconButton(
                      icon: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: isFavorite ? Colors.amber : Colors.grey,
                      ),
                      onPressed: () => favorites.toggleStopFavorite(stop),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _selectedStop = null);
                      _showStopDetail(stop);
                    },
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Detaylar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openInGoogleMaps(stop),
                    icon: const Icon(Icons.directions, size: 18),
                    label: const Text('Yol Tarifi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFavoriteStops(BuildContext context, FavoritesProvider favorites) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.star_rounded, color: Colors.amber.shade600),
                    const SizedBox(width: 8),
                    const Text('Favori Duraklarım',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  // ✅ navBar padding
                  padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
                  itemCount: favorites.favoriteStops.length,
                  itemBuilder: (context, index) {
                    final favStop = favorites.favoriteStops[index];
                    return Dismissible(
                      key: Key(favStop.stopId),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) =>
                          favorites.removeStopFromFavorites(favStop.stopId),
                      child: Card(
                        color:
                            isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: Icon(Icons.location_on,
                                color: Colors.green.shade700),
                          ),
                          title: Text(favStop.stopName,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: const Text('Durak'),
                          trailing: IconButton(
                            icon: const Icon(Icons.directions,
                                color: Colors.green),
                            tooltip: 'Yol Tarifi',
                            onPressed: () {
                              Navigator.pop(context);
                              _openInGoogleMaps(favStop);
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStopDetail(Stop stop) async {
    final routes = await _databaseService.getRoutesForStop(stop.stopId);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            // ✅ navBar padding
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stop.stopName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Consumer<FavoritesProvider>(
                      builder: (context, favorites, _) {
                        final isFavorite =
                            favorites.isStopFavorite(stop.stopId);
                        return IconButton(
                          icon: Icon(
                            isFavorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: isFavorite ? Colors.amber : Colors.grey,
                            size: 28,
                          ),
                          onPressed: () {
                            favorites.toggleStopFavorite(stop);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isFavorite
                                    ? '${stop.stopName} favorilerden kaldırıldı'
                                    : '${stop.stopName} favorilere eklendi'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                if (stop.distanceFromUser != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.directions_walk,
                            size: 16,
                            color: _getDistanceColor(
                                stop.distanceFromUser!.toInt())),
                        const SizedBox(width: 4),
                        Text(
                          '${stop.distanceFromUser!.toInt()} metre (~${(stop.distanceFromUser! / 80).round()} dk yürüme)',
                          style: TextStyle(
                              color: _getDistanceColor(
                                  stop.distanceFromUser!.toInt())),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openInGoogleMaps(stop),
                    icon: const Icon(Icons.directions),
                    label: const Text('Google Maps\'te Yol Tarifi Al'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Bu Duraktan Geçen Hatlar',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.directions_bus_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text('Bu duraktan geçen hat bulunamadı.',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                else
                  ...routes.map((route) => Card(
                        color:
                            isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: route.color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                route.routeShortName,
                                style: TextStyle(
                                    color: route.textColor,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          title: Text(route.routeLongName,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Consumer<FavoritesProvider>(
                                builder: (context, favorites, _) {
                                  final isFavorite =
                                      favorites.isRouteFavorite(route.routeId);
                                  return IconButton(
                                    icon: Icon(
                                      isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: isFavorite
                                          ? Colors.amber
                                          : Colors.grey.shade400,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        favorites.toggleRouteFavorite(route),
                                  );
                                },
                              ),
                              const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                          onTap: () =>
                              _showRouteTimes(route, stop, theme, isDarkMode),
                        ),
                      )),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getDistanceColor(int distance) {
    if (distance <= 200) return Colors.green;
    if (distance <= 500) return Colors.orange;
    return Colors.red;
  }
}

class _StopCard extends StatelessWidget {
  final Stop stop;
  final bool isDarkMode;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

  const _StopCard({
    required this.stop,
    required this.isDarkMode,
    required this.onTap,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distance = stop.distanceFromUser?.toInt() ?? 0;

    return Card(
      color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _getDistanceColor(distance).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_walk,
                        color: _getDistanceColor(distance), size: 20),
                    Text(
                      '${distance}m',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getDistanceColor(distance),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.stopName,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '~${(distance / 80).round()} dk yürüme',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Consumer<FavoritesProvider>(
                builder: (context, favorites, _) {
                  final isFavorite = favorites.isStopFavorite(stop.stopId);
                  return IconButton(
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: isFavorite ? Colors.amber : Colors.grey.shade400,
                    ),
                    onPressed: () {
                      favorites.toggleStopFavorite(stop);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isFavorite
                              ? '${stop.stopName} favorilerden kaldırıldı'
                              : '${stop.stopName} favorilere eklendi'),
                          duration: const Duration(seconds: 2),
                          action: SnackBarAction(
                            label: 'Geri Al',
                            onPressed: () => favorites.toggleStopFavorite(stop),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.directions, color: Colors.green),
                tooltip: 'Yol Tarifi',
                onPressed: onNavigate,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getDistanceColor(int distance) {
    if (distance <= 200) return Colors.green;
    if (distance <= 500) return Colors.orange;
    return Colors.red;
  }
}
