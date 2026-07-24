import 'package:flutter/material.dart';

import 'admin_restaurant_selector.dart';

class AdminTopHeader extends StatelessWidget {
  const AdminTopHeader({
    super.key,
    this.pendingOrdersCount = 0,
    this.onNotificationsTap,
    this.isSuperAdmin = false,
    this.restaurantLabel,
  });

  final int pendingOrdersCount;
  final VoidCallback? onNotificationsTap;
  final bool isSuperAdmin;
  final String? restaurantLabel;

  static const Color burgundy = Color(0xFF6B1124);
  static const Color gold = Color(0xFFD49A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSuperAdmin
                      ? 'لوحة AlMenuPro — Super Admin'
                      : 'مرحباً بك${restaurantLabel != null ? '، $restaurantLabel' : ''} 👋',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: burgundy,
                  ),
                ),
                if (isSuperAdmin)
                  const Text(
                    'اختر المطعم من القائمة لإدارة المنيو والإعدادات والطلبات',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
              ],
            ),
          ),
          if (isSuperAdmin) ...[
            const AdminRestaurantSelector(),
            const SizedBox(width: 16),
          ],
          IconButton(
            tooltip: 'الطلبات الجديدة',
            onPressed: onNotificationsTap,
            icon: Badge(
              isLabelVisible: pendingOrdersCount > 0,
              label: Text('$pendingOrdersCount'),
              backgroundColor: gold,
              child: const Icon(
                Icons.notifications_outlined,
                color: burgundy,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: burgundy.withValues(alpha: 0.12),
            child: const Icon(
              Icons.person,
              color: burgundy,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}
