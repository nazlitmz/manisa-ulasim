import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stop_model.dart';
import '../providers/routes_provider.dart';
import '../providers/location_provider.dart';
import '../providers/stops_provider.dart';
import '../providers/accessibility_provider.dart';
import '../services/tts_service.dart';
import '../config/routes.dart';

/// Rota sonuçları ekranı
/// Hedefe giden hat seçeneklerini gösterir
class RouteResultsScreen extends StatefulWidget {
  const RouteResultsScreen({super.key});

  @override
  State<RouteResultsScreen> createState() => _RouteResultsScreenState();
}

class _RouteResultsScreenState extends State<RouteResultsScreen> {
  final TtsService _ttsService = TtsService();
  Stop? _destination;
  Stop? _fromStop;
  List<RouteOption> _routeOptions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args['destination'] != null && _destination == null) {
      _destination = args['destination'] as Stop;
      _findRoutes();
    }
  }

  Future<void> _findRoutes() async {
    if (_destination == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final locationProvider = context.read<LocationProvider>();
      final stopsProvider = context.read<StopsProvider>();
      final routesProvider = context.read<RoutesProvider>();

      final userLocation = locationProvider.effectiveLocation;
      await stopsProvider.findNearbyStops(
        latitude: userLocation.latitude,
        longitude: userLocation.longitude,
        radiusMeters: 500,
      );

      if (stopsProvider.nearbyStops.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Yakınızda durak bulunamadı. Lütfen bir durağa yaklaşın.';
        });
        _announceError();
        return;
      }

      _fromStop = stopsProvider.nearbyStops.first;

      _routeOptions = await routesProvider.findRoutesToDestination(
        fromStop: _fromStop!,
        toStop: _destination!,
      );

      setState(() {
        _isLoading = false;
        if (_routeOptions.isEmpty) {
          _errorMessage = 'Bu güzergah için uygun hat bulunamadı.';
        }
      });

      _announceResults();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Rotalar hesaplanırken hata oluştu: $e';
      });
      _announceError();
    }
  }

  Future<void> _announceResults() async {
    final accessibility = context.read<AccessibilityProvider>();
    if (!accessibility.screenReaderEnabled) return;

    final activeRoutes =
        _routeOptions.where((r) => !r.isDeparturePassed).toList();

    if (activeRoutes.isNotEmpty) {
      final bestRoute = activeRoutes.first;
      await _ttsService.speak('${activeRoutes.length} aktif rota bulundu. '
          '${_fromStop?.stopName ?? "Konumunuz"} durağından ${_destination?.stopName ?? "Hedef"} durağına. '
          'En hızlı seçenek: ${bestRoute.route.routeShortName} numaralı hat, '
          'tahmini süre ${bestRoute.formattedDuration}. '
          '${bestRoute.timeUntilDeparture}.');
    } else {
      await _ttsService.speak(
          'Bugün için aktif sefer bulunmamaktadır. Lütfen yarın tekrar deneyin.');
    }
  }

  Future<void> _announceError() async {
    final accessibility = context.read<AccessibilityProvider>();
    if (!accessibility.screenReaderEnabled) return;
    await _ttsService.speak(_errorMessage ?? 'Bir hata oluştu.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota Seçenekleri'),
      ),
      body: Column(
        children: [
          if (_destination != null) _buildRouteSummary(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildError(theme)
                    : _buildRouteOptions(theme),
          ),
        ],
      ),
    );
  }

  /// Güzergah özeti (üstteki başlangıç → hedef bandı)
  Widget _buildRouteSummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.primary.withOpacity(0.1),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Başlangıç', style: theme.textTheme.labelSmall),
                Text(
                  _fromStop?.stopName ?? 'Konumunuz',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, color: theme.colorScheme.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Hedef', style: theme.textTheme.labelSmall),
                Text(
                  _destination?.stopName ?? '',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ana liste: aktif seferler üstte (süreye göre), seferi bitenler altta
  Widget _buildRouteOptions(ThemeData theme) {
    // Provider zaten sıralamış ve ayırmıştır:
    // - upcomingDepartures.isNotEmpty  → aktif
    // - upcomingDepartures.isEmpty     → seferi biten
    final activeRoutes =
        _routeOptions.where((r) => r.upcomingDepartures.isNotEmpty).toList();
    final expiredRoutes =
        _routeOptions.where((r) => r.upcomingDepartures.isEmpty).toList();

    if (activeRoutes.isEmpty && expiredRoutes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule_outlined,
                  size: 64, color: theme.disabledColor),
              const SizedBox(height: 16),
              Text('Bugün Sefer Yok', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Bu güzergah için bugün sefer bulunmamaktadır.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _findRoutes,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ═══════════════════════════════════════════
        // AKTİF SEFERLER — en kısa süre en üstte
        // ═══════════════════════════════════════════
        if (activeRoutes.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.directions_bus,
            title: 'Aktif Seferler',
            count: activeRoutes.length,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          ...activeRoutes.map((option) => _RouteOptionCard(
                option: option,
                onTap: () => _selectRoute(option),
                onNotifyDriver: () => _notifyDriver(option),
              )),
        ],

        // ═══════════════════════════════════════════
        // ŞU AN SEFER YOK — altta ayrı bölüm
        // ═══════════════════════════════════════════
        if (expiredRoutes.isNotEmpty) ...[
          if (activeRoutes.isNotEmpty) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                    child: Divider(color: Colors.grey.shade400, thickness: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.history,
                        size: 20, color: Colors.grey.shade600),
                  ),
                ),
                Expanded(
                    child: Divider(color: Colors.grey.shade400, thickness: 1)),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _SectionHeader(
            icon: Icons.schedule_outlined,
            title: 'Maalesef Şu An Sefer Yok',
            count: expiredRoutes.length,
            color: Colors.red,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Aşağıdaki hatların bugünkü son seferleri tamamlanmıştır.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.red.shade600),
            ),
          ),
          ...expiredRoutes.map((option) => _ExpiredRouteCard(option: option)),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 64, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text('Rota Bulunamadı', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _findRoutes,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  void _selectRoute(RouteOption option) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      _ttsService.speak('${option.route.routeShortName} hattı seçildi. '
          '${option.fromStop.stopName} durağından binin. '
          '${option.toStop.stopName} durağında inin. '
          'Tahmini süre: ${option.formattedDuration}.');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _RouteDetailSheet(option: option),
    );
  }

  void _notifyDriver(RouteOption option) {
    Navigator.pushNamed(
      context,
      AppRoutes.driverNotification,
      arguments: {
        'route': option.route,
        'fromStop': option.fromStop,
        'departure': option.nextDeparture,
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Bölüm başlığı (yeşil / kırmızı)
// ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final MaterialColor color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color.shade700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Seferi biten rota kartı (sadeleştirilmiş, tıklanamaz)
// ─────────────────────────────────────────────────────────
class _ExpiredRouteCard extends StatelessWidget {
  final RouteOption option;

  const _ExpiredRouteCard({required this.option});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = option.route;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Opacity(
        opacity: 0.65,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Hat numarası (gri)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  route.routeShortName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.routeLongName,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.block, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 4),
                        Text(
                          'Bugünkü seferler sona erdi',
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade400),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.schedule, color: Colors.grey.shade400, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Aktif rota kartı
// ─────────────────────────────────────────────────────────
class _RouteOptionCard extends StatelessWidget {
  final RouteOption option;
  final VoidCallback onTap;
  final VoidCallback onNotifyDriver;

  const _RouteOptionCard({
    required this.option,
    required this.onTap,
    required this.onNotifyDriver,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = option.route;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hat numarası + adı
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: route.color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      route.routeShortName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: route.textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      route.routeLongName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Süre + sonraki kalkış
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.access_time,
                    label: option.timeUntilDeparture,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: option.formattedDuration,
                    color: theme.colorScheme.secondary,
                  ),
                  const Spacer(),
                  if (option.route.routeType == 3)
                    Icon(Icons.accessible,
                        color: theme.colorScheme.secondary, size: 20),
                ],
              ),

              // Yaklaşan seferler
              if (option.upcomingDepartures.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Bugünün Seferleri (${option.upcomingDepartures.length}):',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: option.upcomingDepartures
                      .take(8)
                      .map((time) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    theme.colorScheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ))
                      .toList(),
                ),
                if (option.upcomingDepartures.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${option.upcomingDepartures.length - 8} sefer daha',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
              ],

              const SizedBox(height: 12),

              // Butonlar
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Detaylar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onNotifyDriver,
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Şoföre Bildir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Bilgi chip'i
// ─────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Rota detay sheet'i
// ─────────────────────────────────────────────────────────
class _RouteDetailSheet extends StatelessWidget {
  final RouteOption option;

  const _RouteDetailSheet({required this.option});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDeparturesPassed = option.isDeparturePassed;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Hat başlığı
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: allDeparturesPassed
                            ? Colors.grey
                            : option.route.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        option.route.routeShortName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: allDeparturesPassed
                              ? Colors.white
                              : option.route.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(option.route.routeLongName,
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                if (allDeparturesPassed)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.red.shade700, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Seferler Sona Erdi',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Bu hattın bugünkü tüm seferleri tamamlanmıştır.',
                                style: TextStyle(
                                  color: Colors.red.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailItem(
                          icon: Icons.trip_origin,
                          title: 'Biniş Durağı',
                          value: option.fromStop.stopName),
                      const SizedBox(height: 12),
                      _DetailItem(
                          icon: Icons.location_on,
                          title: 'İniş Durağı',
                          value: option.toStop.stopName),
                      const SizedBox(height: 12),
                      _DetailItem(
                          icon: Icons.timer,
                          title: 'Tahmini Süre',
                          value: option.formattedDuration),
                      if (option.nextDeparture != null) ...[
                        const SizedBox(height: 12),
                        _DetailItem(
                          icon: Icons.access_time,
                          title: 'Sonraki Kalkış',
                          value:
                              '${option.nextDeparture} (${option.timeUntilDeparture})',
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (option.upcomingDepartures.length > 1) ...[
                        Text(
                          'Bugünün Tüm Seferleri (${option.upcomingDepartures.length})',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.primary.withOpacity(0.2),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: option.upcomingDepartures.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: theme.colorScheme.primary.withOpacity(0.1),
                            ),
                            itemBuilder: (context, index) {
                              final time = option.upcomingDepartures[index];
                              final isNext = index == 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                color: isNext
                                    ? theme.colorScheme.primary
                                        .withOpacity(0.05)
                                    : null,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isNext
                                            ? Colors.green
                                            : Colors.grey.shade300,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      time,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isNext
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isNext
                                            ? theme.colorScheme.primary
                                            : Colors.black87,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (isNext)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Sonraki',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),

                // Uyarı notu
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: theme.colorScheme.tertiary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: theme.colorScheme.tertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bu bir karar destek sistemidir. Gerçek sefer saatleri '
                          'trafik koşullarına göre değişebilir.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Detay öğesi
// ─────────────────────────────────────────────────────────
class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelSmall),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}
