import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl = 'https://api.mobigas.co.ke';

  // Get Firebase ID token for authenticated requests
  static Future<String?> _getToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Send push notification via backend
  static Future<bool> sendNotification({
    required String fcmToken,
    required String title,
    required String body,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/notifications/push'),
        headers: await _headers(),
        body: jsonEncode({
          'fcmToken': fcmToken,
          'title': title,
          'body': body,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Notify backend when order is delivered
  static Future<bool> notifyOrderDelivered(String orderId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/orders/delivered'),
        headers: await _headers(),
        body: jsonEncode({'orderId': orderId}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
