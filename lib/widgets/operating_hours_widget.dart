import 'package:flutter/material.dart';
import '../models/operating_hours.dart';

/// Otobüs çalışma saatleri uyarı widget'ı
class OperatingHoursWarning extends StatelessWidget {
  const OperatingHoursWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final status = OperatingHours.getStatus();

    // Normal çalışma saatlerinde ve uyarı yoksa gösterme
    if (status.isOperating && !status.showWarning) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getBackgroundColor(status.color),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getBorderColor(status.color), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _getBorderColor(status.color).withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getBorderColor(status.color).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getIcon(status.color),
              color: _getBorderColor(status.color),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _getBorderColor(status.color),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getBackgroundColor(String color) {
    switch (color) {
      case 'red':
        return Colors.red.shade50;
      case 'orange':
        return Colors.orange.shade50;
      case 'green':
        return Colors.green.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  Color _getBorderColor(String color) {
    switch (color) {
      case 'red':
        return Colors.red.shade700;
      case 'orange':
        return Colors.orange.shade700;
      case 'green':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  IconData _getIcon(String color) {
    switch (color) {
      case 'red':
        return Icons.nightlight_round;
      case 'orange':
        return Icons.warning_amber_rounded;
      case 'green':
        return Icons.directions_bus;
      default:
        return Icons.info_outline;
    }
  }
}

/// Kompakt çalışma saatleri badge'i (app bar için)
class OperatingHoursBadge extends StatelessWidget {
  const OperatingHoursBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final status = OperatingHours.getStatus();

    if (status.isOperating && !status.showWarning) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color == 'red' ? Colors.red : Colors.orange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.color == 'red'
                ? Icons.nightlight_round
                : Icons.warning_amber_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            status.isOperating ? 'Son Seferler' : 'Kapalı',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Çalışma saatleri bilgi dialog'u
void showOperatingHoursDialog(BuildContext context) {
  final status = OperatingHours.getStatus();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            status.isOperating ? Icons.directions_bus : Icons.nightlight_round,
            color: status.isOperating ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Çalışma Saatleri')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Durum
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: status.isOperating
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  status.isOperating
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  color: status.isOperating ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: status.isOperating
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Çalışma saatleri
          const Text(
            'Manisa Belediyesi Otobüsleri',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildTimeRow('İlk Sefer', '06:00'),
          _buildTimeRow('Son Sefer', '23:00'),

          const SizedBox(height: 16),
          Text(
            status.message,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );
}

Widget _buildTimeRow(String label, String time) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        const Spacer(),
        Text(
          time,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
  );
}
