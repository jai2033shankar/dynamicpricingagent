import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/voice_service.dart';
import '../services/tts_service.dart';
import '../widgets/waveform_visualizer.dart';
import 'results_screen.dart';

/// Voice Home Screen — Main entry point with floating mic, waveform, and suggestion chips.
class VoiceHomeScreen extends StatefulWidget {
  const VoiceHomeScreen({super.key});

  @override
  State<VoiceHomeScreen> createState() => _VoiceHomeScreenState();
}

class _VoiceHomeScreenState extends State<VoiceHomeScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  late AnimationController _pulseController;

  bool _showTextField = false;
  bool _isListening = false;
  bool _isSubmitting = false;
  bool _isActivated = false; // Track if user has activated the session
  String _liveTranscript = '';
  String _voiceError = '';
  bool _voiceAvailable = false;
  bool _voiceInitialized = false;
  bool _hasGreeted = false;
  Timer? _silenceTimer;

  final VoiceService _voiceService = VoiceService();

  final List<String> _suggestions = [
    'Ship 2 tons of electronics from New York to Los Angeles urgently',
    'Cheapest way to send FMCG goods Dallas to Houston',
    'Express delivery 500kg pharmaceuticals Austin to Miami',
    'Move 1.5 tons of textiles from Boston to Philadelphia',
    'Ship perishable goods from San Diego to New York under \$400',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Check backend connection but don't auto-greet yet (blocked by browsers)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().checkConnection();
      _initVoice();
    });
  }

  Future<void> _initVoice() async {
    final available = await _voiceService.initialize();
    
    // Also ensure TTS is ready
    final tts = TTSService();
    await tts.initialize();

    if (mounted) {
      setState(() {
        _voiceAvailable = available;
        _voiceInitialized = true;
      });
    }
  }

  Future<void> _activateAssistant() async {
    setState(() {
      _isActivated = true;
    });
    
    // Now that we have user interaction, we can speak and listen
    if (!_hasGreeted) {
      _hasGreeted = true;
      await _speakAndListen();
    }
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _pulseController.dispose();
    _textController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (_isListening && _liveTranscript.trim().isNotEmpty) {
        if (mounted) {
          _submitQuery(_liveTranscript.trim());
        }
      }
    });
  }

  // ─── Voice actions ─────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    if (!_isActivated) {
      await _activateAssistant();
      return;
    }

    final state = context.read<AppState>();
    
    if (state.isSpeaking) {
      await state.stopTTS();
      return;
    }

    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _speakAndListen() async {
    final state = context.read<AppState>();
    _hasGreeted = true;
    
    setState(() {
      _showTextField = false;
      _voiceError = '';
    });

    final tts = TTSService();
    
    // Await greeting completion
    await tts.speak("Hello! I am your logistics assistant. I can help you find the best shipping rates and book your cargo. For example, you can say: Ship 2 tons of electronics from New York to Los Angeles. How can I help you today?");
    
    if (!mounted) return;
    
    // Start listening right after
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _liveTranscript = '';
      _voiceError = '';
      _showTextField = false;
    });

    await _voiceService.startListening(
      resultCallback: (text, isFinal) {
        if (!mounted) return;

        setState(() {
          _liveTranscript = text;
        });

        if (text.trim().isNotEmpty) {
          _resetSilenceTimer();
        }

        if (isFinal && text.trim().isNotEmpty) {
          _silenceTimer?.cancel();
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && text.trim().isNotEmpty) {
              _submitQuery(text.trim());
            }
          });
        }
      },
      errorCallback: (error) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          _voiceError = _friendlyError(error);
        });
        context.read<AppState>().setListening(false);
      },
    );

    if (mounted) {
      setState(() {
        _isListening = true;
      });
      context.read<AppState>().setListening(true);
    }
  }

  Future<void> _stopListening() async {
    await _voiceService.stopListening();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
      context.read<AppState>().setListening(false);

      if (_liveTranscript.trim().isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _submitQuery(_liveTranscript.trim());
          }
        });
      }
    }
  }

  String _friendlyError(String error) {
    if (error.contains('not-allowed') || error.contains('permission')) {
      return 'Microphone access denied. Please allow microphone access in your browser settings.';
    }
    if (error.contains('no-speech')) {
      return 'No speech detected. Please try again.';
    }
    return 'Speech error: $error';
  }

  void _submitQuery(String query) async {
    if (_isSubmitting) return;
    _silenceTimer?.cancel();
    if (query.trim().isEmpty) return;
    
    // Stop any ongoing greeting TTS
    final tts = TTSService();
    await tts.stop();

    setState(() { _isSubmitting = true; });

    if (_isListening) {
      await _voiceService.stopListening();
      setState(() { _isListening = false; });
      context.read<AppState>().setListening(false);
    }

    final state = context.read<AppState>();
    state.setTranscript(query);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (ctx) => const ResultsScreen()),
      ).then((_) {
        if (mounted) {
          setState(() {
            _liveTranscript = '';
            _textController.clear();
            _isSubmitting = false;
          });
        }
      });
    }

    await state.getRecommendationsFromText(query);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
            child: Stack(
              children: [
                SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(state),
                      const Spacer(flex: 1),
                      _buildTitle(),
                      const SizedBox(height: 24),
                      if (state.isSpeaking) ...[
                        Icon(Icons.volume_up_rounded, color: AppTheme.accentCyan, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          "Speaking...",
                          style: GoogleFonts.inter(color: AppTheme.accentCyan, fontWeight: FontWeight.w500),
                        ),
                      ] else ...[
                        _buildWaveform(state),
                      ],
                      const SizedBox(height: 8),
                      if ((_liveTranscript.isNotEmpty || _isListening) && !state.isSpeaking)
                        _buildLiveTranscript(),
                      const SizedBox(height: 16),
                      _buildMicButton(state),
                      const SizedBox(height: 8),
                      if (_voiceError.isNotEmpty) _buildVoiceError(),
                      const SizedBox(height: 16),
                      if (_showTextField) _buildTextInput(),
                      const Spacer(flex: 1),
                      _buildSuggestions(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // Activation Overlay
                if (!_isActivated) _buildActivationOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivationOverlay() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentBlue.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 64),
            ),
            const SizedBox(height: 32),
            Text(
              "LogiPrice Assistant",
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Ready to help with your shipping needs.",
              style: GoogleFonts.inter(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _activateAssistant,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: Text(
                "Start Assistant",
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            'LogiPrice',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (state.isConnected) 
            const Icon(Icons.cloud_done_rounded, color: AppTheme.accentGreen, size: 18),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Where are you\nshipping today?',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform(AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: WaveformVisualizer(
        isActive: _isListening,
        height: 70,
      ),
    );
  }

  Widget _buildLiveTranscript() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.3)),
        ),
        child: Text(
          _liveTranscript.isEmpty ? 'Listening...' : _liveTranscript,
          style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildVoiceError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        _voiceError,
        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.accentAmber),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMicButton(AppState state) {
    return GestureDetector(
      onTap: _toggleListening,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: _isListening ? AppTheme.purpleGradient : AppTheme.primaryGradient,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isListening ? Icons.stop_rounded : Icons.mic_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: _textController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Type your query...',
          suffixIcon: IconButton(
            icon: const Icon(Icons.send_rounded, color: AppTheme.accentBlue),
            onPressed: () => _submitQuery(_textController.text),
          ),
        ),
        onSubmitted: _submitQuery,
      ),
    );
  }

  Widget _buildSuggestions() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(_suggestions[index]),
              onPressed: () => _submitQuery(_suggestions[index]),
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}
