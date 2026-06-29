import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../models/stop_model.dart';
import '../models/route_model.dart';
import '../services/navigation_service.dart';
import '../providers/location_provider.dart';
import '../config/api_config.dart';

class TripNavigationScreen extends StatefulWidget {
  const TripNavigationScreen({super.key});

  @override
  State<TripNavigationScreen> createState() => _TripNavigationScreenState();
}

class _TripNavigationScreenState extends State<TripNavigationScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  ActiveTrip? _trip;
  bool _mapFollowsUser = true;
  bool _initialized = false;

  List<LatLng> _walkPolyline = [];
  List<LatLng> _busPolyline = [];
  bool _polylinesLoading = false;

  StreamSubscription<MapEvent>? _mapEventSubscription;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );

    // onPositionChanged sürümler arası uyumsuz → mapEventStream kullan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapEventSubscription =
          _mapController.mapEventStream.listen((MapEvent event) {
        if (event is MapEventMoveStart &&
            event.source == MapEventSource.dragStart) {
          if (_mapFollowsUser) setState(() => _mapFollowsUser = false);
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _trip = args['trip'] as ActiveTrip?;
        if (_trip != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<NavigationService>().startNavigation(_trip!);
            _loadPolylines();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _mapEventSubscription?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Polyline yükleme
  // ─────────────────────────────────────────────────────────

  Future<void> _loadPolylines() async {
    final trip = _trip;
    if (trip == null) return;

    setState(() => _polylinesLoading = true);

    try {
      final locationProvider = context.read<LocationProvider>();
      final userLoc = locationProvider.currentLocation ??
          locationProvider.effectiveLocation;

      final walkPoints = await _fetchOsrmRoute(
        fromLat: userLoc.latitude,
        fromLon: userLoc.longitude,
        toLat: trip.boardingStop.latitude,
        toLon: trip.boardingStop.longitude,
        profile: 'foot',
      );

      List<LatLng> busPoints;
      if (trip.routeStops.length >= 2) {
        busPoints = trip.routeStops
            .map((s) => LatLng(s.latitude, s.longitude))
            .toList();
      } else {
        busPoints = await _fetchOsrmRoute(
          fromLat: trip.boardingStop.latitude,
          fromLon: trip.boardingStop.longitude,
          toLat: trip.alightingStop.latitude,
          toLon: trip.alightingStop.longitude,
          profile: 'driving',
        );
      }

      if (mounted) {
        setState(() {
          _walkPolyline = walkPoints;
          _busPolyline = busPoints;
          _polylinesLoading = false;
        });
        _fitMapToBounds();
      }
    } catch (_) {
      if (mounted) setState(() => _polylinesLoading = false);
    }
  }

  Future<List<LatLng>> _fetchOsrmRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    String profile = 'foot',
  }) async {
    final url =
        '${ApiConfig.osrmBaseUrl}/$profile/$fromLon,$fromLat;$toLon,$toLat'
        '?overview=full&geometries=geojson';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return [];

      final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List?;
      if (coordinates == null) return [];

      return coordinates
          .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _fitMapToBounds() {
    final allPoints = [..._walkPolyline, ..._busPolyline];
    if (allPoints.isEmpty) return;

    // FIX: LatLngBounds.fromPoints() — eski positional constructor kaldırıldı
    final bounds = LatLngBounds.fromPoints(allPoints);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 120, 40, 280),
        ),
      );
      if (mounted) setState(() => _mapFollowsUser = false);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  // BUILD — FIX: WillPopScope → PopScope (Flutter 3.12+)
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _showExitDialog();
      },
      child: Scaffold(
        body: Stack(
          children: [
            _buildMap(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildBottomCard(),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 280,
              child: _buildMapControls(),
            ),
            if (_polylinesLoading)
              Positioned(
                top: MediaQuery.of(context).padding.top + 80,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 6),
                      Text('Rota çiziliyor...',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Harita
  // ─────────────────────────────────────────────────────────

  Widget _buildMap() {
    final locationProvider = context.watch<LocationProvider>();
    final userLoc = locationProvider.currentLocation;
    final userLatLng =
        userLoc != null ? LatLng(userLoc.latitude, userLoc.longitude) : null;

    if (_mapFollowsUser && userLatLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(userLatLng, _mapController.camera.zoom);
        } catch (_) {}
      });
    }

    final trip = _trip;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: userLatLng ??
            (trip != null
                ? LatLng(
                    trip.boardingStop.latitude, trip.boardingStop.longitude)
                : const LatLng(38.614, 27.424)),
        initialZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: ApiConfig.osmTileUrl,
          userAgentPackageName: 'com.example.manisa_ulasim',
        ),

        // Otobüs güzergahı (düz çizgi, hat rengi)
        if (_busPolyline.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _busPolyline,
                color: (trip?.route.color ?? Colors.blue).withOpacity(0.85),
                strokeWidth: 6,
                borderColor: Colors.white.withOpacity(0.6),
                borderStrokeWidth: 2,
              ),
            ],
          ),

        // Yürüyüş rotası — noktalı görünüm için iki katmanlı çizim:
        // altta beyaz kalın + üstte mavi ince = kesik çizgi efekti
        if (_walkPolyline.length >= 2) ...[
          PolylineLayer(
            polylines: [
              Polyline(
                points: _walkPolyline,
                color: Colors.white,
                strokeWidth: 6,
              ),
            ],
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: _walkPolyline,
                color: Colors.blue.shade700.withOpacity(0.85),
                strokeWidth: 3,
              ),
            ],
          ),
        ],

        MarkerLayer(
          markers: [
            if (trip != null)
              Marker(
                point: LatLng(
                    trip.boardingStop.latitude, trip.boardingStop.longitude),
                width: 68,
                height: 68,
                child: _StopMarker(
                  label: trip.route.routeShortName,
                  color: trip.route.color,
                  icon: Icons.directions_bus,
                ),
              ),
            if (trip != null)
              Marker(
                point: LatLng(
                    trip.alightingStop.latitude, trip.alightingStop.longitude),
                width: 68,
                height: 68,
                child: const _StopMarker(
                  label: 'İniş',
                  color: Colors.red,
                  icon: Icons.flag,
                ),
              ),
            if (userLatLng != null)
              Marker(
                point: userLatLng,
                width: 52,
                height: 52,
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 4,
                        )
                      ],
                    ),
                    child: const Icon(Icons.navigation,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Üst bar
  // ─────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final trip = _trip;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.75),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showExitDialog,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          if (trip != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: trip.route.color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trip.route.routeShortName,
                style: TextStyle(
                  color: trip.route.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.route.routeLongName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${trip.boardingStop.stopName} → ${trip.alightingStop.stopName}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _fitMapToBounds,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.fit_screen, color: Colors.white, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Alt navigasyon kartı
  // ─────────────────────────────────────────────────────────

  Widget _buildBottomCard() {
    final navService = context.watch<NavigationService>();
    final state = navService.state;
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (state == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black26, blurRadius: 20, offset: Offset(0, -4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildPhaseIndicator(state.phase),
          _buildMainInstruction(state, theme),
          _buildPhaseContent(state, theme),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPhaseIndicator(NavigationPhase phase) {
    final steps = [
      (NavigationPhase.walkingToStop, Icons.directions_walk, 'Yürü'),
      (NavigationPhase.waitingAtStop, Icons.schedule, 'Bekle'),
      (NavigationPhase.onBus, Icons.directions_bus, 'Otobüs'),
      (NavigationPhase.arrived, Icons.flag, 'İniş'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final step = entry.value;
          final isActive = step.$1 == phase;
          final isDone = step.$1.index < phase.index;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: isActive ? 36 : 28,
                        height: isActive ? 36 : 28,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.blue.shade600
                              : isDone
                                  ? Colors.green.shade400
                                  : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDone ? Icons.check : step.$2,
                          color: isActive || isDone
                              ? Colors.white
                              : Colors.grey.shade400,
                          size: isActive ? 20 : 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.$3,
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive
                              ? Colors.blue.shade600
                              : isDone
                                  ? Colors.green.shade500
                                  : Colors.grey.shade400,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (idx < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color:
                          isDone ? Colors.green.shade300 : Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMainInstruction(NavigationState state, ThemeData theme) {
    late Color bgColor;
    late IconData icon;
    const Color textColor = Colors.white;

    // FIX: exhaustive switch (break yerine Dart 3 syntax)
    switch (state.phase) {
      case NavigationPhase.walkingToStop:
        bgColor = Colors.blue.shade600;
        icon = Icons.directions_walk;
      case NavigationPhase.waitingAtStop:
        bgColor = Colors.orange.shade600;
        icon = Icons.schedule;
      case NavigationPhase.onBus:
        bgColor = Colors.green.shade600;
        icon = Icons.directions_bus;
      case NavigationPhase.arrived:
        bgColor = Colors.red.shade600;
        icon = Icons.flag;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.instruction,
                  style: const TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
                if (state.subInstruction.isNotEmpty)
                  Text(
                    state.subInstruction,
                    style: TextStyle(
                        color: textColor.withOpacity(0.85), fontSize: 13),
                  ),
              ],
            ),
          ),
          if (state.distanceToNextPoint > 0)
            Column(
              children: [
                Text(
                  state.distanceToNextPoint < 1000
                      ? '${state.distanceToNextPoint.toInt()}'
                      : '${(state.distanceToNextPoint / 1000).toStringAsFixed(1)}',
                  style: const TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 22),
                ),
                Text(
                  state.distanceToNextPoint < 1000 ? 'm' : 'km',
                  style: TextStyle(
                      color: textColor.withOpacity(0.8), fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPhaseContent(NavigationState state, ThemeData theme) {
    switch (state.phase) {
      case NavigationPhase.walkingToStop:
        return _buildWalkingContent(state, theme);
      case NavigationPhase.waitingAtStop:
        return _buildWaitingContent(state, theme);
      case NavigationPhase.onBus:
        return _buildOnBusContent(state, theme);
      case NavigationPhase.arrived:
        return _buildArrivedContent(theme);
    }
  }

  // ─── Yürüyüş aşaması ─────────────────────────────────────

  Widget _buildWalkingContent(NavigationState state, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue.shade400, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Biniş Durağı: ${_trip?.boardingStop.stopName ?? ''}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _skipWalkingToStop,
              icon: const Icon(Icons.directions_bus_filled, size: 18),
              label: const Text(
                'Durağa Kendim Gidebilirim',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade400, width: 1.5),
                backgroundColor: Colors.orange.shade50,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _skipWalkingToStop() {
    final trip = _trip;
    if (trip != null) {
      try {
        _mapController.move(
          LatLng(trip.boardingStop.latitude, trip.boardingStop.longitude),
          17,
        );
        setState(() => _mapFollowsUser = false);
      } catch (_) {}
    }
    context.read<NavigationService>().skipToWaitingAtStop();
  }

  // ─── Bekleme aşaması ─────────────────────────────────────

  Widget _buildWaitingContent(NavigationState state, ThemeData theme) {
    final minutes = state.minutesUntilBus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_bus,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    minutes != null
                        ? '$minutes dk sonra'
                        : _trip?.nextDeparture ?? 'Bekleniyor',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () =>
                context.read<NavigationService>().confirmBoarding(),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Bindim!'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Otobüste aşaması ────────────────────────────────────

  Widget _buildOnBusContent(NavigationState state, ThemeData theme) {
    final stopsLeft = state.stopsRemaining;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          if (stopsLeft != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                (stopsLeft + 1).clamp(1, 6),
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < stopsLeft
                        ? Colors.grey.shade300
                        : Colors.green.shade500,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.flag, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('İniş Durağınız',
                          style: TextStyle(
                              color: Colors.green.shade600, fontSize: 11)),
                      Text(
                        _trip?.alightingStop.stopName ?? '',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (stopsLeft != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      stopsLeft == 0 ? 'Şimdi!' : '$stopsLeft durak',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Varış aşaması ───────────────────────────────────────

  Widget _buildArrivedContent(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.celebration, color: Colors.amber, size: 40),
          const SizedBox(height: 8),
          Text(
            'Hedefinize Ulaştınız!',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await context.read<NavigationService>().stopNavigation();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Navigasyonu Bitir'),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Harita kontrolleri
  // ─────────────────────────────────────────────────────────

  Widget _buildMapControls() {
    return Column(
      children: [
        FloatingActionButton.small(
          heroTag: 'recenter',
          onPressed: () {
            setState(() => _mapFollowsUser = true);
            final loc = context.read<LocationProvider>().currentLocation;
            if (loc != null) {
              _mapController.move(LatLng(loc.latitude, loc.longitude), 16);
            }
          },
          backgroundColor:
              _mapFollowsUser ? Colors.blue.shade600 : Colors.white,
          child: Icon(
            Icons.my_location,
            color: _mapFollowsUser ? Colors.white : Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'fitAll',
          backgroundColor: Colors.white,
          onPressed: _fitMapToBounds,
          tooltip: 'Tüm rotayı göster',
          child: Icon(Icons.zoom_out_map, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'zoomIn',
          backgroundColor: Colors.white,
          onPressed: () => _mapController.move(
              _mapController.camera.center, _mapController.camera.zoom + 1),
          child: Icon(Icons.add, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'zoomOut',
          backgroundColor: Colors.white,
          onPressed: () => _mapController.move(
              _mapController.camera.center, _mapController.camera.zoom - 1),
          child: Icon(Icons.remove, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Çıkış dialogu
  // FIX: Çift pop hatası giderildi.
  // Eski: dialog içinde pop(true) + dışarıda tekrar pop → çift pop
  // Yeni: dialog sadece bool döndürür, navigator işlemi burada yapılır
  // ─────────────────────────────────────────────────────────

  Future<void> _showExitDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Navigasyonu Bitir?'),
        content:
            const Text('Navigasyonu durdurursanız yönlendirmeler sona erer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Devam Et'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Bitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await context.read<NavigationService>().stopNavigation();
      if (mounted) Navigator.of(context).pop();
    }
  }
}

// ─────────────────────────────────────────────────────────
// Yardımcı widget'lar
// ─────────────────────────────────────────────────────────

class _StopMarker extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StopMarker({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
