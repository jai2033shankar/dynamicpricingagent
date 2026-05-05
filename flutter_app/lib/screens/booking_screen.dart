import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../services/tts_service.dart';

/// Booking Confirmation Screen — Shows booking confirmation with tracking ID
class BookingScreen extends StatefulWidget {
  final Map<String, dynamic> booking;

  const BookingScreen({super.key, required this.booking});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final TTSService _ttsService = TTSService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confirmAndNotify();
    });
  }

  void _confirmAndNotify() async {
    final carrier = widget.booking['carrier'] ?? 'your selected carrier';
    
    // Show simulated email notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.mark_email_read_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Email sent successfully', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  Text('Booking Confirmation & Tracking ID have been emailed.', style: GoogleFonts.inter(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );

    // Speak confirmation
    await _ttsService.speak(
      "Booking confirmed! Your shipment with $carrier is scheduled. I have sent the tracking details to your email."
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Success animation area
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      // Success icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.accentGreen, Color(0xFF059669)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentGreen.withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Booking Confirmed!',
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your shipment has been booked successfully',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Booking details card
                      GlassCard(
                        showGlow: true,
                        glowColor: AppTheme.accentGreen,
                        child: Column(
                          children: [
                            _buildDetailRow('Booking ID', widget.booking['booking_id'] ?? ''),
                            _buildDivider(),
                            _buildDetailRow('Tracking ID', widget.booking['tracking_id'] ?? '', highlight: true),
                            _buildDivider(),
                            _buildDetailRow('Carrier', widget.booking['carrier'] ?? ''),
                            _buildDivider(),
                            _buildDetailRow('Route', (widget.booking['route'] as List?)?.join(' → ') ?? ''),
                            _buildDivider(),
                            _buildDetailRow(
                              'Price',
                              '₹${_formatPrice((widget.booking['price'] as num?)?.toDouble() ?? 0)}',
                              highlight: true,
                            ),
                            _buildDivider(),
                            _buildDetailRow('ETA', '${(widget.booking['eta_hours'] as num?)?.toStringAsFixed(1) ?? '?'} hours'),
                            _buildDivider(),
                            _buildDetailRow('Status', (widget.booking['status'] ?? 'confirmed').toUpperCase(), statusColor: AppTheme.accentGreen),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  // TODO: Track shipment
                                },
                                icon: const Icon(Icons.location_on_rounded, size: 18),
                                label: const Text('Track'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accentCyan,
                                  side: BorderSide(
                                    color: AppTheme.accentCyan.withValues(alpha: 0.3),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  // TODO: Share details
                                },
                                icon: const Icon(Icons.share_rounded, size: 18),
                                label: const Text('Share'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accentPurple,
                                  side: BorderSide(
                                    color: AppTheme.accentPurple.withValues(alpha: 0.3),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // New shipment button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _ttsService.stop();
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('New Shipment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool highlight = false, Color? statusColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textMuted,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: statusColor ?? (highlight ? AppTheme.accentGreen : AppTheme.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withValues(alpha: 0.06),
      height: 1,
    );
  }

  String _formatPrice(double price) {
    if (price >= 100000) {
      return '${(price / 100000).toStringAsFixed(2)}L';
    } else if (price >= 1000) {
      final thousands = (price / 1000).toStringAsFixed(1);
      return '${thousands}K';
    }
    return price.toStringAsFixed(0);
  }
}
