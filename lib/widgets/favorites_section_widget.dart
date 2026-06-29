import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/favorites_provider.dart';
import '../providers/accessibility_provider.dart';
import '../models/route_model.dart';
import '../models/stop_model.dart';
import '../config/routes.dart';
import '../services/tts_service.dart';
import '../services/database_service.dart';
import '../screens/route_map_screen.dart';

/// Ana sayfada gösterilecek favoriler bölümü
class FavoritesSection extends StatelessWidget {
  const FavoritesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    return Consumer<FavoritesProvider>(
      builder: (context, favorites, _) {
        if (!favorites.hasFavorites) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            color: Colors.amber.shade600,
                            size: isLargeText ? 18 : 22),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Favorilerim',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${favorites.totalFavoritesCount}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showAllFavorites(context),
                    child: const Text('Tümü'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FavoritesTabs(favorites: favorites),
            ],
          ),
        );
      },
    );
  }

  void _showAllFavorites(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AllFavoritesSheet(),
    );
  }
}

/// FavoriteRoute → TransitRoute dönüşüm yardımcısı
TransitRoute _buildTransitRoute({
  required String routeId,
  required String routeShortName,
  required String routeLongName,
  String? routeColor,
}) {
  return TransitRoute(
    routeId: routeId,
    routeShortName: routeShortName,
    routeLongName: routeLongName,
    routeColor: routeColor,
    routeType: 3,
  );
}

// ===========================================================================
// Durak favorisine tıklanınca açılan "Bu Duraktan Geçen Hatlar" sheet'i
// ===========================================================================

void _showStopRoutesSheet(BuildContext context, Stop stop) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StopRoutesSheet(stop: stop),
  );
}

class _StopRoutesSheet extends StatefulWidget {
  final Stop stop;
  const _StopRoutesSheet({required this.stop});

  @override
  State<_StopRoutesSheet> createState() => _StopRoutesSheetState();
}

class _StopRoutesSheetState extends State<_StopRoutesSheet> {
  final DatabaseService _db = DatabaseService();
  List<TransitRoute> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final routes = await _db.getRoutesForStop(widget.stop.stopId);
    if (mounted) {
      setState(() {
        _routes = routes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final sheetColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: sheetColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on,
                        color: Colors.green, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.stop.stopName,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Bu duraktan geçen hatlar',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _routes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.directions_bus_outlined,
                                  size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'Bu duraktan geçen hat bulunamadı',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemCount: _routes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final route = _routes[index];
                            return _RouteListTile(
                              route: route,
                              cardColor: cardColor,
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RouteMapScreen(route: route),
                                  ),
                                );
                              },
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

class _RouteListTile extends StatelessWidget {
  final TransitRoute route;
  final Color cardColor;
  final VoidCallback onTap;

  const _RouteListTile({
    required this.route,
    required this.cardColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: route.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    route.routeShortName,
                    style: TextStyle(
                      color: route.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: route.routeShortName.length > 3 ? 12 : 16,
                    ),
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
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      route.typeName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Icon(Icons.map_outlined,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Sekmeli favori listesi
// ===========================================================================

class _FavoritesTabs extends StatefulWidget {
  final FavoritesProvider favorites;
  const _FavoritesTabs({required this.favorites});

  @override
  State<_FavoritesTabs> createState() => _FavoritesTabsState();
}

class _FavoritesTabsState extends State<_FavoritesTabs> {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _selectFirstNonEmptyTab();
  }

  void _selectFirstNonEmptyTab() {
    if (widget.favorites.favoriteStops.isNotEmpty) {
      _selectedTab = 0;
    } else if (widget.favorites.favoriteRoutes.isNotEmpty) {
      _selectedTab = 1;
    } else if (widget.favorites.favoritePlaces.isNotEmpty) {
      _selectedTab = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    return Column(
      children: [
        // ✅ Tab bar — dark modda koyu arka plan
        Container(
          height: isLargeText ? 48 : 40,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildTab(context, isDark, 0, 'Duraklar', Icons.location_on,
                  widget.favorites.favoriteStops.length, isLargeText),
              _buildTab(context, isDark, 1, 'Hatlar', Icons.directions_bus,
                  widget.favorites.favoriteRoutes.length, isLargeText),
              _buildTab(context, isDark, 2, 'Yerler', Icons.place,
                  widget.favorites.favoritePlaces.length, isLargeText),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildContent(theme, isDark, isLargeText),
        ),
      ],
    );
  }

  Widget _buildTab(BuildContext context, bool isDark, int index, String label,
      IconData icon, int count, bool isLargeText) {
    final isSelected = _selectedTab == index;
    final isEmpty = count == 0;

    return Expanded(
      child: GestureDetector(
        onTap: isEmpty ? null : () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            // ✅ Seçili tab — dark modda koyu kart rengi
            color: isSelected
                ? (isDark ? const Color(0xFF3C3C3C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1), blurRadius: 4)
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: isLargeText ? 14 : 16,
                color: isEmpty
                    ? Colors.grey.shade600
                    : isSelected
                        ? Theme.of(context).colorScheme.primary
                        : (isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600),
              ),
              const SizedBox(width: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  count > 0 ? '$count' : '-',
                  style: TextStyle(
                    fontSize: isLargeText ? 11 : 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isEmpty
                        ? Colors.grey.shade600
                        : isSelected
                            ? Theme.of(context).colorScheme.primary
                            : (isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark, bool isLargeText) {
    switch (_selectedTab) {
      case 0:
        return _buildStopsList(isDark, isLargeText);
      case 1:
        return _buildRoutesList(isDark, isLargeText);
      case 2:
        return _buildPlacesList(isDark, isLargeText);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStopsList(bool isDark, bool isLargeText) {
    final stops = widget.favorites.favoriteStops;
    if (stops.isEmpty) {
      return _buildEmptyState('Favori durak yok', Icons.location_on);
    }
    return SizedBox(
      height: isLargeText ? 100 : 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: stops.length.clamp(0, 5),
        itemBuilder: (context, index) {
          final stop = stops[index];
          return _FavoriteStopCard(
            stopId: stop.stopId,
            stopName: stop.stopName,
            latitude: stop.latitude,
            longitude: stop.longitude,
            isDark: isDark,
          );
        },
      ),
    );
  }

  Widget _buildRoutesList(bool isDark, bool isLargeText) {
    final routes = widget.favorites.favoriteRoutes;
    if (routes.isEmpty) {
      return _buildEmptyState('Favori hat yok', Icons.directions_bus);
    }
    return SizedBox(
      height: isLargeText ? 100 : 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: routes.length.clamp(0, 5),
        itemBuilder: (context, index) {
          final route = routes[index];
          return _FavoriteRouteCard(
            routeId: route.routeId,
            routeShortName: route.routeShortName,
            routeLongName: route.routeLongName,
            routeColor: route.routeColor,
            isDark: isDark,
          );
        },
      ),
    );
  }

  Widget _buildPlacesList(bool isDark, bool isLargeText) {
    final places = widget.favorites.favoritePlaces;
    if (places.isEmpty) {
      return _buildEmptyState('Favori yer yok', Icons.place);
    }
    return SizedBox(
      height: isLargeText ? 100 : 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: places.length.clamp(0, 5),
        itemBuilder: (context, index) {
          final place = places[index];
          return _FavoritePlaceCard(
            id: place.id,
            name: place.name,
            category: place.category,
            latitude: place.latitude,
            longitude: place.longitude,
            isDark: isDark,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Container(
      height: 90,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text(text,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Favori kartları — isDark parametresi ile dark mode desteği
// ===========================================================================

class _FavoriteStopCard extends StatelessWidget {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;
  final bool isDark;

  const _FavoriteStopCard({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    // ✅ Dark mode arka plan rengi
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final borderColor =
        isDark ? Colors.green.withOpacity(0.3) : Colors.green.shade100;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: isLargeText ? 150 : 130,
        margin: const EdgeInsets.only(right: 12),
        padding: EdgeInsets.all(isLargeText ? 10 : 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(isDark ? 0.05 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus,
                    size: isLargeText ? 14 : 16, color: Colors.green.shade400),
                const SizedBox(width: 4),
                Text(
                  'Hatları Gör',
                  style: TextStyle(
                      fontSize: isLargeText ? 9 : 10,
                      color: Colors.green.shade400),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                stopName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: isLargeText ? 11 : 12,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      TtsService().speak('$stopName durağından geçen hatlar gösteriliyor');
    }
    final stop = Stop(
      stopId: stopId,
      stopName: stopName,
      latitude: latitude,
      longitude: longitude,
    );
    _showStopRoutesSheet(context, stop);
  }
}

class _FavoriteRouteCard extends StatelessWidget {
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final String? routeColor;
  final bool isDark;

  const _FavoriteRouteCard({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    this.routeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    final color = routeColor != null
        ? Color(int.parse('FF${routeColor!}', radix: 16))
        : Theme.of(context).colorScheme.primary;

    // ✅ Dark mode arka plan rengi
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final borderColor =
        isDark ? color.withOpacity(0.2) : color.withOpacity(0.3);

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: isLargeText ? 150 : 130,
        margin: const EdgeInsets.only(right: 12),
        padding: EdgeInsets.all(isLargeText ? 10 : 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isDark ? 0.05 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isLargeText ? 6 : 8,
                  vertical: isLargeText ? 3 : 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  routeShortName,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isLargeText ? 10 : 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                routeLongName,
                style: TextStyle(
                  fontSize: isLargeText ? 10 : 11,
                  color: isDark ? Colors.grey.shade400 : Colors.grey,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      TtsService().speak('$routeShortName numaralı hat haritası açılıyor');
    }
    Navigator.pushNamed(
      context,
      AppRoutes.routeMap,
      arguments: _buildTransitRoute(
        routeId: routeId,
        routeShortName: routeShortName,
        routeLongName: routeLongName,
        routeColor: routeColor,
      ),
    );
  }
}

class _FavoritePlaceCard extends StatelessWidget {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final bool isDark;

  const _FavoritePlaceCard({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    // ✅ Dark mode arka plan rengi
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final borderColor =
        isDark ? Colors.red.withOpacity(0.3) : Colors.red.shade100;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: isLargeText ? 150 : 130,
        margin: const EdgeInsets.only(right: 12),
        padding: EdgeInsets.all(isLargeText ? 10 : 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(isDark ? 0.05 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place,
                    size: isLargeText ? 14 : 16, color: Colors.red.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    category,
                    style: TextStyle(
                        fontSize: isLargeText ? 9 : 10,
                        color: Colors.red.shade400),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: isLargeText ? 11 : 12,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      TtsService().speak('$name için rota hesaplanıyor');
    }
    Navigator.pushNamed(context, AppRoutes.destinationSearch, arguments: {
      'name': name,
      'lat': latitude,
      'lon': longitude,
    });
  }
}

// ===========================================================================
// Tüm favoriler bottom sheet
// ===========================================================================

class _AllFavoritesSheet extends StatefulWidget {
  const _AllFavoritesSheet();

  @override
  State<_AllFavoritesSheet> createState() => _AllFavoritesSheetState();
}

class _AllFavoritesSheetState extends State<_AllFavoritesSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // ✅ Sheet arka planı dark modda koyu
    final sheetColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: Colors.amber.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Tüm Favorilerim',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: theme.colorScheme.primary,
            tabs: [
              Consumer<FavoritesProvider>(
                builder: (_, fav, __) =>
                    Tab(text: 'Duraklar (${fav.favoriteStops.length})'),
              ),
              Consumer<FavoritesProvider>(
                builder: (_, fav, __) =>
                    Tab(text: 'Hatlar (${fav.favoriteRoutes.length})'),
              ),
              Consumer<FavoritesProvider>(
                builder: (_, fav, __) =>
                    Tab(text: 'Yerler (${fav.favoritePlaces.length})'),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStopsTab(isDark),
                _buildRoutesTab(isDark),
                _buildPlacesTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopsTab(bool isDark) {
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    return Consumer<FavoritesProvider>(
      builder: (context, favorites, _) {
        if (favorites.favoriteStops.isEmpty) {
          return _buildEmptyTab('Favori durak eklemediniz', Icons.location_on);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: favorites.favoriteStops.length,
          itemBuilder: (context, index) {
            final stop = favorites.favoriteStops[index];
            return _FavoriteListTile(
              title: stop.stopName,
              subtitle: 'Durak — hatları görmek için tıklayın',
              icon: Icons.location_on,
              color: Colors.green,
              cardBg: cardBg,
              onTap: () => _showStopRoutesSheet(
                context,
                Stop(
                  stopId: stop.stopId,
                  stopName: stop.stopName,
                  latitude: stop.latitude,
                  longitude: stop.longitude,
                ),
              ),
              onDelete: () => favorites.removeStopFromFavorites(stop.stopId),
            );
          },
        );
      },
    );
  }

  Widget _buildRoutesTab(bool isDark) {
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    return Consumer<FavoritesProvider>(
      builder: (context, favorites, _) {
        if (favorites.favoriteRoutes.isEmpty) {
          return _buildEmptyTab('Favori hat eklemediniz', Icons.directions_bus);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: favorites.favoriteRoutes.length,
          itemBuilder: (context, index) {
            final route = favorites.favoriteRoutes[index];
            return _FavoriteListTile(
              title: '${route.routeShortName} - ${route.routeLongName}',
              subtitle: 'Hat',
              icon: Icons.directions_bus,
              color: Colors.blue,
              cardBg: cardBg,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.routeMap,
                  arguments: _buildTransitRoute(
                    routeId: route.routeId,
                    routeShortName: route.routeShortName,
                    routeLongName: route.routeLongName,
                    routeColor: route.routeColor,
                  ),
                );
              },
              onDelete: () => favorites.removeRouteFromFavorites(route.routeId),
            );
          },
        );
      },
    );
  }

  Widget _buildPlacesTab(bool isDark) {
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    return Consumer<FavoritesProvider>(
      builder: (context, favorites, _) {
        if (favorites.favoritePlaces.isEmpty) {
          return _buildEmptyTab('Favori yer eklemediniz', Icons.place);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: favorites.favoritePlaces.length,
          itemBuilder: (context, index) {
            final place = favorites.favoritePlaces[index];
            return _FavoriteListTile(
              title: place.name,
              subtitle: place.category,
              icon: Icons.place,
              color: Colors.red,
              cardBg: cardBg,
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.destinationSearch,
                    arguments: {
                      'name': place.name,
                      'lat': place.latitude,
                      'lon': place.longitude,
                    });
              },
              onDelete: () => favorites.removePlaceFromFavorites(place.id),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyTab(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(text,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Favorilere eklemek için ⭐ simgesine dokunun',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FavoriteListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color cardBg;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _FavoriteListTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.cardBg,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(title),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: cardBg, // ✅ Dark mode kart rengi
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color),
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
