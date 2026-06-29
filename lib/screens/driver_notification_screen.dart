import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../models/stop_model.dart';
import '../models/route_model.dart';
import '../models/vehicle_location_model.dart';
import '../providers/location_provider.dart';
import '../providers/accessibility_provider.dart';
import '../services/tts_service.dart';
import '../services/database_service.dart';
import '../services/terminal_message_service.dart';
import '../services/vehicle_service.dart';
import '../services/notification_service.dart';

enum CardStep { methodSelect, nfcScanning, manualEntry, verified }

class DriverNotificationScreen extends StatefulWidget {
  const DriverNotificationScreen({super.key});

  @override
  State<DriverNotificationScreen> createState() =>
      _DriverNotificationScreenState();
}

class _DriverNotificationScreenState extends State<DriverNotificationScreen>
    with TickerProviderStateMixin {
  final TtsService _ttsService = TtsService();
  final DatabaseService _databaseService = DatabaseService();
  final TerminalMessageService _terminalService = TerminalMessageService();
  final VehicleService _vehicleService = VehicleService();
  final NotificationService _notificationService = NotificationService();

  // Engelli karti state
  CardStep _cardStep = CardStep.methodSelect;
  bool _nfcAvailable = false;
  bool _isNfcScanning = false;
  bool _isVerifyingCard = false;
  bool _cardVerified = false;
  String? _verifiedCardNumber;
  String? _verifiedCardType;
  int? _verifiedDiscountRate;
  String? _cardErrorMessage;
  final _cardController = TextEditingController();
  final _tcController = TextEditingController();
  final _cardFormKey = GlobalKey<FormState>();

  // Ana ekran state
  Stop? _selectedBoardingStop;
  Stop? _selectedAlightingStop;
  TransitRoute? _selectedRoute;
  List<Stop> _nearbyStops = [];
  List<Stop> _routeStops = [];
  List<TransitRoute> _availableRoutes = [];
  List<VehicleLocation> _availableVehicles = [];
  List<VehicleLocationWithDistance> _vehiclesWithDistance = [];
  VehicleLocation? _selectedVehicle;
  bool _isLoading = false;
  bool _isSending = false;
  bool _notificationSent = false;
  String? _errorMessage;
  String? _sentVehicleId;
  Map<String, dynamic>? _lastResponse;
  String? _sentTimestamp;
  bool _trackingActive = false;

  late AnimationController _successAnimController;
  late AnimationController _pulseAnimController;
  late AnimationController _cardSuccessController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _cardSuccessAnimation;

  @override
  void initState() {
    super.initState();

    _successAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _successAnimController,
      curve: Curves.elasticOut,
    );

    _pulseAnimController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseAnimController, curve: Curves.easeInOut),
    );

    _cardSuccessController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _cardSuccessAnimation = CurvedAnimation(
      parent: _cardSuccessController,
      curve: Curves.elasticOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkNfc();
      _notificationService.initialize();
      _notificationService.checkPermission();
      final accessibility = context.read<AccessibilityProvider>();
      if (accessibility.screenReaderEnabled) {
        await _ttsService
            .speak('Şoföre bildir ekranı. Önce engelli kartınızı doğrulayın.');
      }
    });
  }

  Future<void> _checkNfc() async {
    try {
      final available = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _nfcAvailable = false);
    }
  }

  @override
  void dispose() {
    _trackingActive = false;
    _isNfcScanning = false;
    try {
      NfcManager.instance.stopSession();
    } catch (_) {}
    _successAnimController.dispose();
    _pulseAnimController.dispose();
    _cardSuccessController.dispose();
    _cardController.dispose();
    _tcController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════
  // NFC
  // ════════════════════════════════════════

  Future<void> _startNfcScan() async {
    if (!_nfcAvailable) return;
    setState(() {
      _cardStep = CardStep.nfcScanning;
      _isNfcScanning = true;
      _cardErrorMessage = null;
    });

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      await _ttsService.speak(
          'NFC tarama başladı. Kartınızı telefonun arkasına yaklaştırın.');
    }

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          await NfcManager.instance.stopSession();
          if (!mounted) return;
          setState(() => _isNfcScanning = false);
          await _processNfcTag(tag);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isNfcScanning = false;
        _cardErrorMessage = 'NFC başlatılamadı: $e';
        _cardStep = CardStep.methodSelect;
      });
    }
  }

  Future<void> _stopNfcScan() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isNfcScanning = false;
      _cardStep = CardStep.methodSelect;
    });
  }

  Future<void> _processNfcTag(NfcTag tag) async {
    setState(() => _isVerifyingCard = true);

    try {
      String? cardId;

      // NDEF kayitlarindan oku (nfc_manager_ndef paketi)
      final ndef = Ndef.from(tag);
      if (ndef != null) {
        final msg = ndef.cachedMessage;
        if (msg != null) {
          for (final record in msg.records) {
            final payload = String.fromCharCodes(record.payload);
            final cleaned =
                payload.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
            if (cleaned.length >= 6) {
              cardId = cleaned.toUpperCase();
              break;
            }
          }
        }
      }

      // NDEF yoksa tag.data map'inden identifier al
      if (cardId == null) {
        final tagData = tag.data as Map<String, dynamic>;
        tagData.forEach((key, value) {
          if (cardId != null) return;
          if (value is Map) {
            final id = value['identifier'];
            if (id is List && id.isNotEmpty) {
              cardId = id
                  .map((b) => (b as int).toRadixString(16).padLeft(2, '0'))
                  .join()
                  .toUpperCase();
            }
          }
        });
      }

      if (cardId != null && cardId!.length >= 6) {
        await _verifyCardNumber(cardId!);
      } else {
        if (!mounted) return;
        setState(() {
          _isVerifyingCard = false;
          _cardErrorMessage = 'Kart verisi okunamadi. Lütfen tekrar deneyin.';
          _cardStep = CardStep.methodSelect;
        });
      }
    } catch (e) {
      debugPrint('NFC isleme hatasi: $e');
      if (!mounted) return;
      setState(() {
        _isVerifyingCard = false;
        _cardErrorMessage = 'Kart okunamadi. Tekrar deneyin.';
        _cardStep = CardStep.methodSelect;
      });
    }
  }

  // ════════════════════════════════════════
  // KART DOGRULAMA
  // ════════════════════════════════════════

  Future<void> _submitManualCard() async {
    if (!_cardFormKey.currentState!.validate()) return;
    final cardNumber = _cardController.text.trim().toUpperCase();
    await _verifyCardNumber(cardNumber);
  }

  Future<void> _verifyCardNumber(String cardNumber) async {
    setState(() {
      _isVerifyingCard = true;
      _cardErrorMessage = null;
    });

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      await _ttsService.speak('Kart dogrulanıyor, lütfen bekleyin.');
    }

    try {
      await Future.delayed(const Duration(seconds: 2));

      final bool isValid = cardNumber.length >= 6;

      if (!mounted) return;

      if (isValid) {
        final cardType = cardNumber.startsWith('A')
            ? 'Agir Engelli'
            : cardNumber.startsWith('B')
                ? 'Orta Engelli'
                : 'Engelli';
        final discountRate = cardNumber.startsWith('A') ? 100 : 50;

        setState(() {
          _isVerifyingCard = false;
          _cardVerified = true;
          _verifiedCardNumber = cardNumber;
          _verifiedCardType = cardType;
          _verifiedDiscountRate = discountRate;
          _cardStep = CardStep.verified;
          _cardErrorMessage = null;
        });

        _cardSuccessController.forward();
        _loadNearbyStops();

        if (accessibility.screenReaderEnabled) {
          await _ttsService.speak('Engelli karti dogrulandi! $cardType. '
              'Yüzde $discountRate indirim aktif. '
              'Simdi binis duraganizi secebilirsiniz.');
        }
      } else {
        setState(() {
          _isVerifyingCard = false;
          _cardErrorMessage =
              'Kart dogrulanamadi. Lütfen bilgileri kontrol edin.';
        });

        if (accessibility.screenReaderEnabled) {
          await _ttsService
              .speak('Kart dogrulanamadi. Bilgileri kontrol edin.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifyingCard = false;
        _cardErrorMessage = 'Bir hata olustu. Lütfen tekrar deneyin.';
      });
    }
  }

  void _resetCard() {
    try {
      NfcManager.instance.stopSession();
    } catch (_) {}
    _cardController.clear();
    _tcController.clear();
    _cardSuccessController.reset();
    _successAnimController.reset();
    setState(() {
      _cardStep = CardStep.methodSelect;
      _cardVerified = false;
      _verifiedCardNumber = null;
      _verifiedCardType = null;
      _verifiedDiscountRate = null;
      _cardErrorMessage = null;
      _isNfcScanning = false;
      _isVerifyingCard = false;
      _nearbyStops = [];
      _selectedBoardingStop = null;
      _selectedRoute = null;
      _selectedAlightingStop = null;
      _availableRoutes = [];
      _routeStops = [];
      _availableVehicles = [];
      _vehiclesWithDistance = [];
      _selectedVehicle = null;
      _notificationSent = false;
      _isLoading = false;
    });
  }

  // ════════════════════════════════════════
  // ANA EKRAN FONKSIYONLARI
  // ════════════════════════════════════════

  DateTime _getTurkeyTime() {
    return DateTime.now().toUtc().add(const Duration(hours: 3));
  }

  Future<void> _loadNearbyStops() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final locationProvider = context.read<LocationProvider>();
      final location = locationProvider.effectiveLocation;

      final allStops = await _databaseService.getAllStops();
      final stopsWithRoutes = <Stop>[];

      for (final stop in allStops) {
        final routes = await _databaseService.getRoutesForStop(stop.stopId);
        if (routes.isNotEmpty) {
          final distance = _calculateDistance(
            location.latitude,
            location.longitude,
            stop.latitude,
            stop.longitude,
          );
          stopsWithRoutes.add(stop.copyWith(distanceFromUser: distance));
        }
      }

      stopsWithRoutes.sort((a, b) => (a.distanceFromUser ?? double.infinity)
          .compareTo(b.distanceFromUser ?? double.infinity));

      if (!mounted) return;
      setState(() {
        _nearbyStops = stopsWithRoutes.take(15).toList();
        _isLoading = false;
        if (_nearbyStops.isEmpty) {
          _errorMessage = 'Yakinda hat gecen durak bulunamadi.';
        }
      });

      final accessibility = context.read<AccessibilityProvider>();
      if (accessibility.screenReaderEnabled && _nearbyStops.isNotEmpty) {
        await _ttsService.speak('${_nearbyStops.length} yakin durak bulundu. '
            'Adim 1: Bineceginizduragi secin.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Duraklar yüklenirken hata olustu.';
      });
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  Future<void> _onBoardingStopSelected(Stop stop) async {
    setState(() {
      _selectedBoardingStop = stop;
      _selectedRoute = null;
      _selectedAlightingStop = null;
      _selectedVehicle = null;
      _availableRoutes = [];
      _routeStops = [];
      _availableVehicles = [];
      _vehiclesWithDistance = [];
    });

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      final distance = stop.distanceFromUser ?? 0;
      final distanceText = distance < 1000
          ? '${distance.toInt()} metre'
          : '${(distance / 1000).toStringAsFixed(1)} kilometre';
      await _ttsService
          .speak('${stop.stopName} duragi secildi. $distanceText uzaklikta. '
              'Simdi adim 2: Hat secin.');
    }

    final routes = await _databaseService.getRoutesForStop(stop.stopId);
    if (!mounted) return;
    setState(() => _availableRoutes = routes);

    if (accessibility.screenReaderEnabled && routes.isNotEmpty) {
      final hatlar = routes.take(3).map((r) => r.routeShortName).join(', ');
      await _ttsService
          .speak('${routes.length} hat mevcut. Ilk hatlar: $hatlar');
    }
  }

  Future<void> _onRouteSelected(TransitRoute route) async {
    setState(() {
      _selectedRoute = route;
      _selectedAlightingStop = null;
      _selectedVehicle = null;
      _availableVehicles = [];
      _vehiclesWithDistance = [];
      _routeStops = [];
    });

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      _ttsService.speak(
          '${route.routeShortName} numarali hat secildi. ${route.routeLongName}. '
          'Ineceginizduragi yükleniyor.');
    }

    try {
      final stopsDir0 = await _databaseService
          .getStopsForRouteDirection(route.routeId, direction: 1);
      final stopsDir1 = await _databaseService
          .getStopsForRouteDirection(route.routeId, direction: 2);

      List<Stop> stopsViaBoardingStop = [];
      final boardingId = _selectedBoardingStop?.stopId;
      final boardingName = _selectedBoardingStop?.stopName ?? '';
      final boardingIdStr = boardingId?.toString() ?? '';

      final foundInDir0 =
          stopsDir0.any((s) => s.stopId.toString() == boardingIdStr);
      final foundInDir1 =
          stopsDir1.any((s) => s.stopId.toString() == boardingIdStr);
      final foundInDir0ByName = !foundInDir0 &&
          stopsDir0.any((s) =>
              s.stopName.trim().toLowerCase() ==
              boardingName.trim().toLowerCase());
      final foundInDir1ByName = !foundInDir1 &&
          stopsDir1.any((s) =>
              s.stopName.trim().toLowerCase() ==
              boardingName.trim().toLowerCase());

      List<Stop> correctStops;
      if (foundInDir1 || foundInDir1ByName) {
        correctStops = stopsDir1;
        debugPrint('✅ direction 2 (donus) secildi (${stopsDir1.length} durak)');
      } else if (foundInDir0 || foundInDir0ByName) {
        correctStops = stopsDir0;
        debugPrint('✅ direction 1 (gidis) secildi (${stopsDir0.length} durak)');
      } else {
        if (boardingIdStr.isNotEmpty) {
          stopsViaBoardingStop = await _databaseService
              .getStopsForRouteThroughStop(route.routeId, boardingIdStr);
        }
        if (stopsViaBoardingStop.isNotEmpty) {
          correctStops = stopsViaBoardingStop;
        } else {
          correctStops =
              stopsDir1.length >= stopsDir0.length ? stopsDir1 : stopsDir0;
        }
      }

      correctStops
          .sort((a, b) => (a.stopSequence ?? 0).compareTo(b.stopSequence ?? 0));

      if (!mounted) return;
      setState(() => _routeStops = correctStops);

      if (accessibility.screenReaderEnabled) {
        await _ttsService.speak(
            '${correctStops.length} durak bulundu. Ineceginizduragi secin.');
      }
    } catch (e) {
      debugPrint('Duraklar yüklenirken hata: $e');
    }
  }

  Future<void> _onAlightingStopSelected(Stop stop) async {
    setState(() {
      _selectedAlightingStop = stop;
      _selectedVehicle = null;
      _availableVehicles = [];
      _vehiclesWithDistance = [];
    });

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      _ttsService
          .speak('${stop.stopName} inis duragi secildi. Araclar yükleniyor.');
    }

    try {
      final vehicles =
          await _vehicleService.getVehiclesForRoute(_selectedRoute!.routeId);
      final vehiclesWithDist = _calculateVehicleDistances(vehicles)
        ..sort((a, b) => a.distanceToStop.compareTo(b.distanceToStop));

      if (!mounted) return;
      setState(() {
        _availableVehicles = vehicles;
        _vehiclesWithDistance = vehiclesWithDist;
        _selectedVehicle =
            vehiclesWithDist.isNotEmpty ? vehiclesWithDist.first.vehicle : null;
      });

      if (accessibility.screenReaderEnabled) {
        if (vehicles.isEmpty) {
          await _ttsService.speak(
              'Bu hatta su anda aktif arac yok. Tüm araclara bildirim gönderilecek.');
        } else {
          final closest = vehiclesWithDist.first;
          final distanceText = closest.distanceToStop < 1000
              ? '${closest.distanceToStop.toInt()} metre'
              : '${(closest.distanceToStop / 1000).toStringAsFixed(1)} kilometre';
          await _ttsService.speak('${vehicles.length} aktif arac bulundu. '
              'En yakin arac: ${closest.vehicle.name}, $distanceText uzaklikta.');
        }
      }
    } catch (e) {
      debugPrint('Araclar yüklenirken hata: $e');
      if (!mounted) return;
      setState(() {
        _availableVehicles = [];
        _vehiclesWithDistance = [];
        _selectedVehicle = null;
      });
    }
  }

  List<VehicleLocationWithDistance> _calculateVehicleDistances(
      List<VehicleLocation> vehicles) {
    if (_selectedBoardingStop == null) return [];
    return vehicles.map((vehicle) {
      final distance = _calculateDistance(
        vehicle.gps.latitude,
        vehicle.gps.longitude,
        _selectedBoardingStop!.latitude,
        _selectedBoardingStop!.longitude,
      );
      debugPrint(
          '🚌 ${vehicle.name}: ${distance.toStringAsFixed(0)}m uzaklikta duraga');
      return VehicleLocationWithDistance(
          vehicle: vehicle, distanceToStop: distance);
    }).toList();
  }

  void _onVehicleSelected(VehicleLocation? vehicle) {
    setState(() => _selectedVehicle = vehicle);
    final accessibility = context.read<AccessibilityProvider>();
    if (!accessibility.screenReaderEnabled) return;
    if (vehicle == null) {
      _ttsService.speak('Tüm araclara bildirim gönderilecek.');
    } else {
      final vehicleWithDist = _vehiclesWithDistance.firstWhere(
        (v) => v.vehicle.id == vehicle.id,
        orElse: () =>
            VehicleLocationWithDistance(vehicle: vehicle, distanceToStop: 0),
      );
      final distanceText = vehicleWithDist.distanceToStop < 1000
          ? '${vehicleWithDist.distanceToStop.toInt()} metre'
          : '${(vehicleWithDist.distanceToStop / 1000).toStringAsFixed(1)} kilometre';
      _ttsService
          .speak('${vehicle.name} secildi. Duraga $distanceText uzaklikta.');
    }
  }

  Future<void> _sendNotification() async {
    if (_selectedBoardingStop == null || _selectedRoute == null) return;

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      await _ttsService.speak('Bildirim gönderiliyor, lütfen bekleyin.');
    }

    setState(() => _isSending = true);

    try {
      bool success = false;
      Map<String, dynamic>? response;

      final turkeyTime = _getTurkeyTime();
      final timestamp = turkeyTime.toIso8601String();
      debugPrint('⏰ Yerel Zaman (Türkiye): $timestamp');

      final msgBody =
          'Engelli yolcu ${_selectedBoardingStop!.stopName} duraginda '
          '${_selectedRoute!.routeShortName} numarali hatta binmek istiyor.'
          '${_selectedAlightingStop != null ? ' Inecek durak: ${_selectedAlightingStop!.stopName}' : ''}'
          ' [ENGELLI YOLCU - $_verifiedCardType - %$_verifiedDiscountRate Indirim]';

      final msgData = {
        'boarding_stop_name': _selectedBoardingStop!.stopName,
        'boarding_stop_id': _selectedBoardingStop!.stopId,
        if (_selectedAlightingStop != null) ...{
          'alighting_stop_name': _selectedAlightingStop!.stopName,
          'alighting_stop_id': _selectedAlightingStop!.stopId,
        },
        'route_number': _selectedRoute!.routeShortName,
        'notification_type': 'disabled_passenger_boarding',
        'timestamp': timestamp,
        'is_disabled_passenger': true,
        'disability_card_number': _verifiedCardNumber,
        'disability_card_type': _verifiedCardType,
        'disability_discount_rate': _verifiedDiscountRate,
      };

      if (_selectedVehicle != null) {
        response = await _terminalService.sendTerminalMessage(
          terminalName: _selectedVehicle!.name,
          msgType: '01',
          msgHeader: 'Engelli Yolcu Binis Bildirimi',
          msgBody: msgBody,
          msgData: msgData,
        );
        success = response != null;
        _sentVehicleId = _selectedVehicle!.name;
      } else if (_availableVehicles.isNotEmpty) {
        success = true;
        _sentVehicleId = 'Tüm araclar (${_availableVehicles.length})';
        for (final vehicle in _availableVehicles) {
          response = await _terminalService.sendTerminalMessage(
            terminalName: vehicle.name,
            msgType: '01',
            msgHeader: 'Engelli Yolcu Binis Bildirimi',
            msgBody: msgBody,
            msgData: msgData,
          );
          if (response == null) {
            success = false;
            break;
          }
        }
      } else {
        await Future.delayed(const Duration(seconds: 1));
        success = true;
        _sentVehicleId = 'Demo Mod';
      }

      if (!mounted) return;
      setState(() {
        _isSending = false;
        _notificationSent = success;
        _lastResponse = response;
        _sentTimestamp = timestamp;
        if (!success) {
          _errorMessage = 'Bildirim gönderilemedi. Lütfen tekrar deneyin.';
        }
      });

      if (success) {
        _successAnimController.forward();
        await _notificationService.showNotification(
          title: '✅ Soföre Bildirildi!',
          body:
              '${_selectedRoute!.routeShortName} hatti icin engelli yolcu bildirimi gönderildi.',
        );
        _startVehicleTracking();

        if (accessibility.screenReaderEnabled) {
          String announcement =
              'Bildiriminiz basariyla gönderildi! Engelli yolcu oldugunuz soföre bildirildi. '
              '${_selectedRoute!.routeShortName} numarali hattin soförü, '
              '${_selectedBoardingStop!.stopName} duraginda bineceginiziblilecek.';
          if (_selectedAlightingStop != null) {
            announcement +=
                ' ${_selectedAlightingStop!.stopName} duraginda ineceginiziblilecek.';
          }
          announcement +=
              ' Arac duraga yakastiginda size bildirim göndereceğiz.';
          await _ttsService.speak(announcement);
        }
      } else {
        if (accessibility.screenReaderEnabled) {
          await _ttsService
              .speak('Bildirim gönderilemedi. Lütfen tekrar deneyin.');
        }
      }
    } catch (e) {
      debugPrint('Bildirim gönderme hatasi: $e');
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = 'Bir hata olustu: $e';
      });
    }
  }

  void _startVehicleTracking() {
    if (_selectedBoardingStop == null || _selectedRoute == null) return;
    _trackingActive = true;

    final String? trackedVehicleId = _selectedVehicle?.id;
    final boardingStop = _selectedBoardingStop!;
    final route = _selectedRoute!;
    final alightingStop = _selectedAlightingStop;

    bool approachingNotificationSent = false;
    bool arrivedNotificationSent = false;
    bool oneStopAwayNotificationSent = false;
    bool alightingNotificationSent = false;
    List<Stop> routeStops = [];

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted || !_trackingActive) return false;
      if (alightingStop == null && arrivedNotificationSent) return false;
      if (alightingStop != null && alightingNotificationSent) return false;

      try {
        final vehicles =
            await _vehicleService.getVehiclesForRoute(route.routeId);
        if (vehicles.isEmpty) return true;

        final vehiclesToCheck = trackedVehicleId != null
            ? vehicles.where((v) => v.id == trackedVehicleId).toList()
            : vehicles;
        if (vehiclesToCheck.isEmpty) return true;

        VehicleLocation? closestVehicle;
        double closestToBoardingDistance = double.infinity;
        for (final vehicle in vehiclesToCheck) {
          final distance = _calculateDistance(
              vehicle.gps.latitude,
              vehicle.gps.longitude,
              boardingStop.latitude,
              boardingStop.longitude);
          if (distance < closestToBoardingDistance) {
            closestToBoardingDistance = distance;
            closestVehicle = vehicle;
          }
        }
        if (closestVehicle == null) return true;

        if (!approachingNotificationSent && closestToBoardingDistance <= 300) {
          approachingNotificationSent = true;
          await _notificationService.showNotification(
            title: '🚌 Otobüsünüz Yaklasıyor! Hazırlanın!',
            body:
                '${route.routeShortName} hatti ${boardingStop.stopName} duragina yaklasıyor. (${closestToBoardingDistance.toInt()}m)',
          );
          if (mounted) {
            final acc = context.read<AccessibilityProvider>();
            if (acc.screenReaderEnabled) {
              await _ttsService.speak(
                  '${route.routeShortName} numarali hat geliyor! Hazırlanın!');
            }
          }
        }

        if (approachingNotificationSent &&
            !arrivedNotificationSent &&
            closestToBoardingDistance <= 50) {
          arrivedNotificationSent = true;
          await _notificationService.showNotification(
            title: '🚌 Otobüsünüz Geldi! Binin!',
            body:
                '${route.routeShortName} hatti ${boardingStop.stopName} duraginda.',
          );
          if (mounted) {
            final acc = context.read<AccessibilityProvider>();
            if (acc.screenReaderEnabled) {
              await _ttsService.speak(
                  '${route.routeShortName} numarali otobüs duraga geldi! Simdi binin!');
            }
          }
          if (alightingStop == null) return false;
        }

        if (arrivedNotificationSent &&
            alightingStop != null &&
            (!oneStopAwayNotificationSent || !alightingNotificationSent)) {
          if (routeStops.isEmpty) {
            try {
              List<Stop> stops = await _databaseService
                  .getStopsForRouteDirection(route.routeId, direction: 1);
              if (stops.isEmpty) {
                stops = await _databaseService
                    .getStopsForRouteDirection(route.routeId, direction: 2);
              }
              routeStops = stops;
            } catch (_) {
              return true;
            }
          }

          if (routeStops.isNotEmpty) {
            final alightingIndex =
                routeStops.indexWhere((s) => s.stopId == alightingStop.stopId);
            if (alightingIndex > 0) {
              final oneBeforeStop = routeStops[alightingIndex - 1];
              final closestToAlightingDist = _calculateDistance(
                  closestVehicle.gps.latitude,
                  closestVehicle.gps.longitude,
                  alightingStop.latitude,
                  alightingStop.longitude);
              final closestToOneBeforeDist = _calculateDistance(
                  closestVehicle.gps.latitude,
                  closestVehicle.gps.longitude,
                  oneBeforeStop.latitude,
                  oneBeforeStop.longitude);

              if (!oneStopAwayNotificationSent &&
                  closestToOneBeforeDist <= 80) {
                oneStopAwayNotificationSent = true;
                await _notificationService.showNotification(
                  title: '🔔 Bir Sonraki Durak: ${alightingStop.stopName}',
                  body: 'Ineceginizduraga 1 durak kaldi. Hazırlanın!',
                );
                if (mounted) {
                  final acc = context.read<AccessibilityProvider>();
                  if (acc.screenReaderEnabled) {
                    await _ttsService.speak(
                        'Dikkat! Bir sonraki durak ineceginizduraga: ${alightingStop.stopName}. Hazırlanın!');
                  }
                }
              }

              if (oneStopAwayNotificationSent &&
                  !alightingNotificationSent &&
                  closestToAlightingDist <= 80) {
                alightingNotificationSent = true;
                await _notificationService.showNotification(
                  title: '🚨 Ineceginizduraga Siniz!',
                  body:
                      '${alightingStop.stopName} duragındasınız. Lütfen simdi inin!',
                );
                if (mounted) {
                  final acc = context.read<AccessibilityProvider>();
                  if (acc.screenReaderEnabled) {
                    await _ttsService.speak(
                        'Ineceginizduraga: ${alightingStop.stopName}. Lütfen simdi inin!');
                  }
                }
                return false;
              }
            }
          }
        }
        return true;
      } catch (e) {
        debugPrint('❌ Arac takibi hatasi: $e');
        return true;
      }
    });
  }

  void _resetNotification() {
    _trackingActive = false;
    _successAnimController.reset();
    setState(() {
      _notificationSent = false;
      _selectedBoardingStop = null;
      _selectedAlightingStop = null;
      _selectedRoute = null;
      _selectedVehicle = null;
      _availableRoutes = [];
      _routeStops = [];
      _availableVehicles = [];
      _vehiclesWithDistance = [];
      _sentVehicleId = null;
      _lastResponse = null;
      _sentTimestamp = null;
    });
    _loadNearbyStops();
  }

  // ════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soföre Bildir'),
        actions: [
          if (_cardVerified)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar:
                      const Icon(Icons.verified, color: Colors.white, size: 16),
                  label: Text(
                    _verifiedCardType ?? 'Engelli',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  backgroundColor: Colors.purple,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: !_cardVerified
            ? _buildCardVerificationView(theme)
            : _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null && !_notificationSent
                    ? _buildErrorView(theme)
                    : _notificationSent
                        ? _buildSuccessView(theme)
                        : _isSending
                            ? _buildSendingView(theme)
                            : _buildFormView(theme),
      ),
    );
  }

  Widget _buildCardVerificationView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF283593)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.accessibility_new,
                    color: Colors.white, size: 52),
                const SizedBox(height: 14),
                const Text(
                  'Engelli Kartı Dogrulama',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Bu ekranı kullanmak icin engelli kartınızı dogrulamanız gerekmektedir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (_cardErrorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_cardErrorMessage!,
                        style: TextStyle(color: Colors.red.shade700))),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (_isVerifyingCard) ...[
            const SizedBox(height: 40),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Kart dogrulanıyor...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
            const SizedBox(height: 40),
          ] else if (_cardStep == CardStep.methodSelect) ...[
            _buildMethodSelectStep(theme),
          ] else if (_cardStep == CardStep.nfcScanning) ...[
            _buildNfcScanStep(theme),
          ] else if (_cardStep == CardStep.manualEntry) ...[
            _buildManualEntryStep(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildMethodSelectStep(ThemeData theme) {
    return Column(
      children: [
        Text(
          'Dogrulama yöntemini secin',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        if (_nfcAvailable) ...[
          _buildMethodButton(
            icon: Icons.nfc,
            title: 'NFC ile Okut',
            subtitle: 'Kartınızı telefonun arkasına yaklaştırın',
            color: const Color(0xFF1A237E),
            onTap: _startNfcScan,
          ),
          const SizedBox(height: 14),
        ],
        _buildMethodButton(
          icon: Icons.keyboard_alt_outlined,
          title: 'Kart Numarası ile Gir',
          subtitle: 'Kartınızdaki numarayı manuel olarak girin',
          color: Colors.teal.shade700,
          onTap: () => setState(() {
            _cardStep = CardStep.manualEntry;
            _cardErrorMessage = null;
          }),
        ),
        if (!_nfcAvailable) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Bu cihazda NFC desteklenmiyor.',
                      style: TextStyle(
                          color: Colors.orange.shade700, fontSize: 12))),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _buildMethodButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          )),
          Icon(Icons.arrow_forward_ios,
              color: color.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }

  Widget _buildNfcScanStep(ThemeData theme) {
    return Column(children: [
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _isNfcScanning ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A237E).withOpacity(0.07),
              border: Border.all(
                color: _isNfcScanning
                    ? const Color(0xFF1A237E)
                    : Colors.grey.shade300,
                width: 2.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.nfc,
                  size: 80,
                  color: _isNfcScanning ? const Color(0xFF1A237E) : Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  _isNfcScanning ? 'Taranıyor...' : 'Hazır',
                  style: TextStyle(
                    color:
                        _isNfcScanning ? const Color(0xFF1A237E) : Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        _isNfcScanning
            ? 'Engelli kartınızı telefonun\narka kısmına yaklaştırın'
            : 'NFC taraması başlatılıyor...',
        textAlign: TextAlign.center,
        style:
            theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 32),
      if (_isNfcScanning)
        ElevatedButton.icon(
          onPressed: _stopNfcScan,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Taramayı Iptal Et'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () {
          _stopNfcScan();
          setState(() => _cardStep = CardStep.methodSelect);
        },
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Geri Dön'),
      ),
    ]);
  }

  Widget _buildManualEntryStep(ThemeData theme) {
    return Form(
      key: _cardFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kart Bilgilerini Girin',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _cardController,
            decoration: InputDecoration(
              labelText: 'Engelli Kart Numarası *',
              hintText: 'Örn: EK123456789',
              prefixIcon: const Icon(Icons.credit_card),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(15),
            ],
            validator: (v) {
              if (v == null || v.trim().length < 6) {
                return 'En az 6 karakter girin';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tcController,
            decoration: InputDecoration(
              labelText: 'T.C. Kimlik No (Opsiyonel)',
              hintText: '11 haneli TC kimlik no',
              prefixIcon: const Icon(Icons.person_outline),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            validator: (v) {
              if (v != null && v.isNotEmpty && v.length != 11) {
                return 'TC kimlik numarası 11 haneli olmalıdır';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitManualCard,
              icon: const Icon(Icons.verified_user),
              label:
                  const Text('Kartı Dogrula', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() {
                _cardStep = CardStep.methodSelect;
                _cardErrorMessage = null;
              }),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Geri Dön'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVerifiedCardBanner(theme),
          const SizedBox(height: 20),
          Card(
            color: theme.colorScheme.primary.withOpacity(0.1),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        'Bineceginiz ve ineceginizduragi secerekoföre önceden bilgilendirin.',
                        style: TextStyle(color: theme.colorScheme.primary))),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          _buildStepHeader(
              theme, 1, 'Binis Duragi Secin', _selectedBoardingStop != null),
          const SizedBox(height: 12),
          if (_nearbyStops.isEmpty)
            const Center(child: Text('Yakinda durak bulunamadi'))
          else
            SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _nearbyStops.length,
                itemBuilder: (context, index) {
                  final stop = _nearbyStops[index];
                  final isSelected =
                      _selectedBoardingStop?.stopId == stop.stopId;
                  final distance = stop.distanceFromUser ?? 0;

                  return GestureDetector(
                    onTap: () => _onBoardingStopSelected(stop),
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                    color: theme.colorScheme.primary
                                        .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2))
                              ]
                            : null,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.directions_bus_filled,
                              color: isSelected
                                  ? Colors.white
                                  : theme.colorScheme.primary,
                              size: 24),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(stop.stopName,
                                style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(height: 8),
                          Text(
                              distance < 1000
                                  ? '${distance.toInt()} m'
                                  : '${(distance / 1000).toStringAsFixed(1)} km',
                              style: TextStyle(
                                  color:
                                      isSelected ? Colors.white70 : Colors.grey,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          _buildStepHeader(theme, 2, 'Hat Secin', _selectedRoute != null),
          const SizedBox(height: 12),
          if (_selectedBoardingStop == null)
            _buildPlaceholder('Önce binis duragını secin')
          else if (_availableRoutes.isEmpty)
            _buildLoadingPlaceholder()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableRoutes.map((route) {
                final isSelected = _selectedRoute?.routeId == route.routeId;
                return GestureDetector(
                  onTap: () => _onRouteSelected(route),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.secondary
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.secondary
                              : Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(8)),
                          child: Center(
                              child: Text(route.routeShortName,
                                  style: TextStyle(
                                      color: isSelected
                                          ? theme.colorScheme.secondary
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14))),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                              route.routeLongName.length > 20
                                  ? '${route.routeLongName.substring(0, 20)}...'
                                  : route.routeLongName,
                              style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          if (_selectedRoute != null) ...[
            const SizedBox(height: 24),
            _buildStepHeader(theme, 3, 'Inis Duragi Secin (Opsiyonel)',
                _selectedAlightingStop != null),
            const SizedBox(height: 12),
            if (_routeStops.isEmpty)
              _buildLoadingPlaceholder()
            else
              Builder(builder: (context) {
                final boardingIdStr =
                    _selectedBoardingStop?.stopId.toString() ?? '';
                final boardingNameStr =
                    _selectedBoardingStop?.stopName.trim().toLowerCase() ?? '';

                int boardingIndex = _routeStops
                    .indexWhere((s) => s.stopId.toString() == boardingIdStr);
                if (boardingIndex == -1 && _selectedBoardingStop != null) {
                  boardingIndex = _routeStops.indexWhere((s) =>
                      s.stopName.trim().toLowerCase() == boardingNameStr);
                }

                final stopsAfterBoarding = boardingIndex == -1
                    ? _routeStops
                    : _routeStops.sublist(boardingIndex + 1);

                if (stopsAfterBoarding.isEmpty) {
                  return _buildPlaceholder('Bu hattın son duragındasınız.');
                }

                return SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: stopsAfterBoarding.length,
                    itemBuilder: (context, index) {
                      final realIndex = boardingIndex == -1
                          ? index
                          : boardingIndex + 1 + index;
                      final stop = stopsAfterBoarding[index];
                      final isSelected =
                          _selectedAlightingStop?.stopId == stop.stopId;

                      return GestureDetector(
                        onTap: () => _onAlightingStopSelected(stop),
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.orange : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isSelected
                                    ? Colors.orange
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    '${realIndex + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.orange
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Text(stop.stopName,
                                    style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 11),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
          ],
          if (_selectedRoute != null && _selectedAlightingStop != null) ...[
            const SizedBox(height: 24),
            _buildStepHeader(theme, 4, 'Arac Secin (Opsiyonel)', false),
            const SizedBox(height: 8),
            Text('Araclar duraga olan mesafesine göre sıralanmıştır',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 12),
            if (_vehiclesWithDistance.isNotEmpty)
              _buildClosestDriverCard(theme)
            else
              _buildPlaceholder('Bu hatta aktif arac yok'),
            const SizedBox(height: 12),
            if (_vehiclesWithDistance.isNotEmpty)
              Column(children: [
                GestureDetector(
                  onTap: () => _onVehicleSelected(null),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _selectedVehicle == null
                          ? theme.colorScheme.primary.withOpacity(0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedVehicle == null
                            ? theme.colorScheme.primary
                            : Colors.grey.shade300,
                        width: _selectedVehicle == null ? 2 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.group,
                          color: _selectedVehicle == null
                              ? theme.colorScheme.primary
                              : Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                        'Tüm Araclara Gönder (${_vehiclesWithDistance.length} arac)',
                        style: TextStyle(
                          fontWeight: _selectedVehicle == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedVehicle == null
                              ? theme.colorScheme.primary
                              : Colors.black87,
                        ),
                      )),
                    ]),
                  ),
                ),
                ..._vehiclesWithDistance.asMap().entries.map((entry) {
                  final index = entry.key;
                  final vehicleWithDist = entry.value;
                  final vehicle = vehicleWithDist.vehicle;
                  final distance = vehicleWithDist.distanceToStop;
                  final isSelected = _selectedVehicle?.id == vehicle.id;
                  final distanceColor = distance < 1000
                      ? Colors.green
                      : distance < 5000
                          ? Colors.orange
                          : Colors.red;
                  final distanceText = distance < 1000
                      ? '${distance.toInt()} m'
                      : '${(distance / 1000).toStringAsFixed(1)} km';

                  return GestureDetector(
                    onTap: () => _onVehicleSelected(vehicle),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary.withOpacity(0.1)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: distanceColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8)),
                          child: Center(
                              child: Text('${index + 1}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: distanceColor))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vehicle.name,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.black87)),
                            if (vehicle.driverName != null)
                              Text('Sofür: ${vehicle.driverName}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                          ],
                        )),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: distanceColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(children: [
                            Text(distanceText,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: distanceColor,
                                    fontWeight: FontWeight.bold)),
                            Text('uzaklikta',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: distanceColor.withOpacity(0.7))),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }),
              ]),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_selectedBoardingStop != null && _selectedRoute != null)
                      ? _sendNotification
                      : null,
              icon: const Icon(Icons.send),
              label:
                  const Text('Soföre Bildir', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _resetCard,
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Farkli Kart Kullan',
                  style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildVerifiedCardBanner(ThemeData theme) {
    return ScaleTransition(
      scale: _cardSuccessAnimation,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade600, Colors.purple.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(children: [
          const Icon(Icons.verified, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Engelli Kartı Dogrulandi',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              Text(
                '$_verifiedCardType  •  %$_verifiedDiscountRate Indirim  •  $_verifiedCardNumber',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('AKTİF',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadNearbyStops,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendingView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications_active,
                    size: 56, color: theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text('Soföre Bildiriliyor...',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
                backgroundColor: theme.colorScheme.primary.withOpacity(0.2)),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
                '${_selectedRoute?.routeShortName} - ${_selectedBoardingStop?.stopName}',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center),
          ),
          if (_selectedVehicle != null) ...[
            const SizedBox(height: 8),
            Text('Arac: ${_selectedVehicle!.name}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _buildSuccessView(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5)
                  ],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 64),
              ),
            ),
            const SizedBox(height: 32),
            Text('Bildirim Gönderildi!',
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.green.shade700)),
            const SizedBox(height: 8),
            Text('Sofür sizi bekleyecek',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey)),
            const SizedBox(height: 32),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                          child: Text(_selectedRoute?.routeShortName ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18))),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(_selectedRoute?.routeLongName ?? '',
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  const Divider(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place, color: theme.colorScheme.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Binis: ${_selectedBoardingStop?.stopName ?? ''}',
                              style: theme.textTheme.bodyLarge),
                          if (_selectedAlightingStop != null) ...[
                            const SizedBox(height: 4),
                            Text('Inis: ${_selectedAlightingStop!.stopName}',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey.shade700)),
                          ],
                        ],
                      )),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(children: [
                    const Icon(Icons.accessibility_new, color: Colors.purple),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Engelli Yolcu Bildirimi',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple)),
                        Text(
                            '$_verifiedCardType  •  %$_verifiedDiscountRate indirim',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.purple.shade300)),
                      ],
                    )),
                  ]),
                  if (_sentVehicleId != null) ...[
                    const Divider(height: 24),
                    Row(children: [
                      Icon(Icons.directions_bus,
                          color: theme.colorScheme.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text('Hedef: $_sentVehicleId',
                              style: theme.textTheme.bodyMedium)),
                    ]),
                  ],
                  if (_sentTimestamp != null) ...[
                    const Divider(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.schedule,
                            color: theme.colorScheme.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gönderme Zamanı (Türkiye):',
                                style: theme.textTheme.bodySmall),
                            Text(
                              _formatTimestamp(_sentTimestamp!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700),
                            ),
                          ],
                        )),
                      ],
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200)),
              child: Row(children: [
                Icon(Icons.notifications_active,
                    color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Arac duraga yaklastiginda size bildirim göndereceğiz.',
                        style: TextStyle(
                            color: Colors.blue.shade700, fontSize: 12))),
              ]),
            ),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.home),
                      label: const Text('Ana Sayfa'))),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton.icon(
                      onPressed: _resetNotification,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Yeni Bildirim'))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildPlaceholder(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Center(
          child: Text(message, style: TextStyle(color: Colors.grey.shade600))),
    );
  }

  Widget _buildClosestDriverCard(ThemeData theme) {
    final closestVehicle = _vehiclesWithDistance.first;
    final vehicle = closestVehicle.vehicle;
    final distance = closestVehicle.distanceToStop;
    final distanceText = distance < 1000
        ? '${distance.toInt()} metre'
        : '${(distance / 1000).toStringAsFixed(1)} kilometre';
    final estimatedTime = (distance / (30 * 1000 / 60)).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade300, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.blue.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.location_on_outlined,
              color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Size En Yakin Sofür',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: Colors.blue.shade200,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.directions_bus,
                color: Colors.blue.shade700, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(vehicle.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900)),
              if (vehicle.driverName != null)
                Text('Sofür: ${vehicle.driverName}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.blue.shade700)),
            ],
          )),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8)),
          child: IntrinsicHeight(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                      child: Column(children: [
                    Text('Mesafe',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.blue.shade600)),
                    const SizedBox(height: 4),
                    Text(distanceText,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900),
                        textAlign: TextAlign.center),
                  ])),
                  Container(width: 1, color: Colors.blue.shade300),
                  Expanded(
                      child: Column(children: [
                    Text('Tahmini Zaman',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.blue.shade600)),
                    const SizedBox(height: 4),
                    Text('~$estimatedTime dk',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900),
                        textAlign: TextAlign.center),
                  ])),
                ]),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    'Bu sofür secilirse, bildirim en hızlı sekilde ulaşacak.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.blue.shade700))),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStepHeader(
      ThemeData theme, int step, String title, bool completed) {
    return Row(children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: completed ? Colors.green : theme.colorScheme.primary,
            shape: BoxShape.circle),
        child: Center(
            child: completed
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text('$step',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp;
    }
  }
}

class VehicleLocationWithDistance {
  final VehicleLocation vehicle;
  final double distanceToStop;

  const VehicleLocationWithDistance({
    required this.vehicle,
    required this.distanceToStop,
  });
}