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
///
/// The mic button toggles speech recognition:
/// - Single tap: start/stop listening (toggle mode)
/// - Speech is recognized in real-time and shown on screen
/// - When speech ends (pause detected) or user taps stop, the query is submitted
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
  String _liveTranscript = '';
  String _voiceError = '';
  bool _voiceAvailable = false;
  bool _voiceInitialized = false;
  bool _hasGreeted = false;
  Timer? _silenceTimer;

  final VoiceService _voiceService = VoiceService();

  final List<String> _suggestions = [
    'Ship 2 tons of electronics from Mumbai to Delhi urgently',
    'Cheapest way to send FMCG goods Bangalore to Chennai',
    'Express delivery 500kg pharmaceuticals Hyderabad to Kolkata',
    'Move 1.5 tons of textiles from Ahmedabad to Pune',
    'Ship perishable goods from Kochi to Mumbai under ₹40000',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Check backend connection
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

      // Automatically greet the user with the female voice
      if (!_hasGreeted) {
        _hasGreeted = true;
        _speakAndListen();
      }
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
    final state = context.read<AppState>();
    
    // Stop TTSService if it is speaking
    if (state.isSpeaking) {
      await state.stopTTS(); // We need to add stopTTS to AppState or use TTSService directly
      return;
    }

    if (_isListening) {
      await _stopListening();
    } else {
      if (!_hasGreeted) {
        await _speakAndListen();
      } else {
        await _startListening();
      }
    }
  }

  Future<void> _speakAndListen() async {
    final state = context.read<AppState>();
    _hasGreeted = true;
    
    setState(() {
      _showTextField = false;
      _voiceError = '';
    });

    // We can access TTSService directly or through state, but AppState is simpler.
    // Let's use TTSService directly for now to be clear, or add a helper to AppState.
    // Actually, TTSService is a singleton.
    final tts = TTSService();
    
    // Listen to state changes to know when it finishes
    bool finishedSpeaking = false;
    
    // We can just await the speak call, but flutter_tts speak() completes when it *starts* or *finishes* depending on platform.
    // Usually it completes when finished speaking.
    // We'll also start the visual pulse for speaking.
    
    await tts.speak("Hello! I am your logistics assistant. I can help you find the best shipping rates and book your cargo. For example, you can say: Ship 2 tons of electronics from Mumbai to Delhi, or ask for the cheapest way to send goods from Bangalore to Chennai. How can I help you today?");
    
    // Ensure we are mounted
    if (!mounted) return;
    
    // Start listening right after
    if (state.isSpeaking) {
        // Wait until it finishes speaking
        // This is a bit tricky, better to just wait a bit or use the callback.
        // Let's simplify and just start listening after a small delay.
        // Actually flutter_tts await speak() waits for the TTS to complete on iOS/Android, but on Web it might be different.
    }
    
    // Web speech API usually finishes the await when it stops speaking.
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _liveTranscript = '';
      _voiceError = '';
      _showTextField = false; // Hide text field when using voice
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

        // When speech recognition produces a final result, auto-submit
        if (isFinal && text.trim().isNotEmpty) {
          _silenceTimer?.cancel();
          // Small delay so user can see the final transcript
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

      // If we have accumulated text, submit it
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
      return 'Microphone access denied. Please allow microphone access in your browser settings and reload.';
    }
    if (error.contains('no-speech')) {
      return 'No speech detected. Please try again and speak clearly.';
    }
    if (error.contains('network')) {
      return 'Network error. Speech recognition requires an internet connection.';
    }
    if (error.contains('aborted')) {
      return ''; // User cancelled, not a real error
    }
    return 'Speech recognition error: $error';
  }

  // ─── Submit query ──────────────────────────────────────────────────

  void _submitQuery(String query) async {
    if (_isSubmitting) return;
    _silenceTimer?.cancel();
    if (query.trim().isEmpty) return;
    
    setState(() { _isSubmitting = true; });

    // Stop listening if still active
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() {
        _isListening = false;
      });
      context.read<AppState>().setListening(false);
    }

    final state = context.read<AppState>();
    state.setTranscript(query);

    // Navigate to results
    if (mounted) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (ctx, anim1, anim2) => const ResultsScreen(),
          transitionsBuilder: (ctx, anim, anim2, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      ).then((_) {
        // Reset when user returns to this screen
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

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(state),
                  const Spacer(flex: 1),
                  _buildTitle(),
                  const SizedBox(height: 24),
                  if (state.isSpeaking) ...[
                    // Add speaking indicator
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
                  // Live transcript display
                  if ((_liveTranscript.isNotEmpty || _isListening) && !state.isSpeaking)
                    _buildLiveTranscript(),
                  const SizedBox(height: 16),
                  _buildMicButton(state),
                  const SizedBox(height: 8),
                  // Voice error message
                  if (_voiceError.isNotEmpty) _buildVoiceError(),
                  const SizedBox(height: 16),
                  if (_showTextField) _buildTextInput(),
                  const Spacer(flex: 1),
                  _buildSuggestions(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Logo / Brand
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
          // Voice availability indicator
          if (_voiceInitialized)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (_voiceAvailable ? AppTheme.accentCyan : AppTheme.accentAmber)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _voiceAvailable ? Icons.mic_rounded : Icons.mic_off_rounded,
                    size: 12,
                    color: _voiceAvailable ? AppTheme.accentCyan : AppTheme.accentAmber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _voiceAvailable ? 'Voice On' : 'Voice Off',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: _voiceAvailable ? AppTheme.accentCyan : AppTheme.accentAmber,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 6),
          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (state.isConnected ? AppTheme.accentGreen : AppTheme.accentRed)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: state.isConnected ? AppTheme.accentGreen : AppTheme.accentRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  state.isConnected ? 'Connected' : 'Offline',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: state.isConnected ? AppTheme.accentGreen : AppTheme.accentRed,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // History button
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppTheme.textSecondary),
            onPressed: () {
              // TODO: Navigate to history
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
            child: Text(
              'Where are you\nshipping today?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Speak or type your shipment details for\ninstant AI-powered pricing',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Container(
          key: ValueKey(_liveTranscript),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isListening
                  ? AppTheme.accentPurple.withValues(alpha: 0.3)
                  : AppTheme.accentBlue.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              if (_isListening)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AppTheme.accentPurple.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  _liveTranscript.isEmpty ? 'Listening...' : _liveTranscript,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: _liveTranscript.isEmpty
                        ? AppTheme.textMuted
                        : AppTheme.textPrimary,
                    fontStyle: _liveTranscript.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceError() {
    if (_voiceError.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.accentRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.accentAmber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _voiceError,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.accentAmber,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _voiceError = ''),
              child: Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton(AppState state) {
    return Column(
      children: [
        // Mic button
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulseScale = _isListening
                ? 0.6 + _pulseController.value * 0.4
                : 0.5 + _pulseController.value * 0.5;

            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? AppTheme.accentPurple : AppTheme.accentBlue)
                        .withValues(alpha: 0.3 * pulseScale),
                    blurRadius: _isListening ? 40 + _pulseController.value * 25 : 30 + _pulseController.value * 20,
                    spreadRadius: _isListening ? _pulseController.value * 10 : _pulseController.value * 5,
                  ),
                ],
              ),
              child: GestureDetector(
                onTap: _voiceAvailable ? _toggleListening : () {
                  setState(() {
                    _showTextField = !_showTextField;
                    if (!_voiceAvailable) {
                      _voiceError = 'Voice input is not available in this browser. Please use Chrome or type your query below.';
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isListening ? 80 : 72,
                  height: _isListening ? 80 : 72,
                  decoration: BoxDecoration(
                    gradient: _isListening
                        ? AppTheme.purpleGradient
                        : AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: _isListening ? 0.3 : 0.2),
                      width: _isListening ? 3 : 2,
                    ),
                  ),
                  child: Icon(
                    state.isSpeaking ? Icons.stop_rounded :
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: (_isListening || state.isSpeaking) ? 36 : 32,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // Status text
        Text(
          state.isSpeaking
              ? 'Speaking... tap to interrupt'
              : _isListening
                  ? 'Listening... tap to stop'
                  : _showTextField
                      ? 'Type your query below'
                      : _voiceAvailable
                          ? 'Tap to speak'
                          : 'Voice unavailable — tap to type',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: state.isSpeaking ? AppTheme.accentCyan : _isListening ? AppTheme.accentPurple : AppTheme.textMuted,
            fontWeight: (state.isSpeaking || _isListening) ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        // Keyboard toggle (when voice is available)
        if (!_isListening)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showTextField = !_showTextField;
                _voiceError = '';
              });
            },
            icon: Icon(
              _showTextField ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
              size: 16,
              color: AppTheme.textMuted,
            ),
            label: Text(
              _showTextField ? 'Hide keyboard' : 'Type instead',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: _textController,
        autofocus: true,
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'e.g., Ship electronics from Mumbai to Delhi...',
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
          suffixIcon: IconButton(
            icon: const Icon(Icons.send_rounded, color: AppTheme.accentBlue),
            onPressed: () => _submitQuery(_textController.text),
          ),
        ),
        onSubmitted: _submitQuery,
        textInputAction: TextInputAction.send,
      ),
    );
  }

  Widget _buildSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Try saying...',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _suggestions.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _submitQuery(_suggestions[index]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      _suggestions[index],
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
