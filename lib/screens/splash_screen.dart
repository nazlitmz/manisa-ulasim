import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/routes.dart';
import '../providers/location_provider.dart';
import '../providers/stops_provider.dart';
import '../providers/routes_provider.dart';
import '../services/database_service.dart';

/// Açılış ekranı
/// Uygulama başlatılırken verileri yükler
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> 
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  String _loadingMessage = 'Uygulama başlatılıyor...';
  double _loadingProgress = 0.0;
  bool _hasError = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _animationController.forward();
    
    // Verileri yükle
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    try {
      // 1. Veritabanını başlat ve verileri yükle
      setState(() {
        _loadingMessage = 'Veriler yükleniyor...';
        _loadingProgress = 0.2;
      });
      
      final dbService = DatabaseService();
      await dbService.initialize();
      await dbService.loadGtfsData();
      
      // 2. Durak verilerini yükle
      setState(() {
        _loadingMessage = 'Duraklar hazırlanıyor...';
        _loadingProgress = 0.4;
      });
      
      if (mounted) {
        await context.read<StopsProvider>().loadAllStops();
      }
      
      // 3. Hat verilerini yükle
      setState(() {
        _loadingMessage = 'Hatlar hazırlanıyor...';
        _loadingProgress = 0.6;
      });
      
      if (mounted) {
        await context.read<RoutesProvider>().loadAllRoutes();
      }
      
      // 4. Konum servisini başlat
      setState(() {
        _loadingMessage = 'Konum alınıyor...';
        _loadingProgress = 0.8;
      });
      
      if (mounted) {
        await context.read<LocationProvider>().initialize();
      }
      
      // 5. Tamamlandı
      setState(() {
        _loadingMessage = 'Hazır!';
        _loadingProgress = 1.0;
      });
      
      // Ana sayfaya geç
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
      
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withOpacity(0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo / Icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.directions_bus_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Uygulama adı
                    Text(
                      'Manisa Ulaşım',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      semanticsLabel: 'Manisa Ulaşım Uygulaması',
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'Kentsel Toplu Taşıma Destek Sistemi',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Yükleme durumu
                    if (!_hasError) ...[
                      // Progress bar
                      SizedBox(
                        width: 200,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _loadingProgress,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Yükleme mesajı
                      Text(
                        _loadingMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ] else ...[
                      // Hata durumu
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Bir hata oluştu',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage ?? 'Bilinmeyen hata',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _hasError = false;
                                  _errorMessage = null;
                                  _loadingProgress = 0.0;
                                });
                                _initializeApp();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tekrar Dene'),
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
        ),
      ),
    );
  }
}
