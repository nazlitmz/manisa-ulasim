import 'package:flutter/material.dart';
import '../services/city_detection_service.dart';
import '../services/city_database_manager.dart';

class PopularPlace {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final IconData icon;

  const PopularPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.icon,
  });
}

const List<PopularPlace> _manisaPlaces = [
  PopularPlace(
      id: 'cbu',
      name: 'CBÜ Kampüs',
      category: 'Üniversite',
      latitude: 38.6767,
      longitude: 27.3114,
      icon: Icons.school),
  PopularPlace(
      id: 'cbuhastane',
      name: 'CBÜ Hastanesi',
      category: 'Hastane',
      latitude: 38.611043,
      longitude: 27.378358,
      icon: Icons.local_hospital),
  PopularPlace(
      id: 'sehirhastane',
      name: 'Şehir Hastanesi',
      category: 'Hastane',
      latitude: 38.6095,
      longitude: 27.458,
      icon: Icons.healing),
  PopularPlace(
      id: 'terminal',
      name: 'Manisa Terminal',
      category: 'Ulaşım',
      latitude: 38.6378,
      longitude: 27.4460,
      icon: Icons.directions_bus),
  PopularPlace(
      id: 'meydan',
      name: 'Manisa Meydan',
      category: 'Merkez',
      latitude: 38.6127,
      longitude: 27.4297,
      icon: Icons.location_city),
  PopularPlace(
      id: 'forum',
      name: 'Forum Magnesia AVM',
      category: 'AVM',
      latitude: 38.616165,
      longitude: 27.400331,
      icon: Icons.shopping_bag),
  PopularPlace(
      id: 'prime',
      name: 'Prime Mall AVM',
      category: 'AVM',
      latitude: 38.61566,
      longitude: 27.39725,
      icon: Icons.shopping_bag),
  PopularPlace(
      id: 'meydanavm',
      name: 'Meydan AVM',
      category: 'AVM',
      latitude: 38.611139,
      longitude: 27.387089,
      icon: Icons.shopping_bag),
  PopularPlace(
      id: 'muradiye',
      name: 'Muradiye',
      category: 'Semt',
      latitude: 38.6509,
      longitude: 27.3309,
      icon: Icons.location_city),
  PopularPlace(
      id: 'otogar',
      name: 'Otogar',
      category: 'Ulaşım',
      latitude: 38.6194,
      longitude: 27.4382,
      icon: Icons.directions_bus),
];

const List<PopularPlace> _cyprusPlaces = [
  PopularPlace(
      id: 'neu',
      name: 'NEÜ Kampüs',
      category: 'Üniversite',
      latitude: 35.1979,
      longitude: 33.3568,
      icon: Icons.school),
  PopularPlace(
      id: 'dau',
      name: 'DAÜ Kampüs',
      category: 'Üniversite',
      latitude: 35.1504,
      longitude: 33.9077,
      icon: Icons.school),
  PopularPlace(
      id: 'lefkosa_terminal',
      name: 'Lefkoşa Terminal',
      category: 'Ulaşım',
      latitude: 35.1731,
      longitude: 33.3595,
      icon: Icons.directions_bus),
  PopularPlace(
      id: 'girne_liman',
      name: 'Girne Limanı',
      category: 'Turizm',
      latitude: 35.3411,
      longitude: 33.3196,
      icon: Icons.anchor),
  PopularPlace(
      id: 'magusa_kale',
      name: 'Mağusa Kalesi',
      category: 'Turizm',
      latitude: 35.1233,
      longitude: 33.9428,
      icon: Icons.castle),
  PopularPlace(
      id: 'lefkosa_merkez',
      name: 'Lefkoşa Merkez',
      category: 'Merkez',
      latitude: 35.1856,
      longitude: 33.3823,
      icon: Icons.location_city),
  PopularPlace(
      id: 'girne_merkez',
      name: 'Girne Merkez',
      category: 'Merkez',
      latitude: 35.3414,
      longitude: 33.3193,
      icon: Icons.location_city),
  PopularPlace(
      id: 'lefkosa_hastane',
      name: 'Burhan Nalbantoğlu Hastanesi',
      category: 'Hastane',
      latitude: 35.1724,
      longitude: 33.3646,
      icon: Icons.local_hospital),
  PopularPlace(
      id: 'guzelyurt_merkez',
      name: 'Güzelyurt Merkez',
      category: 'Merkez',
      latitude: 35.2009,
      longitude: 32.9970,
      icon: Icons.location_city),
  PopularPlace(
      id: 'ercan',
      name: 'Ercan Havalimanı',
      category: 'Ulaşım',
      latitude: 35.1547,
      longitude: 33.4961,
      icon: Icons.flight),
];

class PopularPlacesConfig {
  static List<PopularPlace> get current {
    final city = CityDetectionService.instance.currentCity;
    if (city == SupportedCity.cyprus) return _cyprusPlaces;
    return _manisaPlaces;
  }

  static List<PopularPlace> get featured {
    final city = CityDetectionService.instance.currentCity;
    if (city == SupportedCity.cyprus) {
      return [
        _cyprusPlaces[0],
        _cyprusPlaces[2],
        _cyprusPlaces[3],
        _cyprusPlaces[5]
      ];
    }
    return [
      _manisaPlaces[5],
      _manisaPlaces[0],
      _manisaPlaces[2],
      _manisaPlaces[3]
    ];
  }

  static String get cityName {
    final city = CityDetectionService.instance.currentCity;
    if (city == SupportedCity.cyprus) return 'KKTC Ulaşım';
    return 'Manisa Ulaşım';
  }

  static Color placeColor(PopularPlace place) {
    switch (place.category) {
      case 'Üniversite':
        return Colors.blue;
      case 'Hastane':
        return Colors.red;
      case 'AVM':
        return Colors.purple;
      case 'Ulaşım':
        return Colors.green;
      case 'Turizm':
        return Colors.teal;
      case 'Merkez':
        return Colors.indigo;
      default:
        return Colors.orange;
    }
  }
}
