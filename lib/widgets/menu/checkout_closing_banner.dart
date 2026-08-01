import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/smart_closing.dart';
import '../../theme/app_theme.dart';

class CheckoutClosingBanner extends StatelessWidget {
  const CheckoutClosingBanner({
    super.key,
    required this.closing,
    required this.localeCode,
  });

  final SmartClosingPayload closing;
  final String localeCode;

  IconData _iconForUrgency(String type) {
    switch (type) {
      case 'first_order':
        return Icons.card_giftcard;
      case 'almost_free_delivery':
        return Icons.local_fire_department;
      case 'peak_hour':
        return Icons.schedule;
      case 'returning_vip':
        return Icons.star;
      default:
        return Icons.bolt;
    }
  }

  Color _accentForUrgency(String type) {
    switch (type) {
      case 'first_order':
        return Colors.deepPurple;
      case 'almost_free_delivery':
        return AppTheme.brandOrange;
      case 'peak_hour':
        return const Color(0xFFE65100);
      case 'returning_vip':
        return AppTheme.brandMaroon;
      default:
        return AppTheme.brandOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = closing.messageFor(localeCode);
    if (message.trim().isEmpty) return const SizedBox.shrink();

    final accent = _accentForUrgency(closing.urgencyType);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.12),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconForUrgency(closing.urgencyType), color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.brandBlack,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckoutEtaCard extends StatelessWidget {
  const CheckoutEtaCard({
    super.key,
    required this.closing,
    required this.strings,
    required this.localeCode,
  });

  final SmartClosingPayload closing;
  final AppStrings strings;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final label = closing.etaLabelFor(localeCode);
    if (label.trim().isEmpty) return const SizedBox.shrink();

    final isPickup = closing.orderType == 'pickup';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.brandMaroon.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandMaroon.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPickup ? Icons.storefront_outlined : Icons.delivery_dining,
              color: AppTheme.brandOrange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.estimatedTimeTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brandMaroon,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandBlack,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.estimatedTimeHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
