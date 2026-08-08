import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/strings_admin.dart';

/// Green / burgundy indicator strip for pending + kitchen queue counts.
class IncomingOrdersAlertBar extends StatelessWidget {
  const IncomingOrdersAlertBar({
    super.key,
    required this.pendingCount,
    this.kitchenCount = 0,
  });

  final int pendingCount;
  final int kitchenCount;

  @override
  Widget build(BuildContext context) {
    if (pendingCount <= 0 && kitchenCount <= 0) {
      return const SizedBox.shrink();
    }

    final s = AppStrings.of(context);
    final hasPending = pendingCount > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasPending
              ? const [Color(0xFF1B7F4E), Color(0xFF6B1124)]
              : const [Color(0xFF6B1124), Color(0xFFD49A00)],
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasPending
                ? Icons.notifications_active
                : Icons.soup_kitchen_outlined,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasPending
                  ? '${s.incomingOrdersBar} ($pendingCount)'
                  : '${s.kitchenMonitorTitle}: $kitchenCount',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          if (kitchenCount > 0 && hasPending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'مطبخ: $kitchenCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
