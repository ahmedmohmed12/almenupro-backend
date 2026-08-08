import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/strings_admin.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_service.dart';
import '../../services/super_admin_scope_service.dart';
import 'admin_kitchen_panel.dart';
import 'admin_kitchens_panel.dart';

/// Kitchen area: management (CRUD) + operational KDS view.
class AdminKitchenHub extends StatefulWidget {
  const AdminKitchenHub({super.key});

  @override
  State<AdminKitchenHub> createState() => _AdminKitchenHubState();
}

class _AdminKitchenHubState extends State<AdminKitchenHub>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onScopeChanged() {
    if (mounted) setState(() {});
  }

  String get _restaurantId {
    if (AdminAuthService.instance.isRestaurantAdmin) {
      return AdminAuthService.instance.restaurantId ??
          ApiService.defaultRestaurantId;
    }
    final scoped = SuperAdminScopeService.instance.effectiveRestaurantId;
    if (scoped.isNotEmpty) return scoped;
    return AdminAuthService.instance.restaurantId ?? ApiService.defaultRestaurantId;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.navKitchen,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6B1124),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.kitchenHubSubtitle,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabs,
                    labelColor: const Color(0xFF6B1124),
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: const Color(0xFF6B1124),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.soup_kitchen_outlined),
                        text: s.kitchensPanelTitle,
                      ),
                      Tab(
                        icon: const Icon(Icons.monitor_heart_outlined),
                        text: s.kitchenOperationsTab,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: AdminKitchensPanel(
                    key: ValueKey('kitchens-$_restaurantId'),
                    restaurantId: _restaurantId,
                    canManage: true,
                  ),
                ),
                AdminKitchenPanel(key: ValueKey('kds-$_restaurantId')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
