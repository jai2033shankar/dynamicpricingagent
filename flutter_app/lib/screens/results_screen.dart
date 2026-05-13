import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../widgets/option_card.dart';
import '../widgets/glass_card.dart';
import 'booking_screen.dart';
import '../services/tts_service.dart';
import '../services/voice_service.dart';
import 'dart:async';

/// Results Screen — Shows top pricing options with explanations
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int? _expandedIndex;

  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isSubmitting = false;
  String _liveTranscript = '';
  String _voiceError = '';
  Timer? _silenceTimer;

  final VoiceService _voiceService = VoiceService();
  final TTSService _ttsService = TTSService();
  bool _hasSpoken = false;

  @override
  void initState() {
    super.initState();
    // Start monitoring the app state to know when results are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndSpeak();
      context.read<AppState>().addListener(_checkAndSpeak);
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _voiceService.stopListening();
    _ttsService.stop();
    context.read<AppState>().removeListener(_checkAndSpeak);
    super.dispose();
  }

  void _checkAndSpeak() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    
    // If it's done loading, has options, and we haven't spoken yet
    if (!state.isLoading && state.error == null && state.options.isNotEmpty && !_hasSpoken) {
      _hasSpoken = true; // prevent re-triggering
      
      setState(() { _isSpeaking = true; });
      
      // Delay to ensure the previous microphone session is fully closed by the browser.
      // Chrome sometimes interrupts SpeechSynthesis when the microphone audio stream is released.
      await Future.delayed(const Duration(milliseconds: 800));
      
      // Limit to top 2 options to prevent Web Speech API bug with long text
      int optionsToSpeak = state.options.length > 2 ? 2 : state.options.length;
      String fullExplanation = "I found ${state.options.length} options. ";
      
      for (int i = 0; i < optionsToSpeak; i++) {
        final opt = state.options[i];
        final carrier = opt['carrier'] ?? 'Unknown carrier';
        final price = opt['price']?.toString() ?? '';
        final transit = opt['transit_hours']?.toString() ?? '';
        
        fullExplanation += "Option ${i + 1} is with $carrier for $price dollars, taking $transit hours. ";
      }
      
      if (state.options.length > 2) {
        fullExplanation += "I have also displayed other options on your screen. ";
      }
      fullExplanation += "Which option would you like to book?";
      
      await _ttsService.speak(fullExplanation);
      
      if (mounted) {
        setState(() { _isSpeaking = false; });
        await _startListening();
      }
    }
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (_isListening && _liveTranscript.trim().isNotEmpty) {
        if (mounted) {
          _submitChoice(_liveTranscript.trim());
        }
      }
    });
  }

  Future<void> _startListening() async {
    setState(() {
      _liveTranscript = '';
      _voiceError = '';
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
              _submitChoice(text.trim());
            }
          });
        }
      },
      errorCallback: (error) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          // _voiceError = error; // Optional: show error to user
        });
      },
    );

    if (mounted) {
      setState(() {
        _isListening = true;
      });
    }
  }

  Future<void> _stopListening() async {
    await _voiceService.stopListening();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
      if (_liveTranscript.trim().isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _submitChoice(_liveTranscript.trim());
          }
        });
      }
    }
  }

  void _submitChoice(String choice) async {
    if (_isSubmitting) return;
    _silenceTimer?.cancel();
    if (choice.trim().isEmpty) return;
    
    setState(() { _isSubmitting = true; });

    if (_isListening) {
      await _voiceService.stopListening();
      setState(() { _isListening = false; });
    }

    final state = context.read<AppState>();
    
    // Delay to allow microphone stream to fully close
    await Future.delayed(const Duration(milliseconds: 800));
    
    // We add a brief TTS acknowledgment before processing
    await _ttsService.speak("Processing your choice...");
    
    final success = await state.processSpokenChoice(choice);
    
    if (success && mounted) {
      // The state automatically creates a booking
      if (state.lastBooking != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BookingScreen(booking: state.lastBooking!),
          ),
        );
      }
    } else if (mounted) {
      setState(() { _isSubmitting = false; });
      // If parsing failed, ask again
      await _ttsService.speak("I didn't quite catch that. Could you repeat which option you'd like to book?");
      await _startListening();
    }
  }

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
                  _buildAppBar(state),
                  Expanded(
                    child: state.isLoading
                        ? _buildLoadingState()
                        : state.error != null
                            ? _buildErrorState(state)
                            : _buildResults(state),
                  ),
                  if (!state.isLoading && state.error == null) _buildVoiceControls(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar(AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
            onPressed: () {
              state.reset();
              Navigator.pop(context);
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Pricing Options',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (state.transcript.isNotEmpty)
                  Text(
                    '"${state.transcript}"',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppTheme.accentBlue.withValues(alpha: 0.8)),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Finding best options...',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optimizing routes • Scoring carriers • Calculating prices',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(AppState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppTheme.accentRed),
            ),
            const SizedBox(height: 20),
            Text(
              'Something went wrong',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                state.reset();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(AppState state) {
    if (state.options.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Intent summary
          if (state.extractedIntent != null) _buildIntentSummary(state),
          const SizedBox(height: 8),

          // Processing time
          if (state.recommendations != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '${state.options.length} options found in ${state.recommendations!['processing_time_ms']}ms',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Option cards
          ...List.generate(state.options.length, (index) {
            final option = state.options[index];
            return AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: OptionCard(
                option: option,
                isExpanded: _expandedIndex == index,
                onTap: () {
                  setState(() {
                    _expandedIndex = _expandedIndex == index ? null : index;
                  });
                },
                onBook: () => _confirmBooking(context, state, option),
              ),
            );
          }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildIntentSummary(AppState state) {
    final intent = state.extractedIntent!['intent'];
    final origin = intent['origin']['city'] ?? '?';
    final dest = intent['destination']['city'] ?? '?';
    final cargo = intent['cargo']['type'] ?? 'general';
    final weight = intent['cargo']['weight_kg'] ?? 0;
    final priority = intent['priority'] ?? 'standard';

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.insights_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$origin → $dest',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${cargo.toUpperCase()} • ${weight}kg • ${priority.toUpperCase()}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(state.extractedIntent!['confidence'] * 100).toInt()}% match',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.accentGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'No options found',
        style: GoogleFonts.inter(color: AppTheme.textMuted),
      ),
    );
  }

  void _confirmBooking(
      BuildContext context, AppState state, Map<String, dynamic> option) async {
    await state.confirmBooking(option);

    if (state.lastBooking != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookingScreen(booking: state.lastBooking!),
        ),
      );
    }
  }
  Widget _buildVoiceControls() {
    return Container(
      padding: const EdgeInsets.only(bottom: 30, top: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppTheme.surfaceDark.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        children: [
          // Transcript Area
          if (_isListening || _isSpeaking)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.cardDark.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isSpeaking 
                      ? AppTheme.accentCyan.withValues(alpha: 0.3)
                      : AppTheme.accentBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isListening)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppTheme.accentBlue),
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      _isSpeaking 
                        ? 'Speaking...' 
                        : _liveTranscript.isNotEmpty ? _liveTranscript : 'Listening...',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontStyle: _liveTranscript.isEmpty && !_isSpeaking ? FontStyle.italic : FontStyle.normal,
                        color: _isSpeaking ? AppTheme.accentCyan : AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
          // Mic Button
          GestureDetector(
            onTap: () {
              if (_isSpeaking) {
                _ttsService.stop();
                setState(() { _isSpeaking = false; });
                _startListening();
              } else if (_isListening) {
                _stopListening();
              } else {
                _startListening();
              }
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _isSpeaking
                    ? AppTheme.purpleGradient
                    : _isListening
                        ? const LinearGradient(colors: [Color(0xFFE040FB), Color(0xFFD500F9)])
                        : AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: (_isSpeaking ? AppTheme.accentCyan : AppTheme.accentBlue).withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _isSpeaking ? Icons.skip_next_rounded : _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isSpeaking ? 'Tap to skip' : _isListening ? 'Listening...' : 'Tap to speak',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
