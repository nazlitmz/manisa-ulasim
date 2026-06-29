// lib/services/terminal_message_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class TerminalMessageService {
  /// Terminale mesaj gönder
  Future<Map<String, dynamic>?> sendTerminalMessage({
    required String terminalName,
    required String msgType,
    required String msgHeader,
    required String msgBody,
    Map<String, dynamic>? msgData,
    List<String>? terminalIds,
  }) async {
    try {
      debugPrint('🚀 Terminal mesajı gönderiliyor...');
      debugPrint('📍 Terminal: $terminalName');

      // ✅ Yerel zamanı kullan (Türkiye saati - UTC+3)
      final now = DateTime.now(); // Yerel saat
      final timestamp = now.toIso8601String();
      final utcTimestamp = now.toUtc().toIso8601String();

      debugPrint('⏰ Yerel Zaman (Türkiye): $timestamp');
      debugPrint('⏰ UTC Karşılığı: $utcTimestamp');

      final payload = {
        'terminals': [
          {'name': terminalName}
        ],
        'msg_type': msgType,
        'msg_header': msgHeader,
        'msg_body': msgBody,
        'msg_data': {
          ...(msgData ?? {}),
          'timestamp': timestamp, // ✅ Yerel saat (UTC+3)
        },
      };

      debugPrint('📦 Body: ${jsonEncode(payload)}');

      final response = await http
          .post(
        Uri.parse(ApiConfig.baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${ApiConfig.bearerToken}',
        },
        body: jsonEncode(payload),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('İstek zaman aşımına uğradı (30s)');
        },
      );

      debugPrint('📨 Response Status: ${response.statusCode}');
      debugPrint('📨 Response Body: ${response.body}');

      try {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;

        if (response.statusCode == 200) {
          debugPrint('✅ Mesaj başarıyla gönderildi!');
          debugPrint(
              '📊 Terminal ID: ${responseData['data']?[0]?['terminal_id']}');
          debugPrint('📊 Mesaj ID: ${responseData['data']?[0]?['msg_id']}');
          return responseData;
        } else {
          debugPrint(
              '❌ Hata (${response.statusCode}): ${responseData['message']}');
          return null;
        }
      } catch (e) {
        debugPrint('❌ Yanıt parse hatası: $e');
        return null;
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Zaman aşımı: $e');
      return null;
    } catch (e) {
      debugPrint('❌ İstek hatası: $e');
      return null;
    }
  }

  /// Yolcu biniş bildirimi gönder
  Future<bool> sendPassengerNotification({
    required String vehicleId,
    required String stopName,
    required String routeShortName,
  }) async {
    // ✅ Yerel zamanı kullan (Türkiye saati - UTC+3)
    final now = DateTime.now(); // Yerel saat
    final timestamp = now.toIso8601String();

    debugPrint('📱 Yolcu Biniş Bildirimi Gönderiliyor');
    debugPrint('🚌 Araç: $vehicleId');
    debugPrint('📍 Durak: $stopName');
    debugPrint('🚏 Hat: $routeShortName');
    debugPrint('⏰ Yerel Zaman: $timestamp');

    final result = await sendTerminalMessage(
      terminalName: vehicleId,
      msgType: '01',
      msgHeader: 'Yolcu Biniş Bildirimi',
      msgBody:
          'Bir yolcu $stopName durağında $routeShortName numaralı hatta binmek istiyor.',
      msgData: {
        'stop_name': stopName,
        'route_number': routeShortName,
        'notification_type': 'passenger_boarding',
        'timestamp': timestamp, // ✅ Yerel saat (UTC+3)
      },
    );

    return result != null;
  }

  /// Birden fazla terminale mesaj gönder
  Future<List<Map<String, dynamic>>> sendBulkTerminalMessage({
    required List<String> terminalNames,
    required String msgType,
    required String msgHeader,
    required String msgBody,
    Map<String, dynamic>? msgData,
  }) async {
    final results = <Map<String, dynamic>>[];

    debugPrint('📢 Toplu Mesaj Gönderiliyor');
    debugPrint('📊 Terminal Sayısı: ${terminalNames.length}');

    for (final terminalName in terminalNames) {
      final result = await sendTerminalMessage(
        terminalName: terminalName,
        msgType: msgType,
        msgHeader: msgHeader,
        msgBody: msgBody,
        msgData: msgData,
      );

      if (result != null) {
        results.add(result);
        debugPrint('✅ $terminalName - Başarılı');
      } else {
        debugPrint('❌ $terminalName - Başarısız');
      }
    }

    debugPrint('📊 Başarılı: ${results.length}/${terminalNames.length}');
    return results;
  }

  /// Mesaj gönderme geçmişi (isteğe bağlı)
  Future<Map<String, dynamic>?> getMessageHistory({
    required String terminalName,
    int limit = 10,
  }) async {
    try {
      debugPrint('📜 Mesaj Geçmişi Alınıyor: $terminalName');

      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/history?terminal=$terminalName&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${ApiConfig.bearerToken}',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('İstek zaman aşımına uğradı (30s)');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Geçmiş başarıyla alındı');
        return data;
      } else {
        debugPrint('❌ Geçmiş alınamadı (${response.statusCode})');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Geçmiş alma hatası: $e');
      return null;
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
