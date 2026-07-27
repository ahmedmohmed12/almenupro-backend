import 'package:flutter/material.dart';

import 'admin_smart_upsell_settings_card.dart';

class AdminSmartUpsellPanel extends StatelessWidget {
  const AdminSmartUpsellPanel({super.key});

  static const burgundy = Color(0xFF6B1124);
  static const gold = Color(0xFFD49A00);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: burgundy,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'البياع الشاطر — Smart Upsell',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: burgundy,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'محرك Upsell المرحلة 2: اقتراحات ذكية حسب السلة، '
                      'سايد إيتمز مربوطة، وإضافات سريعة محسّنة في الدفع.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF555555),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const AdminSmartUpsellSettingsCard(),
        ],
      ),
    );
  }
}
