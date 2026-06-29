import 'package:flutter/material.dart';
import '../services/delay_prediction_service.dart';

/// Gecikme göstergesi widget'ı
///
/// Kullanım:
/// ```dart
/// DelayIndicator(
///   prediction: delayPrediction,
///   compact: false,
/// )
/// ```
class DelayIndicator extends StatelessWidget {
  final DelayPrediction prediction;
  final bool compact;

  const DelayIndicator({
    super.key,
    required this.prediction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildExpanded(context);
  }

  /// Kompakt görünüm (liste item'lar için)
  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getStatusColor();
    final icon = _getStatusIcon();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            prediction.userMessage,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Genişletilmiş görünüm (detay sayfalar için)
  Widget _buildExpanded(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getStatusColor();
    final icon = _getStatusIcon();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.userMessage,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prediction.reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (prediction.isHighConfidence) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.psychology, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  'AI Tahmini (%${(prediction.confidence * 100).toInt()} güven)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (prediction.statusColor) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.amber;
      case 'orange':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    if (prediction.isOnTime) return Icons.check_circle;
    if (prediction.isEarly) return Icons.fast_forward;
    if (prediction.delayMinutes <= 5) return Icons.warning;
    if (prediction.delayMinutes <= 10) return Icons.error;
    return Icons.cancel;
  }
}

/// Gecikme listesi widget'ı (birden fazla tahmin için)
class DelayIndicatorList extends StatelessWidget {
  final List<DelayPrediction> predictions;

  const DelayIndicatorList({
    super.key,
    required this.predictions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.psychology,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'AI Gecikme Tahminleri',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        ...predictions.map((prediction) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DelayIndicator(prediction: prediction),
            )),
      ],
    );
  }
}
