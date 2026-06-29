import 'package:flutter/material.dart';

/// GTFS Route (Hat) modeli
class TransitRoute {
  final String routeId;
  final String? agencyId;
  final String routeShortName;
  final String routeLongName;
  final String? routeDesc;
  final int routeType; // 3 = Otobüs
  final String? routeUrl;
  final String? routeColor;
  final String? routeTextColor;
  final int? routeSortOrder;
  final int? continuousPickup;
  final int? continuousDropOff;
  final String? networkId;
  final String? asRoute;
  final bool isActive;
  
  TransitRoute({
    required this.routeId,
    this.agencyId,
    required this.routeShortName,
    required this.routeLongName,
    this.routeDesc,
    required this.routeType,
    this.routeUrl,
    this.routeColor,
    this.routeTextColor,
    this.routeSortOrder,
    this.continuousPickup,
    this.continuousDropOff,
    this.networkId,
    this.asRoute,
    this.isActive = true,
  });
  
  /// CSV satırından Route oluştur
  factory TransitRoute.fromCsvRow(List<dynamic> row, Map<String, int> headers) {
    return TransitRoute(
      routeId: row[headers['route_id']!].toString(),
      agencyId: _getStringValue(row, headers, 'agency_id'),
      routeShortName: row[headers['route_short_name']!].toString(),
      routeLongName: row[headers['route_long_name']!].toString(),
      routeDesc: _getStringValue(row, headers, 'route_desc'),
      routeType: int.tryParse(row[headers['route_type']!].toString()) ?? 3,
      routeUrl: _getStringValue(row, headers, 'route_url'),
      routeColor: _getStringValue(row, headers, 'route_color'),
      routeTextColor: _getStringValue(row, headers, 'route_text_color'),
      routeSortOrder: _getIntValue(row, headers, 'route_sort_order'),
      continuousPickup: _getIntValue(row, headers, 'continuous_pickup'),
      continuousDropOff: _getIntValue(row, headers, 'continuous_drop_off'),
      networkId: _getStringValue(row, headers, 'network_id'),
      asRoute: _getStringValue(row, headers, 'as_route'),
      isActive: _getStringValue(row, headers, 'is_active')?.toLowerCase() == 'true',
    );
  }
  
  /// Veritabanından Route oluştur
  factory TransitRoute.fromMap(Map<String, dynamic> map) {
    return TransitRoute(
      routeId: map['route_id'],
      agencyId: map['agency_id'],
      routeShortName: map['route_short_name'],
      routeLongName: map['route_long_name'],
      routeDesc: map['route_desc'],
      routeType: map['route_type'] ?? 3,
      routeUrl: map['route_url'],
      routeColor: map['route_color'],
      routeTextColor: map['route_text_color'],
      routeSortOrder: map['route_sort_order'],
      continuousPickup: map['continuous_pickup'],
      continuousDropOff: map['continuous_drop_off'],
      networkId: map['network_id'],
      asRoute: map['as_route'],
      isActive: map['is_active'] == 1,
    );
  }
  
  /// Veritabanına kaydetmek için Map'e dönüştür
  Map<String, dynamic> toMap() {
    return {
      'route_id': routeId,
      'agency_id': agencyId,
      'route_short_name': routeShortName,
      'route_long_name': routeLongName,
      'route_desc': routeDesc,
      'route_type': routeType,
      'route_url': routeUrl,
      'route_color': routeColor,
      'route_text_color': routeTextColor,
      'route_sort_order': routeSortOrder,
      'continuous_pickup': continuousPickup,
      'continuous_drop_off': continuousDropOff,
      'network_id': networkId,
      'as_route': asRoute,
      'is_active': isActive ? 1 : 0,
    };
  }
  
  /// Hat rengini Color olarak döndür
  Color get color {
    if (routeColor == null || routeColor!.isEmpty) {
      return const Color(0xFF1565C0); // Varsayılan mavi
    }
    
    try {
      String hex = routeColor!.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    
    return const Color(0xFF1565C0);
  }
  
  /// Metin rengini Color olarak döndür
  Color get textColor {
    if (routeTextColor == null || routeTextColor!.isEmpty) {
      return Colors.white;
    }
    
    try {
      String hex = routeTextColor!.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    
    return Colors.white;
  }
  
  /// Hat türünün adı
  String get typeName {
    switch (routeType) {
      case 0: return 'Tramvay';
      case 1: return 'Metro';
      case 2: return 'Tren';
      case 3: return 'Otobüs';
      case 4: return 'Feribot';
      case 5: return 'Teleferik';
      case 6: return 'Gondol';
      case 7: return 'Füniküler';
      case 11: return 'Troleybüs';
      case 12: return 'Monoray';
      default: return 'Diğer';
    }
  }
  
  /// Hat türü ikonu
  IconData get typeIcon {
    switch (routeType) {
      case 0: return Icons.tram;
      case 1: return Icons.subway;
      case 2: return Icons.train;
      case 3: return Icons.directions_bus;
      case 4: return Icons.directions_boat;
      case 5:
      case 6: return Icons.airline_seat_individual_suite;
      case 7: return Icons.trending_up;
      case 11: return Icons.electric_car;
      case 12: return Icons.train;
      default: return Icons.directions_bus;
    }
  }
  
  /// Görüntüleme adı (kısa isim - uzun isim)
  String get displayName {
    if (routeShortName.isNotEmpty) {
      return '$routeShortName - $routeLongName';
    }
    return routeLongName;
  }
  
  // Yardımcı fonksiyonlar
  static String? _getStringValue(List<dynamic> row, Map<String, int> headers, String key) {
    final index = headers[key];
    if (index == null || index >= row.length) return null;
    final value = row[index].toString().trim();
    return value.isEmpty ? null : value;
  }
  
  static int? _getIntValue(List<dynamic> row, Map<String, int> headers, String key) {
    final strValue = _getStringValue(row, headers, key);
    if (strValue == null) return null;
    return int.tryParse(strValue);
  }
  
  @override
  String toString() => 'TransitRoute(id: $routeId, name: $routeShortName)';
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransitRoute && other.routeId == routeId;
  }
  
  @override
  int get hashCode => routeId.hashCode;
}
