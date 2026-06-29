import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../providers/accessibility_provider.dart';
import '../services/tts_service.dart';

enum CardVerificationMethod { nfc, manual, qr }

enum CardVerificationStatus { idle, scanning, success, failed, notSupported }

class DisabilityCardScreen extends StatefulWidget {
  const DisabilityCardScreen({super.key});

  @override
  State<DisabilityCardScreen> createState() => _DisabilityCardScreenState();
}

class _DisabilityCardScreenState extends State<DisabilityCardScreen>
    with TickerProviderStateMixin {
  final TtsService _ttsService = TtsService();

  CardVerificationMethod _selectedMethod = CardVerificationMethod.nfc;
  CardVerificationStatus _status = CardVerificationStatus.idle;

  bool _nfcSupported = false;
  bool _cardVerified = false;
  Map<String, dynamic>? _verifiedCardData;

  final _cardController = TextEditingController();
  final _tcController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _pulseController;
  late AnimationController _successController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _successAnimation = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );

    _checkNfcSupport();
  }

  @override
  void dispose() {
    try {
      NfcManager.instance.stopSession();
    } catch (_) {}
    _pulseController.dispose();
    _successController.dispose();
    _cardController.dispose();
    _tcController.dispose();
    super.dispose();
  }

  Future<void> _checkNfcSupport() async {
    try {
      final supported = await NfcManager.instance.isAvailable();
      setState(() {
        _nfcSupported = supported;
        if (!supported) _selectedMethod = CardVerificationMethod.manual;
      });
    } catch (e) {
      setState(() {
        _nfcSupported = false;
        _selectedMethod = CardVerificationMethod.manual;
      });
    }
  }

  // ── NFC OKUMA ──
  Future<void> _startNfcScan() async {
    if (!_nfcSupported) return;

    setState(() => _status = CardVerificationStatus.scanning);

    final accessibility = context.read<AccessibilityProvider>();
    if (accessibility.screenReaderEnabled) {
      await _ttsService.speak(
          'NFC tarama başladı. Kartınızı telefonun arkasına yaklaştırın.');
    }

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          await NfcManager.instance.stopSession();
          await _processNfcTag(tag);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = CardVerificationStatus.failed);
    }
  }

  Future<void> _processNfcTag(NfcTag tag) async {
    try {
      String? cardId;

      // NDEF kayitlarindan oku (nfc_manager_ndef)
      final ndef = Ndef.from(tag);
      if (ndef != null) {
        final cachedMessage = ndef.cachedMessage;
        if (cachedMessage != null) {
          for (final record in cachedMessage.records) {
            final payload = String.fromCharCodes(record.payload);
            if (payload.contains('EK:') || payload.length > 8) {
              cardId = payload.replaceAll(RegExp(r'[^0-9A-Z]'), '');
              break;
            }
          }
        }
      }

      // NDEF yoksa tag identifier kullan
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

      if (cardId != null) {
        await _verifyCard(cardId: cardId!, method: 'NFC');
      } else {
        if (!mounted) return;
        setState(() => _status = CardVerificationStatus.failed);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = CardVerificationStatus.failed);
    }
  }

  void _stopNfcScan() {
    try {
      NfcManager.instance.stopSession();
    } catch (_) {}
    setState(() => _status = CardVerificationStatus.idle);
  }

  // ── KART DOĞRULAMA ──
  Future<void> _verifyCard({
    required String cardId,
    String? tcNumber,
    required String method,
  }) async {
    setState(() => _status = CardVerificationStatus.scanning);

    try {
      await Future.delayed(const Duration(seconds: 2));

      final bool isValid = cardId.length >= 6;

      if (!mounted) return;

      if (isValid) {
        final cardData = {
          'cardId': cardId,
          'holderName': 'Kart Sahibi',
          'cardType': _getCardType(cardId),
          'verificationMethod': method,
          'verifiedAt': DateTime.now().toIso8601String(),
          'discountRate': _getDiscountRate(cardId),
        };

        setState(() {
          _status = CardVerificationStatus.success;
          _cardVerified = true;
          _verifiedCardData = cardData;
        });

        _successController.forward();

        final accessibility = context.read<AccessibilityProvider>();
        if (accessibility.screenReaderEnabled) {
          await _ttsService
              .speak('Engelli kartı doğrulandı! ${cardData['cardType']} kartı. '
                  '%${cardData['discountRate']} indirim hakkınız mevcuttur.');
        }
      } else {
        setState(() => _status = CardVerificationStatus.failed);

        final accessibility = context.read<AccessibilityProvider>();
        if (accessibility.screenReaderEnabled) {
          await _ttsService.speak('Kart doğrulanamadı. Lütfen tekrar deneyin.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = CardVerificationStatus.failed);
    }
  }

  String _getCardType(String cardId) {
    if (cardId.startsWith('A')) return 'Ağır Engelli';
    if (cardId.startsWith('B')) return 'Orta Engelli';
    return 'Engelli';
  }

  int _getDiscountRate(String cardId) {
    if (cardId.startsWith('A')) return 100;
    if (cardId.startsWith('B')) return 50;
    return 50;
  }

  Future<void> _submitManualForm() async {
    if (!_formKey.currentState!.validate()) return;
    await _verifyCard(
      cardId: _cardController.text.trim(),
      tcNumber: _tcController.text.trim(),
      method: 'Manuel',
    );
  }

  void _reset() {
    _successController.reset();
    _cardController.clear();
    _tcController.clear();
    setState(() {
      _status = CardVerificationStatus.idle;
      _cardVerified = false;
      _verifiedCardData = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engelli Kartı Doğrulama'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _cardVerified
            ? _buildSuccessView(theme)
            : _buildVerificationView(theme),
      ),
    );
  }

  Widget _buildSuccessView(ThemeData theme) {
    final data = _verifiedCardData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ScaleTransition(
            scale: _successAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade700],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 24,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(Icons.verified, color: Colors.white, size: 64),
            ),
          ),
          const SizedBox(height: 24),
          Text('Kart Doğrulandı!',
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          const SizedBox(height: 8),
          Text('Engelli yolcu haklarınız aktif',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey)),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF283593)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A237E).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.accessibility_new,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    Text('ENGELLİ SEYAHAT KARTI',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white70, letterSpacing: 1.5)),
                  ],
                ),
                const SizedBox(height: 20),
                Text(data['cardId'],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('KART TÜRÜ',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(data['cardType'],
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('İNDİRİM',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 10)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('%${data['discountRate']}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Doğrulama: ${data['verificationMethod']}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Haklarınız',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800)),
                const SizedBox(height: 12),
                _buildRight(Icons.directions_bus,
                    'Toplu taşımada %${data['discountRate']} indirim'),
                _buildRight(Icons.accessible, 'Öncelikli biniş hakkı'),
                _buildRight(Icons.support_agent, 'Şoföre engelli bildirimi'),
                _buildRight(Icons.chair, 'Engelli koltuğu rezervasyonu'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Farklı Kart'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, _verifiedCardData),
                  icon: const Icon(Icons.check),
                  label: const Text('Devam Et'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRight(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade600, size: 18),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: Colors.blue.shade800)),
        ],
      ),
    );
  }

  Widget _buildVerificationView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.accessibility_new,
                    color: Color(0xFF1A237E), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Engelli kartınızı doğrulayın. '
                    'NFC, kart numarası veya QR kod ile giriş yapabilirsiniz.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Doğrulama Yöntemi',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_nfcSupported)
                Expanded(
                  child: _buildMethodCard(
                    icon: Icons.nfc,
                    label: 'NFC',
                    subtitle: 'Kartı yaklaştır',
                    method: CardVerificationMethod.nfc,
                    theme: theme,
                  ),
                ),
              if (_nfcSupported) const SizedBox(width: 10),
              Expanded(
                child: _buildMethodCard(
                  icon: Icons.keyboard,
                  label: 'Manuel',
                  subtitle: 'Numara gir',
                  method: CardVerificationMethod.manual,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMethodCard(
                  icon: Icons.qr_code_scanner,
                  label: 'QR Kod',
                  subtitle: 'Kodu tara',
                  method: CardVerificationMethod.qr,
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (_selectedMethod == CardVerificationMethod.nfc)
            _buildNfcSection(theme),
          if (_selectedMethod == CardVerificationMethod.manual)
            _buildManualSection(theme),
          if (_selectedMethod == CardVerificationMethod.qr)
            _buildQrSection(theme),
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required CardVerificationMethod method,
    required ThemeData theme,
  }) {
    final isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: () {
        if (_status == CardVerificationStatus.scanning) _stopNfcScan();
        setState(() {
          _selectedMethod = method;
          _status = CardVerificationStatus.idle;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1A237E).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            Text(subtitle,
                style: TextStyle(
                    color: isSelected ? Colors.white70 : Colors.grey,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildNfcSection(ThemeData theme) {
    final isScanning = _status == CardVerificationStatus.scanning;
    final isFailed = _status == CardVerificationStatus.failed;

    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) => Transform.scale(
            scale: isScanning ? _pulseAnimation.value : 1.0,
            child: GestureDetector(
              onTap: isScanning ? _stopNfcScan : _startNfcScan,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFailed
                      ? Colors.red.shade50
                      : isScanning
                          ? const Color(0xFF1A237E).withOpacity(0.1)
                          : Colors.grey.shade100,
                  border: Border.all(
                    color: isFailed
                        ? Colors.red
                        : isScanning
                            ? const Color(0xFF1A237E)
                            : Colors.grey.shade300,
                    width: isScanning ? 3 : 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isFailed ? Icons.error_outline : Icons.nfc,
                      size: 72,
                      color: isFailed
                          ? Colors.red
                          : isScanning
                              ? const Color(0xFF1A237E)
                              : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isFailed
                          ? 'Hata! Tekrar dene'
                          : isScanning
                              ? 'Taranıyor...'
                              : 'Başlatmak için\ndokun',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isFailed
                            ? Colors.red
                            : isScanning
                                ? const Color(0xFF1A237E)
                                : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isScanning
              ? 'Engelli kartınızı telefonun NFC bölgesine yaklaştırın'
              : 'Yukarıdaki alana dokunarak NFC taramasını başlatın',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (isScanning)
          OutlinedButton.icon(
            onPressed: _stopNfcScan,
            icon: const Icon(Icons.stop),
            label: const Text('İptal'),
          ),
        if (isFailed) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _startNfcScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ],
    );
  }

  Widget _buildManualSection(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _cardController,
            decoration: InputDecoration(
              labelText: 'Engelli Kart Numarası',
              hintText: 'Örn: EK123456789',
              prefixIcon: const Icon(Icons.credit_card),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
              LengthLimitingTextInputFormatter(12),
            ],
            validator: (v) {
              if (v == null || v.trim().length < 6) {
                return 'Geçerli bir kart numarası girin (min. 6 karakter)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _tcController,
            decoration: InputDecoration(
              labelText: 'T.C. Kimlik No (Opsiyonel)',
              hintText: '11 haneli TC kimlik no',
              prefixIcon: const Icon(Icons.person),
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
          if (_status == CardVerificationStatus.failed)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200)),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Kart doğrulanamadı. Bilgileri kontrol edin.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _status == CardVerificationStatus.scanning
                  ? null
                  : _submitManualForm,
              icon: _status == CardVerificationStatus.scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified_user),
              label: Text(
                _status == CardVerificationStatus.scanning
                    ? 'Doğrulanıyor...'
                    : 'Kartı Doğrula',
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection(ThemeData theme) {
    return Column(
      children: [
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 64),
                    const SizedBox(height: 12),
                    const Text('Kamera başlatılıyor...',
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    const Text(
                      'pubspec.yaml\'a\nmobile_scanner ekleyin',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Engelli kartınızdaki QR kodu kamera çerçevesine getirin',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }
}
