import 'package:flutter/material.dart';

import '../models/stop_model.dart';

/// Durak kartı widget'ı
class StopCard extends StatelessWidget {
  final Stop stop;
  final bool showDistance;
  final VoidCallback? onTap;

  const StopCard({
    super.key,
    required this.stop,
    this.showDistance = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Durak ikonu
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: stop.isWheelchairAccessible
                      ? theme.colorScheme.secondary.withOpacity(0.1)
                      : theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.directions_bus,
                  color: stop.isWheelchairAccessible
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.primary,
                ),
              ),

              const SizedBox(width: 16),

              // Durak bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.stopName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Mesafe
                        if (showDistance && stop.distanceFromUser != null) ...[
                          Icon(
                            Icons.directions_walk,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            stop.formattedDistance,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                        ],

                        // Erişilebilirlik
                        if (stop.hasWheelchairInfo)
                          Icon(
                            stop.isWheelchairAccessible
                                ? Icons.accessible
                                : Icons.not_accessible,
                            size: 14,
                            color: stop.isWheelchairAccessible
                                ? theme.colorScheme.secondary
                                : Colors.orange,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Ok ikonu
              Icon(
                Icons.chevron_right,
                color: theme.disabledColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
