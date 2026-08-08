import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings/admin_settings_tab.dart';

class AdminSidebarItem {
  const AdminSidebarItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// Default admin navigation — POS first, then orders, menu, analytics, settings.
class AdminSidebar extends StatefulWidget {
  const AdminSidebar({
    super.key,
    this.items = defaultItems,
    required this.selectedIndex,
    required this.onItemSelected,
    this.width = expandedWidth,
    this.enableCollapse = true,
    this.footerBuilder,
    this.settingsNavIndex,
    this.settingsTabs = const [],
    this.activeSettingsTab,
    this.onSettingsTabSelected,
  });

  static const double expandedWidth = 260;
  static const double collapsedWidth = 76;

  static const int posIndex = 0;
  static const int ordersIndex = 1;
  static const int kitchenIndex = 2;
  static const int customersIndex = 3;
  static const int menuIndex = 4;
  static const int deliveryZonesIndex = 5;
  static const int analyticsIndex = 6;
  static const int smartUpsellIndex = 7;
  static const int settingsIndex = 8;

  /// Super Admin sidebar — no orders tab (restaurant admins only).
  static const int superMenuIndex = 0;
  static const int superRestaurantsIndex = 1;
  static const int superKitchenIndex = 2;
  static const int superDeliveryZonesIndex = 3;
  static const int superAnalyticsIndex = 4;
  static const int superSmartUpsellIndex = 5;
  static const int superSettingsIndex = 6;

  static const List<AdminSidebarItem> defaultItems = [
    AdminSidebarItem(
      icon: Icons.point_of_sale,
      label: 'نقطة البيع POS',
    ),
    AdminSidebarItem(
      icon: Icons.receipt_long_outlined,
      label: 'الطلبات',
    ),
    AdminSidebarItem(
      icon: Icons.soup_kitchen_outlined,
      label: 'المطبخ',
    ),
    AdminSidebarItem(
      icon: Icons.people_outline,
      label: 'العملاء',
    ),
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(
      icon: Icons.local_shipping_outlined,
      label: 'مناطق التوصيل ورسومها',
    ),
    AdminSidebarItem(
      icon: Icons.bar_chart,
      label: 'التحليلات والمبيعات',
    ),
    AdminSidebarItem(
      icon: Icons.auto_awesome,
      label: 'البياع الشاطر',
    ),
    AdminSidebarItem(
      icon: Icons.store,
      label: 'إعدادات المحل والواتساب',
    ),
  ];

  /// Cashier sessions are limited to POS views only.
  static const List<AdminSidebarItem> cashierItems = [
    AdminSidebarItem(
      icon: Icons.point_of_sale,
      label: 'نقطة البيع POS',
    ),
  ];

  static const List<AdminSidebarItem> superAdminItems = [
    AdminSidebarItem(
      icon: Icons.restaurant_menu,
      label: 'إدارة المنيو والأصناف',
    ),
    AdminSidebarItem(
      icon: Icons.apartment,
      label: 'المطاعم والاستيراد',
    ),
    AdminSidebarItem(
      icon: Icons.soup_kitchen_outlined,
      label: 'المطبخ',
    ),
    AdminSidebarItem(
      icon: Icons.local_shipping_outlined,
      label: 'مناطق التوصيل ورسومها',
    ),
    AdminSidebarItem(
      icon: Icons.bar_chart,
      label: 'التحليلات والمبيعات',
    ),
    AdminSidebarItem(
      icon: Icons.auto_awesome,
      label: 'البياع الشاطر',
    ),
    AdminSidebarItem(
      icon: Icons.settings,
      label: 'إعدادات المنصة',
    ),
  ];

  static const Color sidebarBg = Color(0xFF2C353F);
  static const Color activeBg = Color(0xFF6B1124);
  static const Color activeGold = Color(0xFFD49A00);

  static const _collapsedPrefKey = 'admin_sidebar_collapsed';

  final List<AdminSidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final double width;
  final bool enableCollapse;
  final Widget Function(bool collapsed)? footerBuilder;
  final int? settingsNavIndex;
  final List<AdminSettingsTab> settingsTabs;
  final AdminSettingsTab? activeSettingsTab;
  final ValueChanged<AdminSettingsTab>? onSettingsTabSelected;

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  var _collapsed = false;
  var _prefLoaded = false;
  var _settingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _settingsExpanded = widget.activeSettingsTab != null;
    if (widget.enableCollapse) {
      _loadCollapsedPreference();
    } else {
      _prefLoaded = true;
    }
  }

  @override
  void didUpdateWidget(covariant AdminSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSettingsTab != null) {
      _settingsExpanded = true;
    }
  }

  Future<void> _loadCollapsedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _collapsed = prefs.getBool(AdminSidebar._collapsedPrefKey) ?? false;
      _prefLoaded = true;
    });
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AdminSidebar._collapsedPrefKey, _collapsed);
  }

  bool get _isCollapsed => widget.enableCollapse && _collapsed;

  double get _effectiveWidth {
    if (!_isCollapsed) return widget.width;
    return AdminSidebar.collapsedWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefLoaded && widget.enableCollapse) {
      return SizedBox(
        width: widget.width,
        child: const ColoredBox(
          color: AdminSidebar.sidebarBg,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AdminSidebar.activeGold,
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: _effectiveWidth,
      color: AdminSidebar.sidebarBg,
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            Expanded(child: _buildNavList()),
            if (widget.footerBuilder != null)
              widget.footerBuilder!(_isCollapsed),
            if (widget.enableCollapse) _buildCollapseToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      padding: EdgeInsets.symmetric(
        vertical: 28,
        horizontal: _isCollapsed ? 12 : 20,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminSidebar.activeGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.restaurant_menu,
              color: AdminSidebar.activeGold,
              size: 28,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _isCollapsed
                ? const SizedBox.shrink(key: ValueKey('logo-collapsed'))
                : const Padding(
                    key: ValueKey('logo-expanded'),
                    padding: EdgeInsetsDirectional.only(start: 12),
                    child: Text(
                      'Almenupro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavList() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: _isCollapsed ? 8 : 12),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        if (widget.settingsNavIndex == index && widget.settingsTabs.isNotEmpty) {
          return _buildSettingsNavItem(widget.items[index], index);
        }
        return _buildRegularNavItem(widget.items[index], index);
      },
    );
  }

  Widget _buildRegularNavItem(AdminSidebarItem item, int index) {
    final isActive = widget.selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isActive ? AdminSidebar.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onItemSelected(index),
          child: Tooltip(
            message: _isCollapsed ? item.label : '',
            preferBelow: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _isCollapsed ? 0 : 16,
                vertical: 14,
              ),
              child: _isCollapsed
                  ? Center(
                      child: Icon(
                        item.icon,
                        color: isActive
                            ? AdminSidebar.activeGold
                            : Colors.white70,
                        size: 22,
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          item.icon,
                          color: isActive
                              ? AdminSidebar.activeGold
                              : Colors.white70,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AnimatedOpacity(
                            opacity: _isCollapsed ? 0 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              item.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white70,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AdminSidebar.activeGold,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsNavItem(AdminSidebarItem item, int index) {
    final isOnSettings = widget.selectedIndex == index;
    final activeTab = widget.activeSettingsTab;

    if (_isCollapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: isOnSettings ? AdminSidebar.activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              widget.onItemSelected(index);
              final first = widget.settingsTabs.first;
              widget.onSettingsTabSelected?.call(first);
            },
            child: Tooltip(
              message: item.label,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Icon(
                    item.icon,
                    color: isOnSettings
                        ? AdminSidebar.activeGold
                        : Colors.white70,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isOnSettings ? AdminSidebar.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _settingsExpanded = !_settingsExpanded);
                if (!isOnSettings) {
                  widget.onItemSelected(index);
                  widget.onSettingsTabSelected?.call(widget.settingsTabs.first);
                }
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      color: isOnSettings
                          ? AdminSidebar.activeGold
                          : Colors.white70,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOnSettings ? Colors.white : Colors.white70,
                          fontWeight:
                              isOnSettings ? FontWeight.bold : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(
                      _settingsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: isOnSettings
                          ? AdminSidebar.activeGold
                          : Colors.white54,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            if (_settingsExpanded)
              ...widget.settingsTabs.map((tab) {
                final selected = isOnSettings && activeTab == tab;
                return Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 8,
                    bottom: 4,
                  ),
                  child: Material(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        widget.onItemSelected(index);
                        widget.onSettingsTabSelected?.call(tab);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              tab.icon,
                              size: 18,
                              color: selected
                                  ? AdminSidebar.activeGold
                                  : Colors.white60,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tab.labelAr,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapseToggle() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _isCollapsed ? 8 : 12,
        4,
        _isCollapsed ? 8 : 12,
        4,
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _toggleCollapsed,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedRotation(
                  turns: _isCollapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isCollapsed
                      ? const SizedBox.shrink(key: ValueKey('collapse-label-off'))
                      : const Padding(
                          key: ValueKey('collapse-label-on'),
                          padding: EdgeInsetsDirectional.only(start: 8),
                          child: Text(
                            'تصغير القائمة',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
