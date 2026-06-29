import 'package:flutter/material.dart';

import '../models/route_model.dart';

/// Hat kartı widget'ı
class RouteCard extends StatelessWidget {
  final TransitRoute route;
  final VoidCallback? onTap;
  final bool showDetails;
  final bool isDisabled;
  final String? disabledReason;

  const RouteCard({
    super.key,
    required this.route,
    this.onTap,
    this.showDetails = true,
    this.isDisabled = false,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isDisabled ? Colors.grey.shade50 : null,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isDisabled ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    // Hat numarası
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isDisabled ? Colors.grey : route.color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isDisabled
                            ? null
                            : [
                                BoxShadow(
                                  color: route.color.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Center(
                        child: Text(
                          route.routeShortName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isDisabled
                                ? Colors.grey.shade600
                                : route.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Hat bilgileri
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route.routeLongName,
                            style: theme.textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (showDetails) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  route.typeIcon,
                                  size: 14,
                                  color: isDisabled
                                      ? Colors.grey.shade500
                                      : theme.textTheme.bodySmall?.color,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  route.typeName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isDisabled
                                        ? Colors.grey.shade500
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Durum ikonu veya ok
                    if (isDisabled)
                      Icon(
                        Icons.schedule,
                        color: Colors.orange.shade600,
                        size: 20,
                      )
                    else if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        color: theme.disabledColor,
                      ),
                  ],
                ),

                // Devre dışı nedeni
                if (isDisabled && disabledReason != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            disabledReason!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
