// lib/models/operating_hours.dart

class OperatingHoursStatus {
  final bool isOperating;
  final bool showWarning;
  final String title;
  final String message;
  final String color; // 'red' veya 'orange'

  OperatingHoursStatus({
    required this.isOperating,
    required this.showWarning,
    required this.title,
    required this.message,
    required this.color,
  });
}

class OperatingHours {
  static OperatingHoursStatus getStatus() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final currentMinutes = hour * 60 + minute;

    // Çalışma saatleri: 06:00 - 23:00
    const int openTime = 6 * 60; // 360 dakika
    const int closeTime = 23 * 60; // 1380 dakika

    if (currentMinutes >= openTime && currentMinutes < closeTime) {
      // Açık saatlerde
      if (currentMinutes >= (23 * 60 - 60)) {
        // Kapanışa 1 saat kala uyarı
        return OperatingHoursStatus(
          isOperating: true,
          showWarning: true,
          title: 'Kapanış Yaklaşıyor',
          message: 'Otobüsler yakında çalışmayı durdurabilir.',
          color: 'orange',
        );
      }
      return OperatingHoursStatus(
        isOperating: true,
        showWarning: false,
        title: 'Açık',
        message: 'Normal çalışma saatleri',
        color: 'green',
      );
    } else {
      // Kapalı saatlerde
      return OperatingHoursStatus(
        isOperating: false,
        showWarning: true,
        title: 'Kapalı',
        message: 'Otobüsler şu an çalışmıyor (06:00 - 23:00)',
        color: 'red',
      );
    }
  }
}
