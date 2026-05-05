import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// Voice Service — Handles speech recognition using the Web Speech API (Chrome)
/// or platform-native speech recognizers (iOS/Android).
///
/// This service manages:
/// - Microphone permission requests
/// - Speech recognition lifecycle (init → listen → stop)
/// - Real-time partial and final transcription callbacks
class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;
  bool _isAvailable = false;
  bool _isListening = false;

  bool get isInitialized => _isInitialized;
  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  String _lastError = '';
  String get lastError => _lastError;

  // Callbacks
  Function(String text, bool isFinal)? onResult;
  Function(bool isListening)? onListeningStateChanged;
  Function(String error)? onError;

  /// Initialize the speech recognition engine.
  /// Must be called before [startListening].
  /// Returns true if speech recognition is available on this device/browser.
  Future<bool> initialize() async {
    if (_isInitialized) return _isAvailable;

    try {
      _isAvailable = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: kDebugMode,
      );
      _isInitialized = true;

      if (kDebugMode) {
        if (_isAvailable) {
          final locales = await _speech.locales();
          debugPrint('🎤 Speech recognition initialized. '
              'Available locales: ${locales.length}');
        } else {
          debugPrint('🎤 Speech recognition NOT available on this device/browser');
        }
      }
    } catch (e) {
      _lastError = 'Failed to initialize speech recognition: $e';
      _isAvailable = false;
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('🎤 Init error: $e');
      }
    }

    return _isAvailable;
  }

  /// Start listening for speech input.
  /// The browser will automatically prompt for microphone permission on first use.
  /// [onResult] callback receives partial and final transcription results.
  Future<void> startListening({
    Function(String text, bool isFinal)? resultCallback,
    Function(String error)? errorCallback,
    String localeId = 'en_US',
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_isAvailable) {
      final msg = 'Speech recognition is not available. '
          'Please ensure microphone access is granted and you are using a supported browser (Chrome).';
      _lastError = msg;
      errorCallback?.call(msg);
      onError?.call(msg);
      return;
    }

    if (_isListening) {
      await stopListening();
    }

    if (resultCallback != null) {
      onResult = resultCallback;
    }
    if (errorCallback != null) {
      onError = errorCallback;
    }

    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.dictation,
        ),
      );

      _isListening = true;
      onListeningStateChanged?.call(true);

      if (kDebugMode) {
        debugPrint('🎤 Started listening...');
      }
    } catch (e) {
      _lastError = 'Failed to start listening: $e';
      onError?.call(_lastError);
      if (kDebugMode) {
        debugPrint('🎤 Listen error: $e');
      }
    }
  }

  /// Stop listening and finalize the last result.
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _speech.stop();
      _isListening = false;
      onListeningStateChanged?.call(false);

      if (kDebugMode) {
        debugPrint('🎤 Stopped listening');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🎤 Stop error: $e');
      }
    }
  }

  /// Cancel the current listening session without processing results.
  Future<void> cancelListening() async {
    if (!_isListening) return;

    try {
      await _speech.cancel();
      _isListening = false;
      onListeningStateChanged?.call(false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🎤 Cancel error: $e');
      }
    }
  }

  // ─── Internal callbacks ───────────────────────────────────────────

  void _onSpeechResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords;
    final isFinal = result.finalResult;

    if (kDebugMode) {
      debugPrint('🎤 ${isFinal ? "FINAL" : "partial"}: "$text" '
          '(confidence: ${result.confidence.toStringAsFixed(2)})');
    }

    onResult?.call(text, isFinal);
  }

  void _onStatus(String status) {
    if (kDebugMode) {
      debugPrint('🎤 Status: $status');
    }

    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      onListeningStateChanged?.call(false);
    }
  }

  void _onError(SpeechRecognitionError error) {
    _lastError = error.errorMsg;
    _isListening = false;
    onListeningStateChanged?.call(false);

    if (kDebugMode) {
      debugPrint('🎤 Error: ${error.errorMsg} (permanent: ${error.permanent})');
    }

    onError?.call(error.errorMsg);
  }

  /// Dispose and clean up resources.
  void dispose() {
    if (_isListening) {
      _speech.cancel();
    }
    _isInitialized = false;
    _isAvailable = false;
    _isListening = false;
  }
}
