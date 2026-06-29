import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/stop_model.dart';

/// Durakları haritada gösteren izole layer widget'ı.
class StopMarkerLayer extends StatelessWidget {
  final List<Stop> stops;
  final String? selectedStopId;
  final Color routeColor;
  final void Function(Stop stop) onStopTap;

  const StopMarkerLayer({
    super.key,
    required this.stops,
    required this.routeColor,
    required this.onStopTap,
    this.selectedStopId,
  });

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Başlangıç ve bitiş RouteEndpointLayer tarafından çizildiği için atla
    final middleStops =
        stops.length > 2 ? stops.sublist(1, stops.length - 1) : stops;

    return MarkerLayer(
      markers: List.generate(middleStops.length, (i) {
        final stop = middleStops[i];
        // FİX: indexOf yerine sublist offset kullan — aynı isimli durak olsa bile doğru index
        final realIndex = stops.length > 2 ? i + 1 : i;
        final isSelected = stop.stopId == selectedStopId;

        final double size = isSelected ? 36.0 : 24.0;

        return Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () => onStopTap(stop),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isSelected
                    ? routeColor
                    : (isDark ? const Color(0xFF3A3A3A) : Colors.white),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isSelected ? Colors.white : routeColor.withOpacity(0.8),
                  width: isSelected ? 2.5 : 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isSelected ? 0.35 : 0.15),
                    blurRadius: isSelected ? 8 : 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              // FİX: FittedBox ile 2 haneli sayılar taşmıyor
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    '${realIndex + 1}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : routeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
