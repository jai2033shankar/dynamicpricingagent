import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/tts_service.dart';

/// App-wide state management using ChangeNotifier + Provider
class AppState extends ChangeNotifier {
  // ─── Connection state ─────────────────────────────────────────────
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // ─── Voice state ──────────────────────────────────────────────────
  bool _isListening = false;
  bool get isListening => _isListening;

  String _transcript = '';
  String get transcript => _transcript;

  // ─── TTS state ────────────────────────────────────────────────────
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  final TTSService _ttsService = TTSService();

  // ─── Intent state ─────────────────────────────────────────────────
  Map<String, dynamic>? _extractedIntent;
  Map<String, dynamic>? get extractedIntent => _extractedIntent;

  // ─── Recommendations state ────────────────────────────────────────
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Map<String, dynamic>? _recommendations;
  Map<String, dynamic>? get recommendations => _recommendations;

  List<dynamic> get options => _recommendations?['options'] ?? [];

  // ─── Booking state ────────────────────────────────────────────────
  Map<String, dynamic>? _lastBooking;
  Map<String, dynamic>? get lastBooking => _lastBooking;

  List<dynamic> _bookingHistory = [];
  List<dynamic> get bookingHistory => _bookingHistory;

  // ─── Error state ──────────────────────────────────────────────────
  String? _error;
  String? get error => _error;

  // ─── Actions ──────────────────────────────────────────────────────

  Future<void> checkConnection() async {
    _isConnected = await ApiService.healthCheck();
    
    // Initialize TTS
    await _ttsService.initialize();
    _ttsService.onStateChanged = (speaking) {
      _isSpeaking = speaking;
      notifyListeners();
    };
    
    notifyListeners();
  }

  Future<void> stopTTS() async {
    await _ttsService.stop();
  }

  void setListening(bool value) {
    _isListening = value;
    notifyListeners();
  }

  void setTranscript(String value) {
    _transcript = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Extract intent from text query
  Future<void> extractIntent(String text) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _extractedIntent = await ApiService.extractIntent(text);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Get recommendations from text query (intent extraction + recommendation in one flow)
  Future<void> getRecommendationsFromText(String text) async {
    _isLoading = true;
    _error = null;
    _recommendations = null;
    notifyListeners();

    try {
      // Step 1: Extract intent
      final intentResult = await ApiService.extractIntent(text);
      _extractedIntent = intentResult;
      notifyListeners();

      final intent = intentResult['intent'];
      final origin = intent['origin'];
      final destination = intent['destination'];

      if (origin['city'].isEmpty || destination['city'].isEmpty) {
        _error = 'Could not extract origin and destination from your query. Please try again with city names.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Step 2: Get recommendations
      _recommendations = await ApiService.getRecommendations(
        originCity: origin['city'],
        destCity: destination['city'],
        originLat: (origin['lat'] as num).toDouble(),
        originLng: (origin['lng'] as num).toDouble(),
        destLat: (destination['lat'] as num).toDouble(),
        destLng: (destination['lng'] as num).toDouble(),
        cargoType: intent['cargo']['type'] ?? 'general',
        weightKg: (intent['cargo']['weight_kg'] as num).toDouble(),
        volumeCbm: (intent['cargo']['volume_cbm'] as num).toDouble(),
        priority: intent['priority'] ?? 'standard',
        maxPrice: intent['constraints']?['max_price']?.toDouble(),
      );

      _isLoading = false;
      notifyListeners();

      // TTS call removed - moved to UI layer for conversational control
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Process the user's spoken choice and confirm the booking
  Future<bool> processSpokenChoice(String transcript) async {
    if (options.isEmpty) return false;

    final lowerTranscript = transcript.toLowerCase();
    Map<String, dynamic>? selectedOption;

    // 1. Check for superlatives or ranked matches
    if (lowerTranscript.contains('first') || lowerTranscript.contains('one') || lowerTranscript.contains('top')) {
      selectedOption = options[0];
    } else if (lowerTranscript.contains('second') || lowerTranscript.contains('two')) {
      if (options.length > 1) selectedOption = options[1];
    } else if (lowerTranscript.contains('third') || lowerTranscript.contains('three')) {
      if (options.length > 2) selectedOption = options[2];
    } else if (lowerTranscript.contains('fast') || lowerTranscript.contains('quick') || lowerTranscript.contains('speed')) {
      // Find the fastest option
      selectedOption = options.reduce((a, b) => 
        (a['transit_hours'] ?? 999) < (b['transit_hours'] ?? 999) ? a : b);
    } else if (lowerTranscript.contains('cheap') || lowerTranscript.contains('budget') || lowerTranscript.contains('lowest')) {
      // Find the cheapest option
      selectedOption = options.reduce((a, b) => 
        (a['price'] ?? 999999) < (b['price'] ?? 999999) ? a : b);
    } else if (lowerTranscript.contains('reliab') || lowerTranscript.contains('safe') || lowerTranscript.contains('best')) {
      // Find the most reliable option, or default to the top option
      selectedOption = options[0];
    } else {
      // 2. Check for carrier names
      for (final option in options) {
        final carrierName = option['carrier']?.toString().toLowerCase() ?? '';
        // split carrier name into words and see if any match the transcript
        final words = carrierName.split(' ');
        for (final word in words) {
          if (word.length > 3 && lowerTranscript.contains(word)) {
            selectedOption = option;
            break;
          }
        }
        if (selectedOption != null) break;
      }
    }

    if (selectedOption == null) {
      // If we couldn't confidently parse it, we default to the top option or return false to ask again.
      // For a smooth demo, let's default to the top option if they say "book it" or similar.
      if (lowerTranscript.contains('book') || lowerTranscript.contains('yes') || lowerTranscript.contains('proceed')) {
        selectedOption = options[0];
      } else {
        return false;
      }
    }

    // Confirm booking
    if (selectedOption != null) {
      await confirmBooking(selectedOption);
      return true;
    }
    return false;
  }

  /// Confirm a booking
  Future<void> confirmBooking(Map<String, dynamic> option) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _lastBooking = await ApiService.confirmBooking(
        optionId: option['option_id'],
        carrier: option['carrier'],
        carrierId: option['carrier_id'],
        route: List<String>.from(option['route']),
        price: (option['price'] as num).toDouble(),
        etaHours: (option['eta_hours'] as num).toDouble(),
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load booking history
  Future<void> loadBookings() async {
    try {
      _bookingHistory = await ApiService.getBookings();
      notifyListeners();
    } catch (_) {}
  }

  /// Reset to initial state
  void reset() {
    _isListening = false;
    _transcript = '';
    _extractedIntent = null;
    _recommendations = null;
    _lastBooking = null;
    _error = null;
    _isLoading = false;
    _ttsService.stop();
    notifyListeners();
  }
}
