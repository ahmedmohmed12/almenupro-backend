import 'package:flutter/material.dart';

class AdminSidebarItem {
  const AdminSidebarItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// Default admin navigation — الطلبات first, then menu, analytics, settings.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    super.key,
    this.items = defaultItems,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
    this.width = 260,
  });

  static const int ordersIndex = 0;
  static const int menuIndex = 1;
  static const int analyticsIndex = 2;
  static const int settingsIndex = 3;
  static const int restaurantsIndex = 4;

  static const List<AdminSidebarItem> defaultItems = [
    // Must stay first: opens AdminOrdersPanel (new + archived tabs).
    AdminSidebarItem(
      icon: Icons.receipt_long_outlined,
      label: 'الطلبات',
    ),
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(
      icon: Icons.bar_chart,
      label: 'التحليلات والمبيعات',
    ),
    AdminSidebarItem(
      icon: Icons.store,
      label: 'إعدادات المحل والواتساب',
    ),
  ];

  static const List<AdminSidebarItem> superAdminItems = [
    AdminSidebarItem(
      icon: Icons.receipt_long_outlined,
      label: 'الطلبات',
    ),
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(
      icon: Icons.apartment,
      label: 'المطاعم والاستيراد',
    ),
    AdminSidebarItem(
      icon: Icons.bar_chart,
      label: 'التحليلات والمبيعات',
    ),
    AdminSidebarItem(
      icon: Icons.settings,
      label: 'إعدادات المنصة',
    ),
  ];

  static const Color sidebarBg = Color(0xFF2C353F);
  static const Color activeBg = Color(0xFF6B1124);
  static const Color activeGold = Color(0xFFD49A00);

  final List<AdminSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onLogout;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: activeGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: activeGold,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Almenupro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isActive = selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isActive ? activeBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onItemSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: isActive ? activeGold : Colors.white70,
                              size: 22,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: isActive ? Colors.white : Colors.white70,
                                  fontWeight:
                                      isActive ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (isActive)
                              Container(
                                width: 4,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: activeGold,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade300,
                  side: BorderSide(color: Colors.red.shade400),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onLogout,
                icon: const Icon(Icons.logout, size: 20),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
