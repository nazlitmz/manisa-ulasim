import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../services/ai_service.dart';
import '../models/ai_message_model.dart';
import '../providers/location_provider.dart';
import '../config/routes.dart';
import '../config/popular_places_config.dart';
import '../services/city_detection_service.dart';
import '../services/city_database_manager.dart';

/// AI Chat ekranı - Doğal dil ile ulaşım asistanı
class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  late final AIService _aiService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<dynamic> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  AIResponse? _pendingConfirmation;

  // Şehire göre örnek sorular
  List<Map<String, String>> get _quickExamples {
    final city = CityDetectionService.instance.currentCity;
    if (city == SupportedCity.cyprus) {
      return [
        {
          'label': 'Lefkoşa\'ya nasıl giderim?',
          'query': 'Lefkoşa\'ya nasıl giderim?'
        },
        {
          'label': 'Girne\'ye gitmek istiyorum',
          'query': 'Girne\'ye gitmek istiyorum'
        },
        {'label': 'Yakın duraklar', 'query': 'Yakındaki duraklar nerede?'},
        {'label': 'Tüm hatlar', 'query': 'Hangi hatlar var?'},
      ];
    }
    return [
      {
        'label': '1 hat ne zaman gelir?',
        'query': '1 numaralı hat ne zaman gelir?'
      },
      {'label': 'CBÜ\'ye nasıl giderim?', 'query': 'CBÜ\'ye nasıl giderim?'},
      {'label': 'Yakın duraklar', 'query': 'Yakındaki duraklar nerede?'},
      {'label': 'Tüm hatlar', 'query': 'Hangi hatlar var?'},
    ];
  }

  String get _welcomeMessage {
    final cityName = PopularPlacesConfig.cityName;
    final city = CityDetectionService.instance.currentCity;

    if (city == SupportedCity.cyprus) {
      return 'Merhaba! 👋\n\nBen $cityName asistanınızım. '
          'Otobüs güzergahları ve duraklar hakkında yardımcı olabilirim.\n\n'
          'Örnekler:\n'
          '• "Lefkoşa\'ya nasıl giderim?"\n'
          '• "Girne\'ye gitmek istiyorum"\n'
          '• "Yakındaki duraklar nerede?"';
    }
    return 'Merhaba! 👋\n\nBen $cityName asistanınızım. '
        'Otobüs saatleri, güzergahlar ve duraklar hakkında yardımcı olabilirim.\n\n'
        'Örnekler:\n'
        '• "1 numaralı hat kaç dakikada gelir?"\n'
        '• "Karaköy Karakol\'dan Meydan AVM\'ye nasıl giderim?"\n'
        '• "Yakındaki duraklar nerede?"';
  }

  @override
  void initState() {
    super.initState();
    _aiService = AIService(apiKey: _getApiKey());

    _addMessage(AIMessage(
      role: 'assistant',
      content: _welcomeMessage,
    ));
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getApiKey() {
    final key = dotenv.env['GROQ_API_KEY'] ?? '';
    if (key.isEmpty) {
      throw Exception('.env dosyasında GROQ_API_KEY bulunamadı.');
    }
    return key;
  }

  void _addMessage(AIMessage message) {
    setState(() {
      _items.add(message);
      _errorMessage = null;
    });
    _scrollToBottom();
  }

  void _addNavigationSuggestion(_NavigationSuggestion suggestion) {
    setState(() => _items.add(suggestion));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (_pendingConfirmation != null) {
      final n = text.trim().toLowerCase();
      final isYes =
          n == 'evet' || n == 'e' || n.startsWith('evet') || n == 'yes';
      final isNo =
          n == 'hayır' || n == 'hayir' || n == 'h' || n.startsWith('hayır');

      if (isYes || isNo) {
        _addMessage(AIMessage(role: 'user', content: text));
        _textController.clear();
        await _handleConfirmation(isYes);
        return;
      }
      _pendingConfirmation = null;
    }

    _addMessage(AIMessage(role: 'user', content: text));
    _textController.clear();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final locationProvider = context.read<LocationProvider>();
      final userLat = locationProvider.currentPosition?.latitude;
      final userLon = locationProvider.currentPosition?.longitude;

      final history =
          _items.whereType<AIMessage>().where((m) => !m.isSystem).toList();

      final response = await _aiService.chat(
        text,
        conversationHistory: history,
        userLat: userLat,
        userLon: userLon,
      );

      _addMessage(AIMessage(
        role: 'assistant',
        content: response.response,
      ));

      if (response.awaitingConfirmation) {
        _pendingConfirmation = response;
        _addNavigationSuggestion(_NavigationSuggestion(
          label: '✅ Evet, o durağım',
          route: '__confirm_yes__',
          args: null,
        ));
        _addNavigationSuggestion(_NavigationSuggestion(
          label: '❌ Hayır, GPS konumumu kullan',
          route: '__confirm_no__',
          args: null,
        ));
      }

      if (!response.awaitingConfirmation &&
          response.hasNavigation &&
          response.navigationRoute != null) {
        _addNavigationSuggestion(_NavigationSuggestion(
          label: _navigationLabel(response.navigationRoute!),
          route: response.navigationRoute!,
          args: response.navigationArgs,
        ));
      }
    } on AIException catch (e) {
      setState(() => _errorMessage = e.message);
      _addMessage(AIMessage(
        role: 'assistant',
        content: '⚠️ ${e.message}',
      ));
    } catch (e) {
      setState(() => _errorMessage = 'Beklenmeyen hata oluştu.');
      _addMessage(AIMessage(
        role: 'assistant',
        content: 'Üzgünüm, bir hata oluştu. Lütfen tekrar deneyin.',
      ));
      debugPrint('❌ Chat hatası: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _navigationLabel(String route) {
    switch (route) {
      case AppRoutes.nearbyStops:
        return '🗺️ Yakındaki Durakları Haritada Göster';
      case AppRoutes.destinationSearch:
        return '🧭 Detaylı Yol Tarifi Al';
      case AppRoutes.allRoutes:
        return '🚌 Tüm Hatları Görüntüle';
      default:
        return '➡️ Sayfaya Git';
    }
  }

  Future<void> _handleConfirmation(bool userConfirmed) async {
    final pending = _pendingConfirmation;
    _pendingConfirmation = null;
    if (pending == null) return;

    setState(() => _isLoading = true);

    try {
      if (userConfirmed) {
        _addMessage(AIMessage(
          role: 'assistant',
          content:
              '✅ Anlaşıldı, ${pending.pendingBoardingStop?.stopName ?? 'belirtilen'} durağından rota hesaplanıyor...',
        ));

        final result = await _aiService.routeFromConfirmedStop(
          boardingStop: pending.pendingBoardingStop,
          destination: pending.pendingDestination ?? '',
        );

        _addMessage(AIMessage(role: 'assistant', content: result.response));
        if (result.hasNavigation && result.navigationRoute != null) {
          _addNavigationSuggestion(_NavigationSuggestion(
            label: _navigationLabel(result.navigationRoute!),
            route: result.navigationRoute!,
            args: result.navigationArgs,
          ));
        }
      } else {
        _addMessage(AIMessage(
          role: 'assistant',
          content: '📍 GPS konumunuza göre rota hesaplanıyor...',
        ));

        final lat = pending.pendingUserLat;
        final lon = pending.pendingUserLon;
        if (lat != null && lon != null && pending.pendingDestination != null) {
          final result = await _aiService.routeFromGps(
            destination: pending.pendingDestination!,
            userLat: lat,
            userLon: lon,
          );
          _addMessage(AIMessage(role: 'assistant', content: result.response));
          if (result.hasNavigation && result.navigationRoute != null) {
            _addNavigationSuggestion(_NavigationSuggestion(
              label: _navigationLabel(result.navigationRoute!),
              route: result.navigationRoute!,
              args: result.navigationArgs,
            ));
          }
        }
      }
    } catch (e) {
      _addMessage(AIMessage(
          role: 'assistant', content: 'Hata oluştu. Lütfen tekrar deneyin.'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.purple, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('AI Asistan'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Konuşmayı Temizle',
            onPressed: () {
              setState(() {
                _items.clear();
                _errorMessage = null;
                _items.add(AIMessage(
                  role: 'assistant',
                  content: 'Konuşma temizlendi. Yeni bir soru sorabilirsiniz!',
                ));
              });
              _aiService.clearCache();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      if (item is AIMessage) {
                        return _ChatBubble(message: item, isDark: isDark);
                      } else if (item is _NavigationSuggestion) {
                        if (item.route == '__confirm_yes__' ||
                            item.route == '__confirm_no__') {
                          return _NavSuggestionButton(
                            suggestion: item,
                            onTap: () => _handleConfirmation(
                                item.route == '__confirm_yes__'),
                          );
                        }
                        return _NavSuggestionButton(
                          suggestion: item,
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              item.route,
                              arguments: item.args,
                            );
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style:
                          TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _errorMessage = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const _TypingIndicator(),
                  const SizedBox(width: 12),
                  Text('Yanıt hazırlanıyor...',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey)),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + navBottom),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Bir şey sorun...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2C2C2C)
                          : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _isLoading ? null : _sendMessage,
                    enabled: !_isLoading,
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  onPressed: _isLoading
                      ? null
                      : () => _sendMessage(_textController.text),
                  backgroundColor:
                      _isLoading ? Colors.grey : theme.colorScheme.primary,
                  elevation: 0,
                  child: Icon(
                    _isLoading ? Icons.hourglass_empty : Icons.send,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final examples = _quickExamples;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 64, color: Colors.purple),
            ),
            const SizedBox(height: 24),
            Text('AI Asistanınız Hazır!',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Doğal dilde soru sorabilirsiniz',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: examples
                  .map((e) => _QuickReplyChip(
                        label: e['label']!,
                        onTap: () => _sendMessage(e['query']!),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Navigation Suggestion model
// ═══════════════════════════════════════════════════════════════════

class _NavigationSuggestion {
  final String label;
  final String route;
  final Map<String, dynamic>? args;

  _NavigationSuggestion({
    required this.label,
    required this.route,
    this.args,
  });
}

// ═══════════════════════════════════════════════════════════════════
// Nav Suggestion Button Widget
// ═══════════════════════════════════════════════════════════════════

class _NavSuggestionButton extends StatelessWidget {
  final _NavigationSuggestion suggestion;
  final VoidCallback onTap;

  const _NavSuggestionButton({
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 44),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                suggestion.label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios,
                  size: 12, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Chat Bubble Widget
// ═══════════════════════════════════════════════════════════════════

class _ChatBubble extends StatelessWidget {
  final AIMessage message;
  final bool isDark;

  const _ChatBubble({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.purple.withOpacity(0.1),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.purple, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : (isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Icon(Icons.person,
                  color: theme.colorScheme.primary, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Typing Indicator
// ═══════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = ((_controller.value * 3) - i).clamp(0.0, 1.0);
            final opacity =
                (offset < 0.5 ? offset * 2 : (1 - offset) * 2).clamp(0.3, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Quick Reply Chip
// ═══════════════════════════════════════════════════════════════════

class _QuickReplyChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickReplyChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.purple.withOpacity(0.1),
      labelStyle: const TextStyle(
        color: Colors.purple,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      side: BorderSide(color: Colors.purple.withOpacity(0.3)),
    );
  }
}
