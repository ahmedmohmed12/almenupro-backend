import 'package:flutter/material.dart';

import '../../../services/super_admin_scope_service.dart';
import '../admin_breakpoints.dart';
import '../admin_loyalty_settings_card.dart';
import '../admin_payment_settings_card.dart';
import '../admin_platform_settings_card.dart';
import '../admin_pos_roles_staff_card.dart';
import '../admin_responsive_layout.dart';
import '../admin_sound_settings_card.dart';
import '../admin_store_profile_card.dart';
import '../admin_working_hours_card.dart';
import 'admin_email_notifications_card.dart';
import 'admin_settings_tab.dart';
import 'admin_whatsapp_settings_section.dart';

class AdminSettingsTabbedPanel extends StatelessWidget {
  const AdminSettingsTabbedPanel({
    super.key,
    required this.isSuperAdmin,
    required this.activeTab,
    this.restaurantLabel,
  });

  final bool isSuperAdmin;
  final AdminSettingsTab activeTab;
  final String? restaurantLabel;

  static const burgundy = Color(0xFF6B1124);

  Widget _buildActiveTabContent() {
    switch (activeTab) {
      case AdminSettingsTab.whatsapp:
        return const AdminWhatsappSettingsSection();
      case AdminSettingsTab.store:
        return const AdminStoreProfileCard();
      case AdminSettingsTab.loyalty:
        return const AdminLoyaltySettingsCard();
      case AdminSettingsTab.email:
        return const AdminEmailNotificationsCard();
      case AdminSettingsTab.platforms:
        return const AdminPlatformSettingsCard();
      case AdminSettingsTab.paymentMethods:
        return const AdminPaymentSettingsCard();
      case AdminSettingsTab.roles:
        return const AdminPosRolesStaffCard();
      case AdminSettingsTab.workingHours:
        return const AdminWorkingHoursCard();
      case AdminSettingsTab.audioNotifications:
        return const AdminSoundSettingsCard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = SuperAdminScopeService.instance;
    final label = isSuperAdmin
        ? (scope.selectedRestaurantName ?? '—')
        : (restaurantLabel ?? 'المطعم');
    final isRoles = activeTab == AdminSettingsTab.roles;
    final pagePad = AdminBreakpoints.pagePadding(context);

    return AdminResponsivePage(
      scrollable: true,
      padding: isRoles
          ? EdgeInsets.fromLTRB(pagePad, 8, pagePad, pagePad)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isRoles) ...[
            Text(
              activeTab.labelAr,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: burgundy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSuperAdmin
                  ? 'المطعم الحالي: $label'
                  : 'إعدادات المحل والواتساب',
            ),
            if (isSuperAdmin && !scope.hasSelection) ...[
              const SizedBox(height: 12),
              const Text(
                'اختر مطعماً من قائمة «المطاعم» أولاً.',
                style: TextStyle(color: Colors.orange),
              ),
            ],
            const SizedBox(height: 20),
          ] else ...[
            if (isSuperAdmin && !scope.hasSelection) ...[
              const Text(
                'اختر مطعماً من قائمة «المطاعم» أولاً.',
                style: TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 8),
            ],
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(activeTab.id),
              child: _buildActiveTabContent(),
            ),
          ),
        ],
      ),
    );
  }
}
