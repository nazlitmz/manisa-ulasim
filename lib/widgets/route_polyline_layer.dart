import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Rota polyline'larını çizen izole layer widget'ı.
/// Sadece [points] veya [color] değişince rebuild olur.
class RoutePolylineLayer extends StatelessWidget {
  final List<LatLng> points;
  final Color color;
  final double strokeWidth;

  const RoutePolylineLayer({
    super.key,
    required this.points,
    required this.color,
    this.strokeWidth = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    return PolylineLayer(
      polylines: [
        Polyline(
          points: points,
          color: color,
          strokeWidth: strokeWidth,
          borderColor: color.withOpacity(0.25),
          borderStrokeWidth: 2,
        ),
      ],
    );
  }
}

/// Gidiş ve dönüş için yalnızca başlangıç/bitiş marker'larını çizen layer.
class RouteEndpointLayer extends StatelessWidget {
  final List<LatLng> points;

  const RouteEndpointLayer({
    super.key,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: [
        _buildEndpoint(points.first, Colors.green, Icons.play_arrow),
        _buildEndpoint(points.last, Colors.red, Icons.stop),
      ],
    );
  }

  Marker _buildEndpoint(LatLng point, Color color, IconData icon) {
    return Marker(
      point: point,
      width: 36,
      height: 36,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
