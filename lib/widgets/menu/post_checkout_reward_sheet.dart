import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../models/smart_closing.dart';
import '../../theme/app_theme.dart';

class PostCheckoutRewardSheet {
  static Future<void> show(
    BuildContext context, {
    required SmartClosingPayload closing,
    required AppStrings strings,
    required String localeCode,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PostCheckoutRewardContent(
        closing: closing,
        strings: strings,
        localeCode: localeCode,
      ),
    );
  }
}

class _PostCheckoutRewardContent extends StatelessWidget {
  const _PostCheckoutRewardContent({
    required this.closing,
    required this.strings,
    required this.localeCode,
  });

  final SmartClosingPayload closing;
  final AppStrings strings;
  final String localeCode;

  Future<void> _copyPromoCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.promoCodeCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rewards = closing.rewards;
    final message = closing.postCheckoutMessageFor(localeCode);
    final promoCode = rewards.personalPromoCode.trim();
    final promoDiscount = rewards.personalPromoDiscount > 0
        ? rewards.personalPromoDiscount
        : rewards.welcomeDiscountForNextOrder;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.celebration,
              color: AppTheme.brandOrange,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.orderConfirmedTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.brandMaroon,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: AppTheme.brandBlack,
            ),
          ),
          if (promoCode.isNotEmpty && promoDiscount > 0) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.brandMaroon.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.brandMaroon.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    strings.personalPromoCodeLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandMaroon,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    promoCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: AppTheme.brandMaroon,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.personalPromoHint(
                      promoCode,
                      promoDiscount.toStringAsFixed(3),
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _copyPromoCode(context, promoCode),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(strings.copyPromoCode),
                  ),
                ],
              ),
            ),
          ],
          if (rewards.hasAnyReward) ...[
            const SizedBox(height: 20),
            _RewardTile(
              icon: Icons.account_balance_wallet_outlined,
              label: strings.loyaltyWalletLabel,
              value: '${rewards.walletBalance.toStringAsFixed(3)} ${strings.currency}',
            ),
            if (rewards.earnedCashback > 0) ...[
              const SizedBox(height: 10),
              _RewardTile(
                icon: Icons.savings_outlined,
                label: strings.cashbackEarnedLabel,
                value:
                    '+${rewards.earnedCashback.toStringAsFixed(3)} ${strings.currency}',
                highlight: true,
              ),
            ],
            if (rewards.welcomeDiscountForNextOrder > 0 && promoCode.isEmpty) ...[
              const SizedBox(height: 10),
              _RewardTile(
                icon: Icons.local_offer_outlined,
                label: strings.nextOrderDiscountLabel,
                value:
                    '${rewards.welcomeDiscountForNextOrder.toStringAsFixed(3)} ${strings.currency}',
                highlight: true,
              ),
            ],
          ],
          const SizedBox(height: 14),
          Text(
            closing.etaLabelFor(localeCode),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.gotIt),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.brandOrange.withValues(alpha: 0.08)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? AppTheme.brandOrange.withValues(alpha: 0.35)
              : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.brandMaroon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? AppTheme.brandMaroon : AppTheme.brandBlack,
            ),
          ),
        ],
      ),
    );
  }
}
