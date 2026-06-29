import 'package:flutter/material.dart';
import '../services/tts_service.dart';

class TtsTestScreen extends StatefulWidget {
  const TtsTestScreen({super.key});

  @override
  State<TtsTestScreen> createState() => _TtsTestScreenState();
}

class _TtsTestScreenState extends State<TtsTestScreen> {
  final TtsService _ttsService = TtsService();
  bool _isPlaying = false;
  double _volume = 1.0;
  double _pitch = 1.0;
  double _rate = 0.5;

  final List<String> _testMessages = [
    'Merhaba, Manisa Ulaşım uygulamasına hoş geldiniz.',
    'Bir sonraki durağınız: Meydan AVM',
    '45 numaralı hat 5 dakika içinde gelecek.',
    'CBÜ Kampüs durağında ininiz.',
    'Dikkat! Otobüs durağa yaklaşıyor.',
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _ttsService.initialize();
    await _ttsService.setVolume(_volume);
    await _ttsService.setPitch(_pitch);
    await _ttsService.setRate(_rate);
  }

  Future<void> _speak(String text) async {
    if (_isPlaying) {
      await _ttsService.stop();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _ttsService.speak(text);
      setState(() => _isPlaying = false);
    }
  }

  @override
  void dispose() {
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesli Okuma Testi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Ayarlar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ses Ayarları', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),

                  // Ses seviyesi
                  Row(
                    children: [
                      const Icon(Icons.volume_up),
                      const SizedBox(width: 8),
                      const Text('Ses:'),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          min: 0,
                          max: 1,
                          onChanged: (value) {
                            setState(() => _volume = value);
                            _ttsService.setVolume(value);
                          },
                        ),
                      ),
                      Text('${(_volume * 100).toInt()}%'),
                    ],
                  ),

                  // Hız
                  Row(
                    children: [
                      const Icon(Icons.speed),
                      const SizedBox(width: 8),
                      const Text('Hız:'),
                      Expanded(
                        child: Slider(
                          value: _rate,
                          min: 0.1,
                          max: 1.0,
                          onChanged: (value) {
                            setState(() => _rate = value);
                            _ttsService.setRate(value);
                          },
                        ),
                      ),
                      Text('${(_rate * 100).toInt()}%'),
                    ],
                  ),

                  // Ton
                  Row(
                    children: [
                      const Icon(Icons.music_note),
                      const SizedBox(width: 8),
                      const Text('Ton:'),
                      Expanded(
                        child: Slider(
                          value: _pitch,
                          min: 0.5,
                          max: 2.0,
                          onChanged: (value) {
                            setState(() => _pitch = value);
                            _ttsService.setPitch(value);
                          },
                        ),
                      ),
                      Text(_pitch.toStringAsFixed(1)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Test mesajları
          Text('Test Mesajları', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          ..._testMessages.map((message) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(message),
                  trailing: IconButton(
                    icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    onPressed: () => _speak(message),
                  ),
                ),
              )),

          const SizedBox(height: 16),

          // Durum
          Card(
            color: _isPlaying ? Colors.green.withOpacity(0.1) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _isPlaying ? Icons.volume_up : Icons.volume_off,
                    color: _isPlaying ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(_isPlaying ? 'Konuşuyor...' : 'Hazır'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
