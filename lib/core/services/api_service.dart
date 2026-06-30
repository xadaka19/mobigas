import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApiService {
  static const String _baseUrl = 'https://api.mobigas.co.ke';
  
  // SHA-256 fingerprint of api.mobigas.co.ke SSL certificate
  static const String _pinnedFingerprint =
      '41:76:69:7F:70:21:74:74:D8:B3:EC:B5:EE:98:9B:1D:F1:79:9E:BC:4C:C4:7C:DF:DE:BB:6C:84:32:4E:C1:9F';

  static Dio? _dio;

  static Dio get _client {
    if (_dio != null) return _dio!;

    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) {
        // Verify certificate fingerprint matches pinned value
        final digest = sha256.convert(cert.der);
        final fingerprint = digest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
        return fingerprint == _pinnedFingerprint;
      };
      return client;
    };

    _dio = dio;
    return dio;
  }

  static Future<String?> _getToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  static Future<Options> _options() async {
    final token = await _getToken();
    return Options(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }

  static Future<bool> sendNotification({
    required String fcmToken,
    required String title,
    required String body,
  }) async {
    try {
      final response = await _client.post(
        '/api/notifications/push',
        data: {'fcmToken': fcmToken, 'title': title, 'body': body},
        options: await _options(),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> notifyOrderDelivered(String orderId) async {
    try {
      final response = await _client.post(
        '/api/orders/delivered',
        data: {'orderId': orderId},
        options: await _options(),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
