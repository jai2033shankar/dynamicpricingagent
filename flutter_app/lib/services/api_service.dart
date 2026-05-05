import 'dart:convert';
import 'package:http/http.dart' as http;

/// API Service — communicates with the DynamicPricingEngine backend
class ApiService {
  static const String baseUrl = 'http://localhost:8000';

  // ─── Health Check ──────────────────────────────────────────────────
  static Future<bool> healthCheck() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ─── Intent Extraction ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> extractIntent(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/intent/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Intent extraction failed: ${response.body}');
  }

  // ─── Get Recommendations ───────────────────────────────────────────
  static Future<Map<String, dynamic>> getRecommendations({
    required String originCity,
    required String destCity,
    double originLat = 0,
    double originLng = 0,
    double destLat = 0,
    double destLng = 0,
    String cargoType = 'general',
    double weightKg = 1000,
    double volumeCbm = 5,
    String priority = 'standard',
    double? maxPrice,
    int maxOptions = 3,
  }) async {
    final body = {
      'origin': {'lat': originLat, 'lng': originLng, 'city': originCity},
      'destination': {'lat': destLat, 'lng': destLng, 'city': destCity},
      'cargo': {'type': cargoType, 'weight_kg': weightKg, 'volume_cbm': volumeCbm},
      'priority': priority,
      'constraints': {
        if (maxPrice != null) 'max_price': maxPrice,
      },
      'max_options': maxOptions,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/recommendations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Recommendations failed: ${response.body}');
  }

  // ─── Confirm Booking ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> confirmBooking({
    required String optionId,
    required String carrier,
    required String carrierId,
    required List<String> route,
    required double price,
    required double etaHours,
    String? customerName,
    String? customerEmail,
  }) async {
    final body = {
      'option_id': optionId,
      'carrier': carrier,
      'carrier_id': carrierId,
      'route': route,
      'price': price,
      'eta_hours': etaHours,
      if (customerName != null) 'customer_name': customerName,
      if (customerEmail != null) 'customer_email': customerEmail,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/booking/confirm'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Booking failed: ${response.body}');
  }

  // ─── Get Routes ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> optimizeRoute({
    required String origin,
    required String destination,
    String optimizeFor = 'balanced',
    int maxResults = 3,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/route/optimize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'origin': origin,
        'destination': destination,
        'optimize_for': optimizeFor,
        'max_results': maxResults,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Route optimization failed: ${response.body}');
  }

  // ─── Get Available Cities ──────────────────────────────────────────
  static Future<List<String>> getCities() async {
    final response = await http.get(Uri.parse('$baseUrl/cities'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['cities']);
    }
    throw Exception('Failed to fetch cities');
  }

  // ─── Get Bookings ─────────────────────────────────────────────────
  static Future<List<dynamic>> getBookings() async {
    final response = await http.get(Uri.parse('$baseUrl/bookings'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['bookings'];
    }
    throw Exception('Failed to fetch bookings');
  }
}
