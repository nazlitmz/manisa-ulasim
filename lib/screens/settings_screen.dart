import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/accessibility_provider.dart';
import '../config/routes.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accessibility = context.watch<AccessibilityProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Erişilebilirlik
          Text('Erişilebilirlik', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Büyük Yazı Tipi'),
                  subtitle: const Text('Daha kolay okuma için'),
                  value: accessibility.largeText,
                  onChanged: (value) => accessibility.setLargeText(value),
                  secondary: const Icon(Icons.text_fields),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Yüksek Kontrast'),
                  subtitle: const Text('Daha belirgin renkler'),
                  value: accessibility.highContrast,
                  onChanged: (value) => accessibility.setHighContrast(value),
                  secondary: const Icon(Icons.contrast),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Sesli Okuma'),
                  subtitle: const Text('Önemli bilgileri sesli oku'),
                  value: accessibility.screenReaderEnabled,
                  onChanged: (value) => accessibility.setScreenReader(value),
                  secondary: const Icon(Icons.volume_up),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Sesli okuma testi
          Text('Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Sesli Okuma Testi'),
              subtitle: const Text('TTS ayarlarını test edin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, AppRoutes.ttsTest),
            ),
          ),

          const SizedBox(height: 24),

          // Uygulama bilgileri
          Text('Hakkında', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Uygulama Versiyonu'),
                  trailing: const Text('1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Geliştirici'),
                  trailing: const Text('Manisa Ulaşım'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.description),
                  title: Text('Veri Kaynağı'),
                  trailing: Text('GTFS'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Uyarı
          Card(
            color: Colors.orange.withOpacity(0.1),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bu uygulama bir karar destek sistemidir. '
                      'Gerçek sefer saatleri trafik koşullarına göre değişebilir.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
