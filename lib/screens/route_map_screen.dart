import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../models/route_model.dart';
import '../models/stop_model.dart';
import '../models/vehicle_location_model.dart';
import '../providers/location_provider.dart';

import '../widgets/route_map_controller.dart';
import '../widgets/route_polyline_layer.dart';
import '../widgets/stop_marker_layer.dart';
import '../widgets/vehicle_marker_layer.dart';

// ---------------------------------------------------------------------------
// RouteMapScreen
// ---------------------------------------------------------------------------

class RouteMapScreen extends StatefulWidget {
  final TransitRoute route;

  const RouteMapScreen({
    super.key,
    required this.route,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen>
    with SingleTickerProviderStateMixin {
  late final RouteMapController _ctrl;
  final MapController _mapController = MapController();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// Kullanıcı konumunu takip etme modu açık mı?
  bool _followUserLocation = false;

  @override
  void initState() {
    super.initState();

    _ctrl = RouteMapController(route: widget.route);
    _ctrl.addListener(_onControllerUpdate);
    _ctrl.init().then((_) {
      if (mounted) _ctrl.fitBounds(_mapController);
    });

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerUpdate);
    _ctrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Konum değişince haritayı kaydır (takip modu açıksa)
    if (_followUserLocation) {
      final locationProvider = context.watch<LocationProvider>();
      final loc = locationProvider.effectiveLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _followUserLocation) {
          _mapController.move(LatLng(loc.latitude, loc.longitude), 16);
        }
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(theme, isDark),
      body: _ctrl.isLoading
          ? _buildLoading(theme)
          : _ctrl.error != null
              ? _buildError(theme)
              : _buildMapStack(theme, isDark),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    final iconColor = isDark ? Colors.white : Colors.black87;

    return AppBar(
      backgroundColor:
          (isDark ? const Color(0xFF121212) : Colors.white).withOpacity(0.92),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: iconColor),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: iconColor),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          _RouteChip(
            label: widget.route.routeShortName,
            background: widget.route.color,
            textColor: widget.route.textColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.route.routeLongName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.directions_bus_rounded),
              tooltip: 'Aktif Otobüsler',
              onPressed: _showActiveVehiclesSheet,
            ),
            if (_ctrl.currentVehicles.isNotEmpty)
              Positioned(
                right: 6,
                top: 6,
                child: _Badge(count: _ctrl.currentVehicles.length),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.list_alt_rounded),
          tooltip: 'Duraklar',
          onPressed: _showListSheet,
        ),
        IconButton(
          icon: Icon(
              _ctrl.showVehicles ? Icons.directions_bus : Icons.no_transfer),
          tooltip: _ctrl.showVehicles ? 'Araçları Gizle' : 'Araçları Göster',
          onPressed: _ctrl.toggleVehicles,
        ),
        IconButton(
          icon: Icon(_ctrl.showStops ? Icons.location_on : Icons.location_off),
          tooltip: _ctrl.showStops ? 'Durakları Gizle' : 'Durakları Göster',
          onPressed: _ctrl.toggleStops,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Loading / Error
  // ---------------------------------------------------------------------------

  Widget _buildLoading(ThemeData theme) =>
      const Center(child: CircularProgressIndicator());

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text('Güzergah Yüklenemedi', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_ctrl.error ?? '',
                style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _ctrl.loadRouteData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Harita
  // ---------------------------------------------------------------------------

  Widget _buildMapStack(ThemeData theme, bool isDark) {
    final locationProvider = context.watch<LocationProvider>();
    final userLoc = locationProvider.effectiveLocation;
    final userLatLng = LatLng(userLoc.latitude, userLoc.longitude);
    final hasRealLocation = locationProvider.hasLocation;

    final points = _ctrl.currentPoints;
    final stops = _ctrl.currentStops;
    final vehicles = _ctrl.currentVehicles;

    LatLng center = userLatLng; // Varsayılan merkez = kullanıcı konumu
    if (points.isNotEmpty) {
      double la = 0, lo = 0;
      for (final p in points) {
        la += p.latitude;
        lo += p.longitude;
      }
      center = LatLng(la / points.length, lo / points.length);
    }

    return Stack(
      children: [
        // ── Harita ──────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            minZoom: AppConstants.minZoom,
            maxZoom: AppConstants.maxZoom,
            onTap: (_, __) => _ctrl.clearSelection(),
            // Kullanıcı haritayı elle kaydırırsa takip modunu kapat
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _followUserLocation) {
                setState(() => _followUserLocation = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: AppConstants.osmTileUrl,
              userAgentPackageName: 'com.manisa.ulasim',
            ),

            // Güzergah çizgisi
            RoutePolylineLayer(
              points: points,
              color: widget.route.color,
            ),

            // Durak marker'ları
            if (_ctrl.showStops)
              StopMarkerLayer(
                stops: stops,
                routeColor: widget.route.color,
                selectedStopId: _ctrl.selectedStop?.stopId,
                onStopTap: (stop) {
                  _ctrl.selectStop(stop);
                  _mapController.move(
                      LatLng(stop.latitude, stop.longitude), 16);
                },
              ),

            // Başlangıç / bitiş noktaları
            if (points.isNotEmpty) RouteEndpointLayer(points: points),

            // Araç marker'ları
            if (_ctrl.showVehicles)
              VehicleMarkerLayer(
                vehicles: vehicles,
                snappedPositions: _ctrl.vehicleSnappedPositions,
                bearings: _ctrl.vehicleBearings,
                routeColor: widget.route.color,
                routeNumber: widget.route.routeShortName,
                pulseAnimation: _pulseAnimation,
                selectedVehicleId: _ctrl.selectedVehicle?.id,
                onVehicleTap: (v) {
                  _ctrl.selectVehicle(v);
                  final pos = _ctrl.vehicleSnappedPositions[v.id] ??
                      LatLng(v.gps.latitude, v.gps.longitude);
                  _mapController.move(pos, 16);
                },
              ),

            // ── Kullanıcı konumu ──────────────────────────────────────────
            MarkerLayer(
              markers: [
                Marker(
                  point: userLatLng,
                  width: 56,
                  height: 56,
                  child: _UserLocationMarker(
                    hasRealLocation: hasRealLocation,
                    pulseAnimation: _pulseAnimation,
                  ),
                ),
              ],
            ),
          ],
        ),

        // ── Yön seçici ──────────────────────────────────────────────────────
        if (_ctrl.outboundPoints.isNotEmpty || _ctrl.inboundPoints.isNotEmpty)
          Positioned(
            top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 64,
            child: _DirectionSelector(
              isDark: isDark,
              hasOutbound: _ctrl.outboundPoints.isNotEmpty,
              hasInbound: _ctrl.inboundPoints.isNotEmpty,
              selectedDirection: _ctrl.selectedDirection,
              onDirectionChanged: (dir) {
                _ctrl.setDirection(dir);
                _ctrl.fitBounds(_mapController);
              },
            ),
          ),

        // ── Seçili araç bilgi kartı ─────────────────────────────────────────
        if (_ctrl.selectedVehicle != null)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 132,
            left: 16,
            right: 16,
            child: _VehicleInfoCard(
              vehicle: _ctrl.selectedVehicle!,
              route: widget.route,
              isDark: isDark,
              onClose: _ctrl.clearSelection,
            ),
          ),

        // ── Seçili durak bilgi kartı ────────────────────────────────────────
        if (_ctrl.selectedStop != null && _ctrl.selectedVehicle == null)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 132,
            left: 16,
            right: 16,
            child: _StopInfoCard(
              stop: _ctrl.selectedStop!,
              stops: stops,
              route: widget.route,
              isDark: isDark,
              onClose: _ctrl.clearSelection,
            ),
          ),

        // ── Alt özet şeridi ─────────────────────────────────────────────────
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16,
          right: 16,
          child: _SummaryBar(
            route: widget.route,
            stopCount: stops.length,
            vehicleCount: vehicles.length,
            direction: _ctrl.selectedDirection,
            isDark: isDark,
          ),
        ),

        // ── Sığdır butonu ───────────────────────────────────────────────────
        Positioned(
          top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: FloatingActionButton.small(
            heroTag: 'fitBounds',
            onPressed: () {
              setState(() => _followUserLocation = false);
              _ctrl.fitBounds(_mapController);
            },
            backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            elevation: 3,
            child: Icon(Icons.fit_screen,
                color: isDark ? Colors.white : Colors.black87, size: 20),
          ),
        ),

        // ── Konumuma git butonu ─────────────────────────────────────────────
        Positioned(
          top: kToolbarHeight + MediaQuery.of(context).padding.top + 56,
          right: 12,
          child: FloatingActionButton.small(
            heroTag: 'myLocation',
            onPressed: () {
              setState(() => _followUserLocation = !_followUserLocation);
              if (_followUserLocation) {
                _mapController.move(userLatLng, 16);
              }
            },
            backgroundColor: _followUserLocation
                ? widget.route.color
                : (isDark ? const Color(0xFF2C2C2C) : Colors.white),
            elevation: 3,
            tooltip: _followUserLocation ? 'Takibi Durdur' : 'Konumuma Git',
            child: Icon(
              _followUserLocation
                  ? Icons.my_location
                  : Icons.location_searching,
              color: _followUserLocation
                  ? Colors.white
                  : (isDark ? Colors.white : Colors.black87),
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom sheets
  // ---------------------------------------------------------------------------

  void _showActiveVehiclesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ActiveVehiclesSheet(
        ctrl: _ctrl,
        route: widget.route,
        onVehicleTap: (vehicle) {
          _ctrl.selectVehicle(vehicle);
          final pos = _ctrl.vehicleSnappedPositions[vehicle.id] ??
              LatLng(vehicle.gps.latitude, vehicle.gps.longitude);
          _mapController.move(pos, 16);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showListSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StopListSheet(
        ctrl: _ctrl,
        route: widget.route,
        onStopTap: (stop) {
          _ctrl.selectStop(stop);
          _mapController.move(LatLng(stop.latitude, stop.longitude), 16);
          Navigator.pop(ctx);
        },
        onVehicleTap: (vehicle) {
          _ctrl.selectVehicle(vehicle);
          final pos = _ctrl.vehicleSnappedPositions[vehicle.id] ??
              LatLng(vehicle.gps.latitude, vehicle.gps.longitude);
          _mapController.move(pos, 16);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ===========================================================================
// _UserLocationMarker — Kullanıcının harita üzerindeki konum göstergesi
// ===========================================================================

class _UserLocationMarker extends StatelessWidget {
  final bool hasRealLocation;
  final Animation<double> pulseAnimation;

  const _UserLocationMarker({
    required this.hasRealLocation,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Dış halka (pulse)
            Container(
              width: 52 * pulseAnimation.value,
              height: 52 * pulseAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(
                  0.15 * (2 - pulseAnimation.value),
                ),
              ),
            ),
            // Orta halka
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.2),
                border:
                    Border.all(color: Colors.blue.withOpacity(0.5), width: 1),
              ),
            ),
            // İç nokta
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasRealLocation ? Colors.blue : Colors.orange,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: (hasRealLocation ? Colors.blue : Colors.orange)
                        .withOpacity(0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
// Alt bileşenler (değişmeyenler)
// ===========================================================================

class _RouteChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;

  const _RouteChip({
    required this.label,
    required this.background,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _DirectionSelector extends StatelessWidget {
  final bool isDark;
  final bool hasOutbound;
  final bool hasInbound;
  final int selectedDirection;
  final void Function(int) onDirectionChanged;

  const _DirectionSelector({
    required this.isDark,
    required this.hasOutbound,
    required this.hasInbound,
    required this.selectedDirection,
    required this.onDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: isDark ? const Color(0xFF242424) : Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            if (hasOutbound)
              Expanded(
                child: _DirButton(
                  label: 'Gidiş',
                  icon: Icons.arrow_forward_rounded,
                  selected: selectedDirection == 1,
                  onTap: () => onDirectionChanged(1),
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            if (hasOutbound && hasInbound)
              Container(width: 1, height: 22, color: Colors.grey.shade300),
            if (hasInbound)
              Expanded(
                child: _DirButton(
                  label: 'Dönüş',
                  icon: Icons.arrow_back_rounded,
                  selected: selectedDirection == 2,
                  onTap: () => onDirectionChanged(2),
                  activeColor: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DirButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  const _DirButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: selected ? activeColor : Colors.grey),
      label: Text(
        label,
        style: TextStyle(
          color: selected ? activeColor : Colors.grey,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final TransitRoute route;
  final int stopCount;
  final int vehicleCount;
  final int direction;
  final bool isDark;

  const _SummaryBar({
    required this.route,
    required this.stopCount,
    required this.vehicleCount,
    required this.direction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: isDark ? const Color(0xFF242424) : Colors.white,
      elevation: 6,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _RouteChip(
                label: route.routeShortName,
                background: route.color,
                textColor: route.textColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                route.routeLongName,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _InfoPill(
                icon: Icons.location_on_rounded,
                label: '$stopCount',
                color: Colors.blue,
                isDark: isDark),
            const SizedBox(width: 6),
            _InfoPill(
                icon: Icons.directions_bus_rounded,
                label: '$vehicleCount',
                color: Colors.green,
                isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleInfoCard extends StatelessWidget {
  final VehicleLocation vehicle;
  final TransitRoute route;
  final bool isDark;
  final VoidCallback onClose;

  const _VehicleInfoCard({
    required this.vehicle,
    required this.route,
    required this.isDark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speed = vehicle.gps.speed?.toStringAsFixed(0) ?? '0';
    final isMoving = (vehicle.gps.speed ?? 0) > 3;

    return Card(
      color: isDark ? const Color(0xFF242424) : Colors.white,
      elevation: 10,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Stack(
              children: [
                Image.asset(
                  'assets/BUS.png',
                  width: 52,
                  height: 52,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.directions_bus, size: 52, color: route.color),
                ),
                if (isMoving)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vehicle.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      _StatusChip(isMoving: isMoving, speed: speed),
                    ],
                  ),
                  if (vehicle.driverName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person,
                            size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          vehicle.driverName!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isMoving;
  final String speed;

  const _StatusChip({required this.isMoving, required this.speed});

  @override
  Widget build(BuildContext context) {
    final color = isMoving ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 5),
          Text(
            isMoving ? '$speed km/s' : 'Duruyor',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StopInfoCard extends StatelessWidget {
  final Stop stop;
  final List<Stop> stops;
  final TransitRoute route;
  final bool isDark;
  final VoidCallback onClose;

  const _StopInfoCard({
    required this.stop,
    required this.stops,
    required this.route,
    required this.isDark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = stops.indexWhere((s) => s.stopId == stop.stopId);

    return Card(
      color: isDark ? const Color(0xFF242424) : Colors.white,
      elevation: 10,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration:
                  BoxDecoration(color: route.color, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                      color: route.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stop.stopName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${stops.length} duraktan ${index + 1}. durak',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopListSheet extends StatelessWidget {
  final RouteMapController ctrl;
  final TransitRoute route;
  final void Function(Stop) onStopTap;
  final void Function(VehicleLocation) onVehicleTap;

  const _StopListSheet({
    required this.ctrl,
    required this.route,
    required this.onStopTap,
    required this.onVehicleTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _RouteChip(
                      label: route.routeShortName,
                      background: route.color,
                      textColor: route.textColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(route.routeLongName,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          ctrl.selectedDirection == 1
                              ? 'Gidiş Yönü  •  ${ctrl.currentStops.length} durak'
                              : 'Dönüş Yönü  •  ${ctrl.currentStops.length} durak',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Builder(
                builder: (context) {
                  final navBottom = MediaQuery.of(context).padding.bottom;
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: ctrl.currentStops.length,
                    padding: EdgeInsets.fromLTRB(12, 6, 12, 6 + navBottom),
                    itemBuilder: (_, i) => _StopListTile(
                      stop: ctrl.currentStops[i],
                      index: i,
                      total: ctrl.currentStops.length,
                      route: route,
                      isDark: isDark,
                      vehiclesAtStop: ctrl.currentVehicles
                          .where((v) =>
                              ctrl.vehicleStopMapping[v.id] ==
                              ctrl.currentStops[i].stopId)
                          .toList(),
                      onStopTap: onStopTap,
                      onVehicleTap: onVehicleTap,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopListTile extends StatelessWidget {
  final Stop stop;
  final int index;
  final int total;
  final TransitRoute route;
  final bool isDark;
  final List<VehicleLocation> vehiclesAtStop;
  final void Function(Stop) onStopTap;
  final void Function(VehicleLocation) onVehicleTap;

  const _StopListTile({
    required this.stop,
    required this.index,
    required this.total,
    required this.route,
    required this.isDark,
    required this.vehiclesAtStop,
    required this.onStopTap,
    required this.onVehicleTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFirst = index == 0;
    final isLast = index == total - 1;
    final dotColor = isFirst
        ? Colors.green
        : isLast
            ? Colors.red
            : route.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 36,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    if (!isFirst)
                      Positioned(
                        top: 0,
                        bottom: isLast ? null : 0,
                        height: isLast ? 22 : null,
                        child: Container(
                            width: 2, color: route.color.withOpacity(0.35)),
                      ),
                    if (!isLast)
                      Positioned(
                        top: 22,
                        bottom: 0,
                        child: Container(
                            width: 2, color: route.color.withOpacity(0.35)),
                      ),
                    Positioned(
                      top: 16,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: dotColor.withOpacity(0.4), blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => onStopTap(stop),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(stop.stopName,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w500)),
                              if (isFirst)
                                Text('Başlangıç durağı',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600))
                              else if (isLast)
                                Text('Son durak',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red.shade600)),
                            ],
                          ),
                        ),
                        if (vehiclesAtStop.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.green.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.directions_bus,
                                    size: 13, color: Colors.green),
                                const SizedBox(width: 3),
                                Text('${vehiclesAtStop.length}',
                                    style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right,
                            size: 18, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (vehiclesAtStop.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: vehiclesAtStop
                  .map((v) => _VehicleChip(
                        vehicle: v,
                        route: route,
                        isDark: isDark,
                        onTap: () => onVehicleTap(v),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final VehicleLocation vehicle;
  final TransitRoute route;
  final bool isDark;
  final VoidCallback onTap;

  const _VehicleChip({
    required this.vehicle,
    required this.route,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final speed = vehicle.gps.speed?.toStringAsFixed(0) ?? '0';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2E2E2E) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/BUS.png',
                width: 18,
                height: 18,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.directions_bus, size: 16, color: route.color)),
            const SizedBox(width: 6),
            Text(vehicle.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(width: 6),
            Text('$speed km/s',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _ActiveVehiclesSheet extends StatelessWidget {
  final RouteMapController ctrl;
  final TransitRoute route;
  final void Function(VehicleLocation) onVehicleTap;

  const _ActiveVehiclesSheet({
    required this.ctrl,
    required this.route,
    required this.onVehicleTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final vehicles = ctrl.currentVehicles;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.directions_bus_rounded,
                        color: Colors.green, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aktif Otobüsler',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '${vehicles.length} araç aktif  •  ${route.routeShortName} hattı',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: vehicles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.no_transfer,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('Bu yönde aktif araç yok',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey)),
                        ],
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final navBottom = MediaQuery.of(context).padding.bottom;
                        return ListView.separated(
                          controller: scrollCtrl,
                          padding:
                              EdgeInsets.fromLTRB(12, 8, 12, 8 + navBottom),
                          itemCount: vehicles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final vehicle = vehicles[i];
                            final speed =
                                vehicle.gps.speed?.toStringAsFixed(0) ?? '0';
                            final isMoving = (vehicle.gps.speed ?? 0) > 3;

                            final assignedStopId =
                                ctrl.vehicleStopMapping[vehicle.id];
                            final assignedStop = assignedStopId != null
                                ? ctrl.currentStops.firstWhere(
                                    (s) => s.stopId == assignedStopId,
                                    orElse: () => ctrl.currentStops.first,
                                  )
                                : null;
                            final stopIndex = assignedStop != null
                                ? ctrl.currentStops.indexOf(assignedStop)
                                : -1;

                            return InkWell(
                              onTap: () => onVehicleTap(vehicle),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2A2A)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isMoving
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Stack(
                                      children: [
                                        Image.asset('assets/BUS.png',
                                            width: 44,
                                            height: 44,
                                            errorBuilder: (_, __, ___) => Icon(
                                                Icons.directions_bus,
                                                size: 44,
                                                color: route.color)),
                                        if (isMoving)
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.5),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(vehicle.name,
                                                    style: theme
                                                        .textTheme.titleSmall
                                                        ?.copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                              ),
                                              _StatusChip(
                                                  isMoving: isMoving,
                                                  speed: speed),
                                            ],
                                          ),
                                          if (vehicle.driverName != null) ...[
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Icon(Icons.person,
                                                    size: 12,
                                                    color:
                                                        Colors.grey.shade500),
                                                const SizedBox(width: 4),
                                                Text(vehicle.driverName!,
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                            color: Colors.grey
                                                                .shade500)),
                                              ],
                                            ),
                                          ],
                                          if (assignedStop != null) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: route.color
                                                    .withOpacity(0.08),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: route.color
                                                        .withOpacity(0.25)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 18,
                                                    height: 18,
                                                    decoration: BoxDecoration(
                                                        color: route.color,
                                                        shape: BoxShape.circle),
                                                    child: Center(
                                                      child: Text(
                                                          '${stopIndex + 1}',
                                                          style: const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      assignedStop.stopName,
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: route.color),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else ...[
                                            const SizedBox(height: 4),
                                            Text('Durak bilgisi yok',
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                        color: Colors
                                                            .grey.shade400)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right,
                                        size: 18, color: Colors.grey.shade400),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
