import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/vehicle_location_model.dart';

class VehicleService {
  static String get _baseUrl => dotenv.env['MANISA_VEHICLE_API_BASE_URL'] ?? '';

  /// Belirli bir hat için araçları getir
  Future<List<VehicleLocation>> getVehiclesForRoute(String routeId) async {
    try {
      debugPrint('🚗 Araçlar yükleniyor... Route: $routeId');

      final response = await http
          .get(
        Uri.parse('$_baseUrl/transit/routes/devices?route_id=$routeId'),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Araçlar yükleme zaman aşımı');
        },
      );

      debugPrint('📨 Response Status: ${response.statusCode}');
      debugPrint('🔍 HAM API YANITI: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Farklı JSON yapılarını dene
        List<dynamic> devices = [];

        if (data is List) {
          // Direkt liste: [{...}, {...}]
          devices = data;
        } else if (data is Map) {
          // { "data": { "devices": [...] } }
          final inner = data['data'];
          if (inner is List) {
            devices = inner;
          } else if (inner is Map) {
            final d = inner['devices'];
            if (d is List) devices = d;
          }

          // { "devices": [...] }
          if (devices.isEmpty && data['devices'] is List) {
            devices = data['devices'] as List;
          }

          // { "result": [...] }
          if (devices.isEmpty && data['result'] is List) {
            devices = data['result'] as List;
          }

          // { "vehicles": [...] }
          if (devices.isEmpty && data['vehicles'] is List) {
            devices = data['vehicles'] as List;
          }
        }

        debugPrint('📦 Bulunan araç sayısı: ${devices.length}');
        if (devices.isNotEmpty) {
          debugPrint('🚌 İlk araç ham verisi: ${devices.first}');
        }

        final vehicles = devices
            .map((json) =>
                VehicleLocation.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✅ ${vehicles.length} araç yüklendi');
        return vehicles;
      } else {
        debugPrint('❌ Hata: ${response.statusCode}');
        return [];
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Zaman aşımı: $e');
      return [];
    } catch (e, stack) {
      debugPrint('❌ Araç yükleme hatası: $e');
      debugPrint('❌ Stack: $stack');
      return [];
    }
  }

  /// Tüm araçları getir
  Future<List<VehicleLocation>> getAllVehicles() async {
    try {
      debugPrint('🚗 Tüm araçlar yükleniyor...');

      final response = await http
          .get(
        Uri.parse('$_baseUrl/vehicles'),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Araçlar yükleme zaman aşımı');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final devices = data['data']?['devices'] as List? ?? [];

        final vehicles = devices
            .map((json) =>
                VehicleLocation.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✅ ${vehicles.length} araç yüklendi');
        return vehicles;
      } else {
        debugPrint('❌ Hata: ${response.statusCode}');
        return [];
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Zaman aşımı: $e');
      return [];
    } catch (e) {
      debugPrint('❌ Araç yükleme hatası: $e');
      return [];
    }
  }

  /// Belirli bir aracı getir
  Future<VehicleLocation?> getVehicleById(String vehicleId) async {
    try {
      debugPrint('🚗 Araç yükleniyor... ID: $vehicleId');

      final response = await http
          .get(
        Uri.parse('$_baseUrl/vehicles/$vehicleId'),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Araç yükleme zaman aşımı');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final vehicle =
            VehicleLocation.fromJson(data['data'] as Map<String, dynamic>);

        debugPrint('✅ Araç yüklendi: ${vehicle.name}');
        return vehicle;
      } else {
        debugPrint('❌ Hata: ${response.statusCode}');
        return null;
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Zaman aşımı: $e');
      return null;
    } catch (e) {
      debugPrint('❌ Araç yükleme hatası: $e');
      return null;
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
