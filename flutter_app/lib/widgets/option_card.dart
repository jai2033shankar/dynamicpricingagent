import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

/// Pricing option card with glassmorphism design
class OptionCard extends StatelessWidget {
  final Map<String, dynamic> option;
  final VoidCallback? onTap;
  final VoidCallback? onBook;
  final bool isExpanded;

  const OptionCard({
    super.key,
    required this.option,
    this.onTap,
    this.onBook,
    this.isExpanded = false,
  });

  Color _getBadgeColor(String? badge) {
    switch (badge) {
      case 'Best Value':
        return AppTheme.accentGreen;
      case 'Fastest':
        return AppTheme.accentAmber;
      case 'Most Reliable':
        return AppTheme.accentPurple;
      default:
        return AppTheme.accentBlue;
    }
  }

  IconData _getBadgeIcon(String? badge) {
    switch (badge) {
      case 'Best Value':
        return Icons.savings_rounded;
      case 'Fastest':
        return Icons.speed_rounded;
      case 'Most Reliable':
        return Icons.verified_rounded;
      default:
        return Icons.local_shipping_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = option['badge'] as String?;
    final badgeColor = _getBadgeColor(badge);
    final price = (option['price'] as num).toDouble();
    final eta = (option['eta_hours'] as num).toDouble();
    final carrier = option['carrier'] as String;
    final route = List<String>.from(option['route']);
    final breakdown = option['breakdown'] as Map<String, dynamic>;
    final confidence = (option['confidence_score'] as num).toDouble();
    final explanation = option['explanation'] as String;

    return GlassCard(
      onTap: onTap,
      showGlow: badge != null,
      glowColor: badgeColor,
      borderColor: badge != null ? badgeColor.withValues(alpha: 0.3) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge + Price row
          Row(
            children: [
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [badgeColor, badgeColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getBadgeIcon(badge), size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        badge,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              // Price
              Text(
                '₹${_formatPrice(price)}',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Carrier + ETA
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.local_shipping_rounded,
                    size: 20, color: AppTheme.accentBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      carrier,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'ETA: ${eta.toStringAsFixed(1)} hours',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Confidence gauge
              _ConfidenceGauge(score: confidence),
            ],
          ),
          const SizedBox(height: 12),

          // Route
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.route_rounded, size: 16, color: AppTheme.accentCyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route.join(' → '),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded details
          if (isExpanded) ...[
            const SizedBox(height: 16),
            // Price breakdown
            _buildBreakdownRow('Base Cost', breakdown['base_cost']),
            _buildBreakdownRow('Demand Surge', breakdown['demand_surge']),
            _buildBreakdownRow('Fuel Adjustment', breakdown['fuel_adjustment']),
            _buildBreakdownRow('Priority Premium', breakdown['priority_premium']),
            _buildBreakdownRow('Weight Surcharge', breakdown['weight_surcharge']),
            _buildBreakdownRow('Margin', breakdown['margin']),
            const Divider(color: AppTheme.cardBorder, height: 20),

            // Explanation
            Text(
              explanation,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // Book button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onBook,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Confirm Booking'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, dynamic value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    if (amount <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
          ),
          Text(
            '₹${_formatPrice(amount)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    if (price >= 100000) {
      return '${(price / 100000).toStringAsFixed(1)}L';
    } else if (price >= 1000) {
      return '${(price / 1000).toStringAsFixed(1)}K';
    }
    return price.toStringAsFixed(0);
  }
}

/// Circular confidence score gauge
class _ConfidenceGauge extends StatelessWidget {
  final double score;

  const _ConfidenceGauge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score > 0.85
        ? AppTheme.accentGreen
        : score > 0.7
            ? AppTheme.accentAmber
            : AppTheme.accentRed;

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score,
            strokeWidth: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '${(score * 100).toInt()}',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
