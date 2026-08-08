import 'package:flutter/material.dart';

enum AdminSettingsTab {
  platforms('platforms', 'إعدادات المنصات'),
  roles('roles', 'الأدوار والكاشير'),
  whatsapp('whatsapp', 'رقم الواتساب والربط'),
  store('store', 'بيانات المحل والمعاينة'),
  workingHours('working-hours', 'مواعيد العمل'),
  audioNotifications('audio-notifications', 'إعدادات التنبيه الصوتي'),
  loyalty('loyalty', 'برنامج الولاء والكاش باك'),
  email('email', 'إشعارات الإيميل'),
  paymentMethods('payment-methods', 'طرق الدفع');

  const AdminSettingsTab(this.id, this.labelAr);

  final String id;
  final String labelAr;

  String get routePath => '/admin/settings/$id';

  static const settingsBasePath = '/admin/settings';

  static const sidebarOrder = [
    AdminSettingsTab.platforms,
    AdminSettingsTab.roles,
    AdminSettingsTab.whatsapp,
    AdminSettingsTab.store,
    AdminSettingsTab.workingHours,
    AdminSettingsTab.audioNotifications,
    AdminSettingsTab.loyalty,
    AdminSettingsTab.email,
    AdminSettingsTab.paymentMethods,
  ];

  static AdminSettingsTab get defaultTab => AdminSettingsTab.platforms;

  static AdminSettingsTab fromId(String? value) {
    if (value == null || value.isEmpty) return defaultTab;
    for (final tab in AdminSettingsTab.values) {
      if (tab.id == value) return tab;
    }
    return defaultTab;
  }

  static AdminSettingsTab? fromRoutePath(String? path) {
    if (path == null || path.isEmpty) return null;
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    if (normalized == settingsBasePath) return defaultTab;
    if (!normalized.startsWith('$settingsBasePath/')) return null;
    final segment = normalized.substring(settingsBasePath.length + 1);
    if (segment.contains('/')) return null;
    return fromId(segment);
  }

  static bool isSettingsRoute(String? path) {
    if (path == null || path.isEmpty) return false;
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    return normalized == settingsBasePath ||
        normalized.startsWith('$settingsBasePath/');
  }

  static List<AdminSettingsTab> sidebarItems({required bool isSuperAdmin}) {
    return sidebarOrder;
  }

  IconData get icon {
    switch (this) {
      case AdminSettingsTab.platforms:
        return Icons.hub_outlined;
      case AdminSettingsTab.roles:
        return Icons.admin_panel_settings_outlined;
      case AdminSettingsTab.whatsapp:
        return Icons.chat_bubble_outline;
      case AdminSettingsTab.store:
        return Icons.storefront_outlined;
      case AdminSettingsTab.workingHours:
        return Icons.schedule_outlined;
      case AdminSettingsTab.audioNotifications:
        return Icons.notifications_active_outlined;
      case AdminSettingsTab.loyalty:
        return Icons.card_giftcard_outlined;
      case AdminSettingsTab.email:
        return Icons.mail_outline;
      case AdminSettingsTab.paymentMethods:
        return Icons.payments_outlined;
    }
  }
}
