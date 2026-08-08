import '../widgets/admin/admin_sidebar.dart';
import '../widgets/admin/settings/admin_settings_tab.dart';
import 'restaurant_route.dart';

/// Admin dashboard URL helpers — keeps `/admin/...` paths on the admin shell.
class AdminRoute {
  AdminRoute._();

  static bool isAdminPath(String? path) {
    final normalized = RestaurantRoute.normalizePath(path);
    return normalized == '/admin' || normalized.startsWith('/admin/');
  }

  /// Maps the current browser path to the admin sidebar tab index.
  static int sidebarIndexForPath(String? path, {required bool isSuperAdmin}) {
    final normalized = RestaurantRoute.normalizePath(path);
    if (normalized == '/' || normalized == '/admin') {
      return isSuperAdmin
          ? AdminSidebar.superMenuIndex
          : AdminSidebar.ordersIndex;
    }

    if (AdminSettingsTab.isSettingsRoute(normalized)) {
      return isSuperAdmin
          ? AdminSidebar.superSettingsIndex
          : AdminSidebar.settingsIndex;
    }

    if (normalized.startsWith('/admin/pos')) {
      return isSuperAdmin ? AdminSidebar.superMenuIndex : AdminSidebar.posIndex;
    }

    if (normalized.startsWith('/admin/kitchen')) {
      return AdminSidebar.kitchenIndex;
    }

    return isSuperAdmin
        ? AdminSidebar.superMenuIndex
        : AdminSidebar.ordersIndex;
  }
}
