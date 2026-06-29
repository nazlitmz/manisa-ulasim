/// Yolculuk kaydı modeli
class TripRecord {
  final int? id;
  final String routeId;
  final String routeShortName;
  final String boardingStopId;
  final String boardingStopName;
  final String alightingStopId;
  final String alightingStopName;
  final String tripDate; // YYYY-MM-DD
  final String tripTime; // HH:MM
  final int dayOfWeek; // 1-7 (Monday-Sunday)
  final int? durationMinutes;
  final DateTime createdAt;

  TripRecord({
    this.id,
    required this.routeId,
    required this.routeShortName,
    required this.boardingStopId,
    required this.boardingStopName,
    required this.alightingStopId,
    required this.alightingStopName,
    required this.tripDate,
    required this.tripTime,
    required this.dayOfWeek,
    this.durationMinutes,
    required this.createdAt,
  });

  /// Map'ten oluştur (veritabanından)
  factory TripRecord.fromMap(Map<String, dynamic> map) {
    return TripRecord(
      id: map['id'] as int?,
      routeId: map['route_id'] as String,
      routeShortName: map['route_short_name'] as String,
      boardingStopId: map['boarding_stop_id'] as String,
      boardingStopName: map['boarding_stop_name'] as String,
      alightingStopId: map['alighting_stop_id'] as String,
      alightingStopName: map['alighting_stop_name'] as String,
      tripDate: map['trip_date'] as String,
      tripTime: map['trip_time'] as String,
      dayOfWeek: map['day_of_week'] as int,
      durationMinutes: map['duration_minutes'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// Map'e dönüştür (veritabanına)
  Map<String, dynamic> toMap() {
    return {
      'route_id': routeId,
      'route_short_name': routeShortName,
      'boarding_stop_id': boardingStopId,
      'boarding_stop_name': boardingStopName,
      'alighting_stop_id': alightingStopId,
      'alighting_stop_name': alightingStopName,
      'trip_date': tripDate,
      'trip_time': tripTime,
      'day_of_week': dayOfWeek,
      'duration_minutes': durationMinutes,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  /// Tarih formatı (kullanıcı dostu)
  String get formattedDate {
    try {
      final date = DateTime.parse(tripDate);
      return '${date.day}.${date.month}.${date.year}';
    } catch (_) {
      return tripDate;
    }
  }

  /// Gün adı (Türkçe)
  String get dayName {
    switch (dayOfWeek) {
      case 1:
        return 'Pazartesi';
      case 2:
        return 'Salı';
      case 3:
        return 'Çarşamba';
      case 4:
        return 'Perşembe';
      case 5:
        return 'Cuma';
      case 6:
        return 'Cumartesi';
      case 7:
        return 'Pazar';
      default:
        return '';
    }
  }

  /// Güzergah özeti
  String get routeSummary => '$boardingStopName → $alightingStopName';

  @override
  String toString() =>
      'TripRecord(${routeShortName}: $routeSummary @ $tripTime)';
}
