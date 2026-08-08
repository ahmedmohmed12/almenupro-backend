import 'admin_route.dart';
import 'restaurant_route.dart';

/// Top-level Flutter web routes for Menu Pro.
class AppRoute {
  AppRoute._();

  static String normalize(String? routeName, {String? fallbackPath}) {
    var route = (routeName == null || routeName.isEmpty)
        ? (fallbackPath ?? '/')
        : routeName;
    if (route.endsWith('/') && route.length > 1) {
      route = route.substring(0, route.length - 1);
    }
    return route.isEmpty ? '/' : route;
  }

  static bool isAdminRoute(String route) {
    if (route == '/') return true;
    return AdminRoute.isAdminPath(route);
  }

  static bool isLegacyMenuRoute(String route) => route == '/legacy-menu';

  static bool isCustomerMenuRoute(String route) {
    if (route == '/') return false;
    if (route.startsWith('/menu/') || route.startsWith('/restaurant/')) {
      return true;
    }
    return RestaurantRoute.parseSlug(route) != null;
  }
}
