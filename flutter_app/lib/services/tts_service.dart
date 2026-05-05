import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

/// Text-to-Speech Service
///
/// Handles speaking text out loud using the platform's native TTS engine.
/// Provides callbacks for state changes (speaking, stopped, etc.).
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _flutterTts = FlutterTts();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  // Callbacks
  Function(bool isSpeaking)? onStateChanged;

  Completer<void>? _speechCompleter;

  Map<String, String>? _currentVoice;

  /// Initialize TTS settings
  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        // Web specific initialization
      } else {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers
          ],
        );
      }

      await _flutterTts.setLanguage("en-US");
      await _findAndSetFemaleVoice();

      await _flutterTts.setSpeechRate(kIsWeb ? 0.9 : 0.5); 
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.3); // Higher pitch helps force a more feminine sound on fallback

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        onStateChanged?.call(true);
        if (kDebugMode) debugPrint("🗣️ TTS Started speaking");
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        onStateChanged?.call(false);
        if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
          _speechCompleter!.complete();
        }
        if (kDebugMode) debugPrint("🗣️ TTS Completed speaking");
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        onStateChanged?.call(false);
        if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
          _speechCompleter!.complete();
        }
        if (kDebugMode) debugPrint("🗣️ TTS Cancelled speaking");
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        onStateChanged?.call(false);
        if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
          _speechCompleter!.complete();
        }
        if (kDebugMode) debugPrint("🗣️ TTS Error: $msg");
      });

    } catch (e) {
      if (kDebugMode) debugPrint("🗣️ TTS Init Error: $e");
    }
  }

  Future<void> _findAndSetFemaleVoice() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        final List<dynamic> voiceList = voices.toList();
        
        // Priority list for female voices across platforms
        final preferredNames = [
          'samantha', 'victoria', 'karen', 'zira', 'microsoft zira', 
          'google us english', 'female', 'fiona', 'moira', 'veena',
          'en-us-x-sfg#female_1-local'
        ];
        
        for (final pref in preferredNames) {
          final matches = voiceList.where((v) {
            final name = v['name']?.toString().toLowerCase() ?? '';
            final locale = v['locale']?.toString().toLowerCase() ?? '';
            return name.contains(pref) && (locale.contains('en-us') || locale.contains('en-gb') || locale.contains('en-au'));
          }).toList();
          
          if (matches.isNotEmpty) {
            _currentVoice = Map<String, String>.from(matches.first);
            if (kDebugMode) debugPrint("🗣️ TTS Selected Female Voice: $_currentVoice");
            break;
          }
        }
        
        if (_currentVoice != null) {
          await _flutterTts.setVoice({
            "name": _currentVoice!["name"]!, 
            "locale": _currentVoice!["locale"]!
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("🗣️ TTS Voice Selection Error: $e");
    }
  }

  /// Speak the provided text
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    
    // Stop any ongoing speech before starting new one
    if (_isSpeaking) {
      await stop();
    }

    // Try to re-confirm voice selection in case it was initialized too early (web)
    if (_currentVoice == null) {
      await _findAndSetFemaleVoice();
    }

    _speechCompleter = Completer<void>();

    try {
      if (_currentVoice != null) {
        await _flutterTts.setVoice({
          "name": _currentVoice!["name"]!, 
          "locale": _currentVoice!["locale"]!
        });
      }
      
      // Re-apply pitch to ensure consistency
      await _flutterTts.setPitch(1.3);
      
      await _flutterTts.speak(text);
      // Wait for completion handler to fire
      await _speechCompleter?.future;
    } catch (e) {
      if (kDebugMode) debugPrint("🗣️ TTS Speak Error: $e");
      if (_speechCompleter != null && !_speechCompleter!.isCompleted) {
         _speechCompleter!.complete();
      }
    } finally {
      _speechCompleter = null;
    }
  }

  /// Stop currently speaking text
  Future<void> stop() async {
    if (!_isSpeaking) return;
    
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
      onStateChanged?.call(false);
    } catch (e) {
      if (kDebugMode) debugPrint("🗣️ TTS Stop Error: $e");
    }
  }
}
