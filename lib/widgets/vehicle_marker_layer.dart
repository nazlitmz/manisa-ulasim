import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/vehicle_location_model.dart';

/// Araç marker'larını haritada gösteren izole layer widget'ı.
///
/// **Performans notları:**
/// - `BusImageCache` singleton ile BUS.png her build'de yeniden decode edilmez.
/// - `AnimatedVehicleMarker` kendi `TweenAnimationBuilder`'ı ile position interpolation
///   yapar; üst widget rebuild gerekmez.
/// - `VehicleMarkerLayer` sadece [vehicles] listesi değişince rebuild olur.
class VehicleMarkerLayer extends StatelessWidget {
  final List<VehicleLocation> vehicles;
  final Map<String, LatLng> snappedPositions;
  final Map<String, double> bearings;
  final String? selectedVehicleId;
  final Color routeColor;
  final String routeNumber;
  final Animation<double> pulseAnimation;
  final void Function(VehicleLocation vehicle) onVehicleTap;

  const VehicleMarkerLayer({
    super.key,
    required this.vehicles,
    required this.snappedPositions,
    required this.bearings,
    required this.routeColor,
    required this.routeNumber,
    required this.pulseAnimation,
    required this.onVehicleTap,
    this.selectedVehicleId,
  });

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: vehicles.map((vehicle) {
        final isSelected = vehicle.id == selectedVehicleId;
        final position = snappedPositions[vehicle.id] ??
            LatLng(vehicle.gps.latitude, vehicle.gps.longitude);
        final bearing = bearings[vehicle.id] ?? 0.0;
        final isMoving = (vehicle.gps.speed ?? 0) > 3;
        final markerSize = isSelected ? 80.0 : 64.0;

        return Marker(
          point: position,
          width: markerSize,
          height: markerSize,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => onVehicleTap(vehicle),
            child: AnimatedBuilder(
              animation: pulseAnimation,
              builder: (context, _) => _BusMarker(
                routeColor: routeColor,
                routeNumber: routeNumber,
                isSelected: isSelected,
                isMoving: isMoving,
                bearing: bearing,
                pulseValue: pulseAnimation.value,
                markerSize: markerSize,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// _BusMarker: BUS.png kullanan, bearing'e göre dönen marker
// ---------------------------------------------------------------------------

class _BusMarker extends StatelessWidget {
  final Color routeColor;
  final String routeNumber;
  final bool isSelected;
  final bool isMoving;
  final double bearing;
  final double pulseValue;
  final double markerSize;

  const _BusMarker({
    required this.routeColor,
    required this.routeNumber,
    required this.isSelected,
    required this.isMoving,
    required this.bearing,
    required this.pulseValue,
    required this.markerSize,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = markerSize * 0.62;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // --- Pulse halkası (sadece hareket halinde) ---
        if (isMoving)
          Container(
            width: markerSize * 0.96 * pulseValue,
            height: markerSize * 0.96 * pulseValue,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.green.withOpacity(0.5 * pulseValue),
                width: 2.5,
              ),
            ),
          ),

        // --- Araç ikonu (bearing'e göre döner, sade PNG) ---
        Transform.rotate(
          angle: bearing * pi / 180,
          child: Image.asset(
            'assets/BUS.png',
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.directions_bus,
              size: iconSize,
              color: routeColor,
            ),
          ),
        ),

        // --- Hat numarası etiketi (dönmez) ---
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: routeColor,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              routeNumber,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSelected ? 10 : 8,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ),
        ),

        // --- Canlı yeşil nokta (hareket halinde, dönmez) ---
        if (isMoving)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: isSelected ? 14 : 11,
              height: isSelected ? 14 : 11,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.55),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
