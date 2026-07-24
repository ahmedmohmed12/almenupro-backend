import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'screens/admin_dashboard.dart';
import 'screens/client_menu_page.dart';
import 'screens/menu_screen.dart';
import 'services/menu_storage_service.dart';
import 'services/molton_upload_service.dart';
import 'services/seed_service.dart';
import 'theme/app_theme.dart';
import 'utils/configure_url_strategy.dart' show configureUrlStrategy;
import 'utils/firebase_config.dart';
import 'utils/restaurant_route.dart';

Future<void> main() async {
  // Flutter Web: usePathUrlStrategy() — see configure_url_strategy_web.dart
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (isFirebaseConfigured) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      debugPrint('Skipping Firebase init: web credentials not configured.');
    }
    await MenuStorageService.instance.initialize();
    if (isFirebaseConfigured) {
      unawaited(SeedService().seedMenuIfEmpty());
      unawaited(MoltonUploadService().uploadMoltonDataIfEmpty());
    }
  } catch (e) {
    debugPrint('Bootstrap error: $e');
    try {
      await MenuStorageService.instance.initialize();
    } catch (_) {}
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static String normalizeRoute(String? routeName) {
    var route = (routeName == null || routeName.isEmpty)
        ? (kIsWeb ? Uri.base.path : '/')
        : routeName;
    if (route.endsWith('/') && route.length > 1) {
      route = route.substring(0, route.length - 1);
    }
    return route.isEmpty ? '/' : route;
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final route = normalizeRoute(settings.name);

    switch (route) {
      case '/admin':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminDashboard(),
        );
      case '/legacy-menu':
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ClientMenuPage(),
        );
      default:
        final slug = RestaurantRoute.parseSlug(
          route,
          query: kIsWeb ? Uri.base.queryParameters : null,
        );
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => MenuScreen(restaurantSlug: slug),
        );
    }
  }

  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    // On web, Uri.base.path reflects the browser URL (/admin, etc.).
    final route = normalizeRoute(kIsWeb ? Uri.base.path : initialRoute);
    return [onGenerateRoute(RouteSettings(name: route))];
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Almenupro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateRoute,
      onUnknownRoute: onGenerateRoute,
      onGenerateInitialRoutes: onGenerateInitialRoutes,
      builder: (context, child) {
        if (child == null) {
          return const ColoredBox(
            color: AppTheme.brandBackground,
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.brandOrange),
            ),
          );
        }
        return child;
      },
    );
  }
}
