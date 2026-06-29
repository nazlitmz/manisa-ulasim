import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/location_provider.dart';
import '../providers/stops_provider.dart';
import '../providers/routes_provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/favorites_provider.dart';
import '../config/routes.dart';
import '../config/popular_places_config.dart';
import '../services/city_detection_service.dart';
import '../services/tts_service.dart';
import '../services/speech_service.dart';
import '../widgets/favorites_section_widget.dart';
import '../screens/ai_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TtsService _ttsService = TtsService();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
      _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final locationProvider = context.read<LocationProvider>();
    final stopsProvider = context.read<StopsProvider>();
    final routesProvider = context.read<RoutesProvider>();
    final favoritesProvider = context.read<FavoritesProvider>();
    final accessibility = context.read<AccessibilityProvider>();

    await locationProvider.getCurrentLocation();

    // Şehir tespiti → UI yenile (Popüler Yerler güncellenir)
    final loc = locationProvider.effectiveLocation;
    await CityDetectionService.instance.detectCity(loc.latitude, loc.longitude);
    if (mounted) setState(() {});

    await stopsProvider.loadAllStops();
    await routesProvider.loadAllRoutes();
    await favoritesProvider.loadFavorites();

    if (accessibility.screenReaderEnabled) {
      String announcement =
          '${PopularPlacesConfig.cityName} uygulamasına hoş geldiniz. ';
      if (favoritesProvider.hasFavorites) {
        announcement +=
            '${favoritesProvider.totalFavoritesCount} favori kaydınız var. ';
      }
      announcement +=
          'Nereye gitmek istiyorsunuz kartına dokunarak hedef arayabilirsiniz.';
      await _ttsService.speak(announcement);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? [
                    const Color(0xFF1E1E1E),
                    const Color(0xFF121212),
                    const Color(0xFF121212),
                  ]
                : [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withOpacity(0.8),
                    theme.colorScheme.surface,
                    theme.colorScheme.surface,
                  ],
            stops: isDarkMode
                ? const [0.0, 0.2, 1.0]
                : const [0.0, 0.15, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: RefreshIndicator(
              onRefresh: _initializeData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAppBar(theme),
                    _buildMainSearchCard(theme),
                    _buildQuickActions(theme),

                    // ⭐ FAVORİLER BÖLÜMÜ (Popüler yerlerden önce)
                    const FavoritesSection(),

                    _buildPopularPlaces(theme),
                    _buildAccessibilitySection(theme),
                    const SizedBox(height: 100), // FAB'lar için ekstra boşluk
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _buildFABs(theme),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PopularPlacesConfig.cityName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Konum aktif',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          _AppBarButton(
            icon: Icons.settings,
            onTap: () {
              _announceNavigation('Ayarlar');
              Navigator.pushNamed(context, AppRoutes.settingsPage);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainSearchCard(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: GestureDetector(
        onTap: () {
          _announceNavigation('Hedef arama ekranı');
          Navigator.pushNamed(context, AppRoutes.destinationSearch);
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: isDarkMode
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.search, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nereye gitmek istiyorsunuz?',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Durak veya konum ara...',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  color: theme.colorScheme.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Küçük ekranlarda veya büyük yazıda dikey yerleşim
          if (constraints.maxWidth < 300) {
            return Column(
              children: [
                _QuickActionButton(
                  icon: Icons.near_me_rounded,
                  label: 'Yakındaki Duraklar',
                  color: Colors.green,
                  onTap: () {
                    _announceNavigation('Yakındaki duraklar');
                    Navigator.pushNamed(context, AppRoutes.nearbyStops);
                  },
                ),
                const SizedBox(height: 8),
                _QuickActionButton(
                  icon: Icons.notifications_active_rounded,
                  label: 'Şoföre Bildir',
                  color: Colors.orange,
                  onTap: () {
                    _announceNavigation('Şoföre bildir');
                    Navigator.pushNamed(context, AppRoutes.driverNotification);
                  },
                ),
                const SizedBox(height: 8),
                _QuickActionButton(
                  icon: Icons.directions_bus_rounded,
                  label: 'Tüm Hatlar',
                  color: Colors.blue,
                  onTap: () {
                    _announceNavigation('Tüm hatlar');
                    Navigator.pushNamed(context, AppRoutes.allRoutes);
                  },
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.near_me_rounded,
                  label: 'Yakındaki\nDuraklar',
                  color: Colors.green,
                  onTap: () {
                    _announceNavigation('Yakındaki duraklar');
                    Navigator.pushNamed(context, AppRoutes.nearbyStops);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.notifications_active_rounded,
                  label: 'Şoföre\nBildir',
                  color: Colors.orange,
                  onTap: () {
                    _announceNavigation('Şoföre bildir');
                    Navigator.pushNamed(context, AppRoutes.driverNotification);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.directions_bus_rounded,
                  label: 'Tüm\nHatlar',
                  color: Colors.blue,
                  onTap: () {
                    _announceNavigation('Tüm hatlar');
                    Navigator.pushNamed(context, AppRoutes.allRoutes);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPopularPlaces(ThemeData theme) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    final places = PopularPlacesConfig.featured;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Popüler Yerler',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  _announceNavigation('Tüm yerler');
                  Navigator.pushNamed(context, AppRoutes.destinationSearch);
                },
                child: const Text('Tümü'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isLargeText ? 1 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: isLargeText ? 3.5 : 1.6,
            ),
            itemCount: places.length,
            itemBuilder: (context, index) {
              final place = places[index];
              return _PopularPlaceCard(
                icon: place.icon,
                name: place.name,
                color: PopularPlacesConfig.placeColor(place),
                category: place.category,
                onTap: () {
                  _announcePopularPlace(place.name);
                  Navigator.pushNamed(
                    context,
                    AppRoutes.destinationSearch,
                    arguments: {
                      'name': place.name,
                      'lat': place.latitude,
                      'lon': place.longitude,
                    },
                  );
                },
                onFavorite: () {
                  final favorites = context.read<FavoritesProvider>();
                  favorites.togglePlaceFavorite(
                    id: place.id,
                    name: place.name,
                    category: place.category,
                    latitude: place.latitude,
                    longitude: place.longitude,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilitySection(ThemeData theme) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Hızlı Erişilebilirlik',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Consumer<AccessibilityProvider>(
            builder: (context, accessibility, _) {
              final isDarkMode = theme.brightness == Brightness.dark;

              return Container(
                padding: EdgeInsets.all(isLargeText ? 12 : 16),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isDarkMode
                          ? Colors.black.withOpacity(0.3)
                          : Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: isLargeText
                    ? Column(
                        children: [
                          _AccessibilityToggle(
                            icon: Icons.text_fields,
                            label: 'Büyük Yazı',
                            isActive: accessibility.largeText,
                            onTap: () {
                              final oldState = accessibility.largeText;
                              accessibility.toggleLargeText();
                              _announceToggle('Büyük yazı', !oldState);
                            },
                          ),
                          const SizedBox(height: 12),
                          _AccessibilityToggle(
                            icon: Icons.volume_up,
                            label: 'Sesli Okuma',
                            isActive: accessibility.screenReaderEnabled,
                            onTap: () {
                              final oldState =
                                  accessibility.screenReaderEnabled;
                              accessibility.toggleScreenReader();
                              _announceToggle('Sesli okuma', !oldState);
                            },
                          ),
                          const SizedBox(height: 12),
                          _AccessibilityToggle(
                            icon: Icons.dark_mode,
                            label: 'Karanlık Mod',
                            isActive: accessibility.darkMode,
                            onTap: () {
                              final oldState = accessibility.darkMode;
                              accessibility.toggleDarkMode();
                              _announceToggle('Karanlık mod', !oldState);
                            },
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Flexible(
                            child: _AccessibilityToggle(
                              icon: Icons.text_fields,
                              label: 'Büyük Yazı',
                              isActive: accessibility.largeText,
                              onTap: () {
                                final oldState = accessibility.largeText;
                                accessibility.toggleLargeText();
                                _announceToggle('Büyük yazı', !oldState);
                              },
                            ),
                          ),
                          Flexible(
                            child: _AccessibilityToggle(
                              icon: Icons.volume_up,
                              label: 'Sesli Okuma',
                              isActive: accessibility.screenReaderEnabled,
                              onTap: () {
                                final oldState =
                                    accessibility.screenReaderEnabled;
                                accessibility.toggleScreenReader();
                                _announceToggle('Sesli okuma', !oldState);
                              },
                            ),
                          ),
                          Flexible(
                            child: _AccessibilityToggle(
                              icon: Icons.dark_mode,
                              label: 'Karanlık Mod',
                              isActive: accessibility.darkMode,
                              onTap: () {
                                final oldState = accessibility.darkMode;
                                accessibility.toggleDarkMode();
                                _announceToggle('Karanlık mod', !oldState);
                              },
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ✨ İkili FAB: AI Asistan (mavi gradient) + Sesli Komut (turuncu)
  Widget _buildFABs(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 🤖 AI Asistan - MAVİ GRADIENT (Üstte)
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF1976D2)], // Mavi tonları
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2196F3).withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton(
            heroTag: 'fab_ai',
            onPressed: () {
              _announceNavigation('AI Asistan');
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AIChatScreen()),
              );
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            tooltip: 'AI Asistan',
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // 🎤 Sesli Komut - TURUNCU GRADIENT (Altta)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.secondary,
                theme.colorScheme.secondary.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.secondary.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FloatingActionButton(
            heroTag: 'fab_voice',
            onPressed: () => _showVoiceCommandDialog(),
            backgroundColor: Colors.transparent,
            elevation: 0,
            tooltip: 'Sesli Komut',
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }

  void _announceNavigation(String destination) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      _ttsService.speak('$destination açılıyor');
    }
  }

  void _announcePopularPlace(String placeName) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      _ttsService.speak('$placeName için rota hesaplanıyor');
    }
  }

  void _announceToggle(String feature, bool newState) {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled || feature == 'Sesli okuma') {
      _ttsService.speak('$feature ${newState ? "açıldı" : "kapatıldı"}');
    }
  }

  void _showVoiceCommandDialog() {
    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      _ttsService.speak('Sesli komut paneli açıldı');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _VoiceCommandSheet(),
    );
  }
}

class _AppBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AppBarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            vertical: isLargeText ? 12 : 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDarkMode
                  ? Colors.black.withOpacity(0.3)
                  : color.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isLargeText ? 40 : 48,
              height: isLargeText ? 40 : 48,
              decoration: BoxDecoration(
                color: color.withOpacity(isDarkMode ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: isLargeText ? 20 : 24),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isLargeText ? 10 : 11,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white70 : Colors.grey.shade700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularPlaceCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final Color color;
  final String category;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  const _PopularPlaceCard({
    required this.icon,
    required this.name,
    required this.color,
    required this.category,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isLargeText ? 8 : 12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDarkMode
                  ? Colors.black.withOpacity(0.3)
                  : color.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: isLargeText ? 28 : 36,
                  height: isLargeText ? 28 : 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(isDarkMode ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: isLargeText ? 16 : 20),
                ),
                Consumer<FavoritesProvider>(
                  builder: (context, favorites, _) {
                    final isFavorite = favorites.isPlaceFavorite(name);
                    return GestureDetector(
                      onTap: onFavorite,
                      child: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: isFavorite
                            ? Colors.amber
                            : (isDarkMode
                                ? Colors.grey.shade600
                                : Colors.grey.shade400),
                        size: isLargeText ? 18 : 22,
                      ),
                    );
                  },
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: isLargeText ? 11 : 13,
                  color: isDarkMode ? Colors.white : Colors.grey.shade800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessibilityToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _AccessibilityToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaleFactor = MediaQuery.textScaleFactorOf(context);
    final isLargeText = textScaleFactor > 1.3;

    if (isLargeText) {
      // Büyük yazı modunda yatay düzen
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primary.withOpacity(0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: isActive ? Colors.white : Colors.grey.shade600,
                    size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? theme.colorScheme.primary
                        : Colors.grey.shade600,
                  ),
                ),
              ),
              Icon(
                isActive ? Icons.check_circle : Icons.circle_outlined,
                color:
                    isActive ? theme.colorScheme.primary : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      );
    }

    // Normal mod - dikey düzen
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color:
                  isActive ? theme.colorScheme.primary : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : Colors.grey.shade600,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color:
                    isActive ? theme.colorScheme.primary : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceCommandSheet extends StatefulWidget {
  const _VoiceCommandSheet();

  @override
  State<_VoiceCommandSheet> createState() => _VoiceCommandSheetState();
}

class _VoiceCommandSheetState extends State<_VoiceCommandSheet>
    with SingleTickerProviderStateMixin {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();

  bool _isListening = false;
  String _recognizedText = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speechService.stopListening();
    super.dispose();
  }

  void _stopListening() {
    _speechService.stopListening();
    _pulseController.stop();
    setState(() => _isListening = false);
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
    });
    _pulseController.repeat(reverse: true);

    await _speechService.startListening(
      onResult: (text) {
        _pulseController.stop();
        setState(() {
          _recognizedText = text;
          _isListening = false;
        });
        _processCommand(text);
      },
      onPartialResult: (text) => setState(() => _recognizedText = text),
      onListeningStopped: () {
        _pulseController.stop();
        setState(() => _isListening = false);
      },
    );
  }

  void _processCommand(String command) {
    if (command.isEmpty) return;

    final normalized = command
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');

    Navigator.pop(context);

    // Şehire göre popüler yerlerde ara
    final places = PopularPlacesConfig.current;
    for (final place in places) {
      final normalizedName = place.name
          .toLowerCase()
          .replaceAll('ı', 'i')
          .replaceAll('ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('ş', 's')
          .replaceAll('ö', 'o')
          .replaceAll('ç', 'c');
      // İlk kelime eşleşmesi veya tam isim eşleşmesi
      final firstWord = normalizedName.split(' ').first;
      if (normalized.contains(firstWord) ||
          normalized.contains(normalizedName)) {
        _ttsService.speak('${place.name} için rota hesaplanıyor');
        Navigator.pushNamed(context, AppRoutes.destinationSearch, arguments: {
          'name': place.name,
          'lat': place.latitude,
          'lon': place.longitude,
        });
        return;
      }
    }

    // Genel komutlar
    if (normalized.contains('durak') || normalized.contains('yakin')) {
      _ttsService.speak('Yakındaki duraklar gösteriliyor');
      Navigator.pushNamed(context, AppRoutes.nearbyStops);
    } else if (normalized.contains('hat') &&
        (normalized.contains('tum') ||
            normalized.contains('butun') ||
            normalized.contains('liste'))) {
      _ttsService.speak('Tüm hatlar gösteriliyor');
      Navigator.pushNamed(context, AppRoutes.allRoutes);
    } else {
      // Bilinmeyen yerler için durak veritabanında ara
      _searchAndNavigate(command);
    }
  }

  Future<void> _searchAndNavigate(String searchText) async {
    final stopsProvider = context.read<StopsProvider>();
    final normalizedSearch = searchText
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');

    // Duraklarda ara
    final matchingStops = stopsProvider.allStops.where((stop) {
      final normalizedStopName = stop.stopName
          .toLowerCase()
          .replaceAll('ı', 'i')
          .replaceAll('ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('ş', 's')
          .replaceAll('ö', 'o')
          .replaceAll('ç', 'c');
      return normalizedStopName.contains(normalizedSearch);
    }).toList();

    if (matchingStops.isNotEmpty) {
      final bestMatch = matchingStops.first;
      _ttsService.speak('${bestMatch.stopName} için rota hesaplanıyor');
      Navigator.pushNamed(context, AppRoutes.destinationSearch, arguments: {
        'name': bestMatch.stopName,
        'lat': bestMatch.latitude,
        'lon': bestMatch.longitude,
      });
    } else {
      _ttsService.speak('$searchText için arama yapılıyor');
      Navigator.pushNamed(context, AppRoutes.destinationSearch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Şehire göre örnek chip'ler
    final featuredPlaces = PopularPlacesConfig.featured.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color:
                      isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Text(_isListening ? 'Dinleniyor...' : 'Sesli Komut',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _recognizedText.isEmpty
                ? 'Mikrofona dokunup konuşun'
                : '"$_recognizedText"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _recognizedText.isEmpty
                  ? Colors.grey
                  : theme.colorScheme.primary,
              fontStyle:
                  _recognizedText.isEmpty ? FontStyle.normal : FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => _isListening ? _stopListening() : _startListening(),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [Colors.red.shade400, Colors.red.shade600]
                            : [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary.withOpacity(0.8)
                              ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening
                                  ? Colors.red
                                  : theme.colorScheme.primary)
                              .withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(_isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white, size: 36),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('Örnek: "${featuredPlaces.first.name}", "Yakındaki duraklar"',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ...featuredPlaces.map((p) => _CommandChip(
                  label: p.name, onTap: () => _processCommand(p.name))),
              _CommandChip(
                  label: 'Yakın Duraklar',
                  onTap: () => _processCommand('yakındaki duraklar')),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CommandChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
              fontSize: 13),
        ),
      ),
    );
  }
}
