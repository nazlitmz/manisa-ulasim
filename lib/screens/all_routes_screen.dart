import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/route_model.dart';
import '../providers/routes_provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/favorites_provider.dart';
import '../services/tts_service.dart';
import '../services/database_service.dart';
import '../services/city_detection_service.dart';
import '../services/city_database_manager.dart';
import '../services/gtfs_service_facade.dart';
import '../services/kktc_intercity_service.dart';
import 'route_map_screen.dart';

// ============================================================
// Kategori tanımları
// ============================================================
class _RouteCategory {
  final String label;
  final String emoji;
  final Color color;
  final List<String> keywords; // route_long_name içinde aranacak
  final bool isIntercity; // Şehirlerarası mı?
  final bool isAirport; // Havalimanı ulaşımı (KIBHAS) mı?

  const _RouteCategory({
    required this.label,
    required this.emoji,
    required this.color,
    required this.keywords,
    this.isIntercity = false,
    this.isAirport = false,
  });
}

const _categories = [
  _RouteCategory(
    label: 'Tümü',
    emoji: '🗺️',
    color: Color(0xFF455A64),
    keywords: [],
  ),
  _RouteCategory(
    label: 'Lefkoşa',
    emoji: '🏛️',
    color: Color(0xFF1A237E),
    keywords: [
      'LEFKOŞA',
      'LEFKOSA',
      'HASPOLAT',
      'DİKMEN',
      'GÖNYELİ',
      'YENİKENT',
      'GÖÇMENKÖY',
      'ŞEHİRİÇİ'
    ],
  ),
  _RouteCategory(
    label: 'Girne',
    emoji: '⚓',
    color: Color(0xFF0097A7),
    keywords: [
      'GİRNE',
      'GIRNE',
      'ÇATALKÖY',
      'ARAPKÖY',
      'BELLAPAİS',
      'OZANKÖY',
      'İLİM'
    ],
  ),
  _RouteCategory(
    label: 'Mağusa',
    emoji: '🏰',
    color: Color(0xFF2E7D32),
    keywords: ['MAĞUSA', 'MAGUSA'],
  ),
  _RouteCategory(
    label: 'Güzelyurt',
    emoji: '🍊',
    color: Color(0xFFE65100),
    keywords: ['GÜZELYURT', 'GUZELYURT', 'LEFKE'],
  ),
  _RouteCategory(
    label: 'Kampüs',
    emoji: '🎓',
    color: Color(0xFF6A1B9A),
    keywords: ['KAMPÜS', 'KAMPUS'],
  ),
  // Şehirlerarası (İtimat + Kombos)
  _RouteCategory(
    label: 'Şehirlerarası',
    emoji: '🚌',
    color: Color(0xFF37474F),
    keywords: [],
    isIntercity: true,
    isAirport: false,
  ),
  // Havalimanı Ulaşımı (KIBHAS)
  _RouteCategory(
    label: 'Havalimanı\nUlaşımı',
    emoji: '✈️',
    color: Color(0xFF1565C0),
    keywords: [],
    isIntercity: true,
    isAirport: true,
  ),
];

// ============================================================
// Renk yardımcıları
// ============================================================
Color _cyprusRouteColor(TransitRoute route) {
  final combined =
      '${route.routeLongName} ${route.routeShortName}'.toUpperCase();
  for (final cat in _categories.skip(1)) {
    if (cat.isIntercity) continue;
    if (cat.keywords.any((kw) => combined.contains(kw))) return cat.color;
  }
  return const Color(0xFF546E7A);
}

Color _textColorFor(Color bg) =>
    bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;

bool _routeMatchesCategory(TransitRoute route, _RouteCategory cat) {
  if (cat.keywords.isEmpty) return true;
  final combined =
      '${route.routeLongName} ${route.routeShortName}'.toUpperCase();
  return cat.keywords.any((kw) => combined.contains(kw));
}

// Şirket rengi
Color _intercityCompanyColor(String company) {
  switch (company) {
    case 'KIBHAS':
      return const Color(0xFF1565C0);
    case 'İtimat':
      return const Color(0xFFE65100);
    case 'Kombos':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF455A64);
  }
}

// ============================================================
// Screen
// ============================================================
class AllRoutesScreen extends StatefulWidget {
  const AllRoutesScreen({super.key});

  @override
  State<AllRoutesScreen> createState() => _AllRoutesScreenState();
}

class _AllRoutesScreenState extends State<AllRoutesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TtsService _ttsService = TtsService();
  final DatabaseService _databaseService = DatabaseService();

  _RouteCategory? _selectedCategory;
  String _intercitySearch = ''; // Şehirlerarası arama

  bool get _isManisa =>
      CityDetectionService.instance.currentCity == null ||
      CityDetectionService.instance.currentCity == SupportedCity.manisa;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoutes());
  }

  Future<void> _loadRoutes() async {
    await context.read<RoutesProvider>().loadAllRoutes();
    if (!_isManisa) return;
    setState(() => _selectedCategory = _categories[0]);
    _announceResults();
  }

  Future<void> _announceResults() async {
    final accessibility = context.read<AccessibilityProvider>();
    if (!accessibility.screenReaderEnabled) return;
    final count = context.read<RoutesProvider>().filteredRoutes.length;
    await _ttsService.speak('Tüm hatlar ekranı. $count hat listeleniyor.');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TransitRoute> _filteredByCategory(List<TransitRoute> all) {
    if (_selectedCategory == null || _selectedCategory!.keywords.isEmpty) {
      return all;
    }
    return all
        .where((r) => _routeMatchesCategory(r, _selectedCategory!))
        .toList();
  }

  // ── Şehirlerarası hat listesi ──────────────────────────────
  List<KktcBusLine> _filteredIntercityLines() {
    // isAirport=true → sadece KIBHAS, isAirport=false → İtimat+Kombos
    final baseLines = (_selectedCategory?.isAirport ?? false)
        ? kKktcBusLines.where((l) => l.company == 'KIBHAS').toList()
        : kKktcBusLines.where((l) => l.company != 'KIBHAS').toList();
    if (_intercitySearch.trim().isEmpty) return baseLines;
    final q = _intercitySearch
        .trim()
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
    return baseLines.where((l) {
      final text = '${l.from} ${l.to} ${l.company} ${l.fromCity} ${l.toCity}'
          .toLowerCase()
          .replaceAll('ı', 'i')
          .replaceAll('ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('ş', 's')
          .replaceAll('ö', 'o')
          .replaceAll('ç', 'c');
      return text.contains(q);
    }).toList();
  }

  void _navigateToMap(BuildContext sheetCtx, TransitRoute route) {
    Navigator.pop(sheetCtx);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)));
  }

  // ── Saat modalı ────────────────────────────────────────────
  void _showRouteTimes(TransitRoute route) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String stopName = '';
      List<String> departureTimes = [];
      bool hasNoTimeData = false;

      if (_isManisa) {
        final stops = await _databaseService
            .getStopsForRouteDirection(route.routeId, direction: 1);
        if (!mounted) return;
        Navigator.pop(context);
        if (stops.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Bu hat için durak bilgisi bulunamadı.')));
          return;
        }
        stopName = stops.first.stopName;
        departureTimes = await _databaseService.getUpcomingDeparturesForStop(
            route.routeShortName, stops.first.stopId,
            direction: 1);
      } else {
        final rawStops = await GtfsService.instance
            .stopsForRoute(routeId: route.routeId, direction: 0);
        if (!mounted) return;
        Navigator.pop(context);
        if (rawStops.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Bu hat için durak bilgisi bulunamadı.')));
          return;
        }
        stopName = rawStops.first['stop_name']?.toString() ?? '';
        hasNoTimeData = true;
      }

      if (!mounted) return;
      _showTimesBottomSheet(
        route: route,
        stopName: stopName,
        departureTimes: departureTimes,
        hasNoTimeData: hasNoTimeData,
        theme: theme,
        isDark: isDark,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seferler yüklenirken hata oluştu: $e')));
    }
  }

  // ── Şehirlerarası durak listesi ──────────────────────────
  void _showIntercityStops(KktcBusLine line, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Handle + başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: color, borderRadius: BorderRadius.circular(8)),
                      child: Text(line.company,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${line.fromCity} → ${line.toCity}',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${line.stops.length} durak  •  ~${line.durationMinutes} dk',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                ]),
              ),
              // Durak listesi
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPadding),
                  itemCount: line.stops.length,
                  itemBuilder: (context, index) {
                    final stop = line.stops[index];
                    final isFirst = index == 0;
                    final isLast = index == line.stops.length - 1;
                    final dotColor = isFirst
                        ? Colors.green
                        : isLast
                            ? Colors.red
                            : color;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Column(children: [
                            if (!isFirst)
                              Container(
                                  width: 2,
                                  height: 14,
                                  color: color.withOpacity(0.3)),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                            if (!isLast)
                              Container(
                                  width: 2,
                                  height: 14,
                                  color: color.withOpacity(0.3)),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stop.stopName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isFirst || isLast
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (isFirst)
                                  Text('Kalkış noktası',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green.shade600))
                                else if (isLast)
                                  Text('Son durak',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.red.shade600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Şehirlerarası sefer saatleri ──────────────────────────
  void _showIntercityTimes(KktcBusLine line) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _intercityCompanyColor(line.company);
    final upcoming = KktcBusService.instance.nextDepartures(line, max: 20);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Başlık
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(8)),
                    child: Text(line.company,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${line.from}\n→ ${line.to}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 8),
                // Bilgi satırı
                Row(children: [
                  Icon(Icons.timer_outlined,
                      size: 15, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('~${line.durationMinutes} dk yolculuk',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  if (line.phone.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.phone, size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(line.phone,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ]),
                const SizedBox(height: 8),
                // Sıklık
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Text(line.frequency,
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 20),
                Text('Sefer Saatleri (${line.departureTimes.length})',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                // Saat grid
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: line.departureTimes.map((time) {
                    final isNext =
                        upcoming.isNotEmpty && upcoming.first.time == time;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isNext ? color : color.withOpacity(0.09),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isNext ? color : color.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Text(time,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isNext ? Colors.white : color)),
                          if (isNext)
                            Text('Sonraki',
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.white70)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                // Duraklar
                if (line.stops.isNotEmpty) ...[
                  Text('Güzergah Durakları',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...line.stops.asMap().entries.map((e) {
                    final i = e.key;
                    final s = e.value;
                    final isFirst = i == 0;
                    final isLast = i == line.stops.length - 1;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Column(children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: isFirst
                                    ? Colors.green
                                    : isLast
                                        ? Colors.red
                                        : color,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                            if (!isLast)
                              Container(
                                  width: 2,
                                  height: 28,
                                  color: color.withOpacity(0.3)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              s.stopName.replaceAll('KIBHAS — ', ''),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isFirst || isLast
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
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

  void _showTimesBottomSheet({
    required TransitRoute route,
    required String stopName,
    required List<String> departureTimes,
    required bool hasNoTimeData,
    required ThemeData theme,
    required bool isDark,
  }) {
    final routeColor = _isManisa ? route.color : _cyprusRouteColor(route);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: routeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(route.routeShortName,
                        style: TextStyle(
                          color: _textColorFor(routeColor),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(route.routeLongName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.location_on,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(stopName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.grey.shade600)),
                  ),
                ]),
                const SizedBox(height: 24),
                Text(
                  'Sonraki Seferler${departureTimes.isNotEmpty ? ' (${departureTimes.length})' : ''}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (hasNoTimeData)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(children: [
                        Icon(Icons.info_outline,
                            size: 48, color: Colors.orange.shade400),
                        const SizedBox(height: 12),
                        Text('Saat bilgisi mevcut değil.',
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(
                            'Bu hat için sefer saati verisi henüz sisteme eklenmemiştir.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500),
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                else if (departureTimes.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(children: [
                        Icon(Icons.schedule,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('Şu anda aktif sefer bulunamadı.',
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text('Sefer saatleri dışında olabilirsiniz.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500),
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: routeColor.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: departureTimes.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1, color: routeColor.withOpacity(0.1)),
                      itemBuilder: (context, index) {
                        final time = departureTimes[index];
                        final isFirst = index == 0;
                        String displayTime = time;
                        String remainingTime = '';
                        try {
                          final parts = time.split(':');
                          if (parts.length >= 2) {
                            final hour = int.tryParse(parts[0]) ?? 0;
                            final minute = int.tryParse(parts[1]) ?? 0;
                            final adj = hour >= 24 ? hour - 24 : hour;
                            displayTime =
                                '${adj.toString().padLeft(2, '0')}:${parts[1]}';
                            final now = DateTime.now();
                            final dep = DateTime(
                                now.year, now.month, now.day, adj, minute);
                            final diff = dep.difference(now);
                            if (!diff.isNegative) {
                              final mins = diff.inMinutes;
                              remainingTime = mins < 60
                                  ? '$mins dk'
                                  : '${mins ~/ 60}s ${mins % 60}dk';
                            }
                          }
                        } catch (_) {}
                        return Container(
                          color: isFirst ? routeColor.withOpacity(0.05) : null,
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isFirst
                                    ? routeColor
                                    : (isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.access_time,
                                  color: isFirst ? Colors.white : routeColor,
                                  size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(displayTime,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isFirst ? routeColor : null,
                                      )),
                                  if (remainingTime.isNotEmpty)
                                    Text(remainingTime,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: isFirst
                                              ? routeColor
                                              : Colors.grey.shade600,
                                        )),
                                ],
                              ),
                            ),
                            if (isFirst)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text('En yakın sefer',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    )),
                              ),
                          ]),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasNoTimeData
                        ? Colors.orange.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: hasNoTimeData
                            ? Colors.orange.shade200
                            : Colors.blue.shade200),
                  ),
                  child: Row(children: [
                    Icon(
                        hasNoTimeData
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline,
                        size: 20,
                        color: hasNoTimeData
                            ? Colors.orange.shade700
                            : Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasNoTimeData
                            ? 'Kıbrıs toplu taşıma verileri güncellenmektedir.'
                            : 'Sefer saatleri tahminidir. Gerçek kalkış saatleri trafik durumuna göre değişebilir.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasNoTimeData
                              ? Colors.orange.shade900
                              : Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
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

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final routesProvider = context.watch<RoutesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCategory == null
            ? 'Tüm Hatlar'
            : _selectedCategory!.isIntercity
                ? _selectedCategory!.isAirport
                    ? '${_selectedCategory!.emoji} Havalimanı Ulaşımı'
                    : '${_selectedCategory!.emoji} Şehirlerarası Hatlar'
                : _selectedCategory!.label == 'Tümü'
                    ? 'Tüm Hatlar'
                    : '${_selectedCategory!.emoji} ${_selectedCategory!.label} Hatları'),
        leading: _selectedCategory != null
            ? BackButton(onPressed: () {
                setState(() {
                  _selectedCategory = null;
                  _intercitySearch = '';
                  _searchController.clear();
                  routesProvider.searchRoutes('');
                });
              })
            : null,
        actions: [
          Consumer<FavoritesProvider>(
            builder: (context, favorites, _) {
              if (favorites.favoriteRoutes.isEmpty)
                return const SizedBox.shrink();
              return IconButton(
                icon: Badge(
                  label: Text('${favorites.favoriteRoutes.length}'),
                  child: const Icon(Icons.star_rounded),
                ),
                tooltip: 'Favori hatlar',
                onPressed: () => _showFavoriteRoutes(context, favorites),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: routesProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : _selectedCategory == null
                ? _buildCategoryGrid(routesProvider)
                : _selectedCategory!.isIntercity
                    ? _buildIntercityList() // Şehirlerarası / Havalimanı liste
                    : _buildRouteList(routesProvider),
      ),
    );
  }

  // ── Kategori Grid ────────────────────────────────────────────
  Widget _buildCategoryGrid(RoutesProvider routesProvider) {
    final theme = Theme.of(context);
    final allRoutes = routesProvider.allRoutes;

    // Manisa modunda sadece "Tümü" + Şehirlerarası gösterme (sadece Kıbrıs'ta)
    final visibleCategories = _isManisa ? [_categories[0]] : _categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Bölge seçin',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: visibleCategories.length,
            itemBuilder: (context, index) {
              final cat = visibleCategories[index];
              final count = cat.isIntercity
                  ? kKktcBusLines.length
                  : _isManisa
                      ? allRoutes.length
                      : allRoutes
                          .where((r) => _routeMatchesCategory(r, cat))
                          .length;
              return _CategoryCard(
                category: cat,
                routeCount: count,
                onTap: () => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Şehirlerarası Hat Listesi ─────────────────────────────────
  Widget _buildIntercityList() {
    final theme = Theme.of(context);
    final lines = _filteredIntercityLines();

    // Şirkete göre grupla
    final companies = <String>[];
    for (final l in lines) {
      if (!companies.contains(l.company)) companies.add(l.company);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Güzergah veya şehir ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _intercitySearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _intercitySearch = ''))
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => setState(() => _intercitySearch = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.directions_bus,
                size: 18, color: Color(0xFF1565C0)),
            const SizedBox(width: 6),
            Text('${lines.length} hat', style: theme.textTheme.bodyMedium),
          ]),
        ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off,
                          size: 48, color: theme.disabledColor),
                      const SizedBox(height: 16),
                      const Text('Hat bulunamadı'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: companies.length,
                  itemBuilder: (context, ci) {
                    final company = companies[ci];
                    final companyLines =
                        lines.where((l) => l.company == company).toList();
                    final color = _intercityCompanyColor(company);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Şirket başlığı
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(company,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ),
                            const SizedBox(width: 8),
                            Text('${companyLines.length} hat',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500)),
                          ]),
                        ),
                        ...companyLines.map((line) {
                          final isAirport =
                              (_selectedCategory?.isAirport ?? false);
                          return _IntercityRouteCard(
                            line: line,
                            color: color,
                            isAirport: isAirport,
                            onShowTimes: () => _showIntercityTimes(line),
                            // Duraklar sadece KIBHAS'ta ve durak verisi varsa
                            onShowStops: isAirport && line.stops.isNotEmpty
                                ? () => _showIntercityStops(line, color)
                                : null,
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── GTFS Hat Listesi ─────────────────────────────────────────
  Widget _buildRouteList(RoutesProvider routesProvider) {
    final theme = Theme.of(context);
    final all = routesProvider.filteredRoutes;
    final filtered = _filteredByCategory(all);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Hat ara...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        routesProvider.searchRoutes('');
                      })
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: routesProvider.searchRoutes,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            if (_selectedCategory != null)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _selectedCategory!.color,
                  shape: BoxShape.circle,
                ),
              ),
            Icon(Icons.directions_bus,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('${filtered.length} hat', style: theme.textTheme.bodyMedium),
          ]),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off,
                          size: 48, color: theme.disabledColor),
                      const SizedBox(height: 16),
                      const Text('Hat bulunamadı'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final route = filtered[index];
                    final cardColor =
                        _isManisa ? route.color : _cyprusRouteColor(route);
                    return _RouteCard(
                      route: route,
                      cardColor: cardColor,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => RouteMapScreen(route: route)),
                      ),
                      onShowTimes: () => _showRouteTimes(route),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Favori Hatlar ────────────────────────────────────────────
  void _showFavoriteRoutes(BuildContext context, FavoritesProvider favorites) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.star_rounded, color: Colors.amber.shade600),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Favori Hatlarım',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: favorites.favoriteRoutes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star_outline,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('Henüz favori hat eklenmedi',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: favorites.favoriteRoutes.length,
                      itemBuilder: (context, index) {
                        final favRoute = favorites.favoriteRoutes[index];
                        final routesProvider = context.read<RoutesProvider>();
                        final TransitRoute? tr = routesProvider.allRoutes
                            .cast<TransitRoute?>()
                            .firstWhere((r) => r?.routeId == favRoute.routeId,
                                orElse: () => null);
                        if (tr == null) return const SizedBox.shrink();
                        final cardColor =
                            _isManisa ? tr.color : _cyprusRouteColor(tr);
                        return Dismissible(
                          key: Key(favRoute.routeId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12)),
                            child:
                                const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => favorites
                              .removeRouteFromFavorites(favRoute.routeId),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: cardColor, shape: BoxShape.circle),
                              ),
                              title: Text(tr.routeLongName,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(tr.typeName,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.schedule,
                                        color: theme.colorScheme.primary,
                                        size: 20),
                                    onPressed: () {
                                      Navigator.pop(sheetCtx);
                                      _showRouteTimes(tr);
                                    },
                                  ),
                                  const Icon(Icons.chevron_right, size: 20),
                                ],
                              ),
                              onTap: () => _navigateToMap(sheetCtx, tr),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Şehirlerarası Hat Kartı
// ============================================================
class _IntercityRouteCard extends StatelessWidget {
  final KktcBusLine line;
  final Color color;
  final bool isAirport; // true=KIBHAS (havalimanı), false=İtimat/Kombos
  final VoidCallback onShowTimes;
  final VoidCallback? onShowStops; // null ise durak butonu gösterilmez

  const _IntercityRouteCard({
    required this.line,
    required this.color,
    required this.isAirport,
    required this.onShowTimes,
    this.onShowStops,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = KktcBusService.instance.nextDepartures(line, max: 1);
    final nextDep = upcoming.isNotEmpty ? upcoming.first : null;
    final isActive = nextDep != null && nextDep.minutesFromNow < 480;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Üst bilgi satırı ──────────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sol renkli şerit
                  Container(width: 5, color: color),
                  // İkon
                  Container(
                    width: 52,
                    color: color.withOpacity(0.08),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                            isAirport
                                ? Icons.flight_takeoff
                                : Icons.directions_bus,
                            color: Colors.white,
                            size: 18),
                      ),
                    ),
                  ),
                  // Metin
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${line.fromCity} → ${line.toCity}',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            line.from,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(children: [
                            Icon(Icons.timer_outlined,
                                size: 12, color: Colors.grey.shade400),
                            const SizedBox(width: 3),
                            Text('~${line.durationMinutes} dk',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500)),
                            if (nextDep != null) ...[
                              const SizedBox(width: 10),
                              Icon(Icons.access_time,
                                  size: 12,
                                  color: isActive
                                      ? Colors.green.shade600
                                      : Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Text(
                                nextDep.time,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isActive
                                      ? Colors.green.shade700
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Butonlar ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(children: [
                // Saatleri Görüntüle
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onShowTimes,
                    icon: Icon(Icons.schedule, size: 15, color: color),
                    label: Text('Saatleri Görüntüle',
                        style: TextStyle(fontSize: 12, color: color)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: color.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                // Durakları Görüntüle — sadece KIBHAS için
                if (onShowStops != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onShowStops,
                      icon: Icon(Icons.location_on, size: 15, color: color),
                      label: Text(
                        'Durakları Görüntüle',
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: color.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Kategori Kartı
// ============================================================
class _CategoryCard extends StatelessWidget {
  final _RouteCategory category;
  final int routeCount;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.routeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [category.color, category.color.withOpacity(0.75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: category.color.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(category.emoji, style: const TextStyle(fontSize: 28)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        )),
                    Text(
                      category.isIntercity
                          ? '$routeCount hat'
                          : '$routeCount hat',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// GTFS Hat Kartı
// ============================================================
class _RouteCard extends StatelessWidget {
  final TransitRoute route;
  final Color cardColor;
  final VoidCallback onTap;
  final VoidCallback onShowTimes;

  const _RouteCard({
    required this.route,
    required this.cardColor,
    required this.onTap,
    required this.onShowTimes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: cardColor),
                Container(
                  width: 52,
                  color: cardColor.withOpacity(0.12),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: cardColor.withOpacity(0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(Icons.directions_bus,
                            color: _textColorFor(cardColor), size: 18),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cardColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            route.routeShortName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: cardColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          route.routeLongName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(route.typeName,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Consumer<FavoritesProvider>(
                      builder: (context, favorites, _) {
                        final isFav = favorites.isRouteFavorite(route.routeId);
                        return IconButton(
                          icon: Icon(
                              isFav
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color:
                                  isFav ? Colors.amber : Colors.grey.shade400,
                              size: 20),
                          onPressed: () {
                            favorites.toggleRouteFavorite(route);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(isFav
                                  ? '${route.routeShortName} favorilerden kaldırıldı'
                                  : '${route.routeShortName} favorilere eklendi'),
                              duration: const Duration(seconds: 2),
                              action: SnackBarAction(
                                  label: 'Geri Al',
                                  onPressed: () =>
                                      favorites.toggleRouteFavorite(route)),
                            ));
                          },
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.schedule,
                          color: theme.colorScheme.primary, size: 20),
                      onPressed: onShowTimes,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    IconButton(
                      icon: Icon(Icons.map_outlined,
                          color: theme.colorScheme.primary, size: 20),
                      onPressed: onTap,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
