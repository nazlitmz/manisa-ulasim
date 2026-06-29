/// Kullanıcı konum modeli
class UserLocation {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  
  UserLocation({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.heading,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  /// Kopya oluştur (bazı alanları değiştirerek)
  UserLocation copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? accuracy,
    double? speed,
    double? heading,
    DateTime? timestamp,
  }) {
    return UserLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
    );
  }
  
  /// Konum geçerli mi?
  bool get isValid => latitude != 0 && longitude != 0;
  
  /// Konum ne kadar eski?
  Duration get age => DateTime.now().difference(timestamp);
  
  /// Konum çok eski mi? (5 dakikadan fazla)
  bool get isStale => age.inMinutes > 5;
  
  /// Doğruluk kabul edilebilir mi? (100 metreden az)
  bool get hasAcceptableAccuracy => accuracy != null && accuracy! < 100;
  
  /// Formatlanmış koordinatlar
  String get formattedCoordinates => 
    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  
  @override
  String toString() => 'UserLocation($formattedCoordinates)';
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserLocation &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }
  
  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

/// Konum durumu
enum LocationStatus {
  /// Konum servisi başlatılmadı
  initial,
  
  /// Konum izni bekleniyor
  requestingPermission,
  
  /// Konum alınıyor
  loading,
  
  /// Konum başarıyla alındı
  success,
  
  /// Konum izni reddedildi
  permissionDenied,
  
  /// Konum servisi kapalı
  serviceDisabled,
  
  /// Konum alınamadı
  error,
}

/// Konum izin durumu
enum LocationPermissionStatus {
  /// İzin durumu bilinmiyor
  unknown,
  
  /// İzin verildi
  granted,
  
  /// Sadece uygulama açıkken izin verildi
  grantedLimited,
  
  /// İzin reddedildi
  denied,
  
  /// İzin kalıcı olarak reddedildi
  deniedForever,
}
