import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/admin_dashboard.dart';
import 'screens/client_menu_page.dart';
import 'screens/menu_screen.dart';
import 'services/menu_storage_service.dart';
import 'services/molton_upload_service.dart';
import 'services/seed_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_route.dart';
import 'utils/configure_url_strategy.dart';

bool get _isFirebaseConfigured {
  if (!kIsWeb) return true;
  final options = DefaultFirebaseOptions.web;
  return !options.apiKey.startsWith('YOUR_') &&
      !options.projectId.startsWith('YOUR_');
}

Future<void> main() async {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (_isFirebaseConfigured) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      debugPrint('Skipping Firebase init: web credentials not configured.');
    }
    await MenuStorageService.instance.initialize();
    if (_isFirebaseConfigured) {
      unawaited(SeedService().seedMenuIfEmpty());
      unawaited(MoltonUploadService().uploadMoltonDataIfEmpty());
    }
  } catch (e) {
    debugPrint('Bootstrap error: $e');
    try {
      await MenuStorageService.instance.initialize();
    } catch (_) {}
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static String _normalizeRoute(String? routeName) {
    return AppRoute.normalize(
      routeName,
      fallbackPath: kIsWeb ? Uri.base.path : '/',
    );
  }

  static Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final route = _normalizeRoute(settings.name);

    if (AppRoute.isAdminRoute(route)) {
      return MaterialPageRoute(
        settings: RouteSettings(name: route, arguments: settings.arguments),
        builder: (_) => const AdminDashboard(),
      );
    }

    if (AppRoute.isLegacyMenuRoute(route)) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const ClientMenuPage(),
      );
    }

    if (AppRoute.isCustomerMenuRoute(route)) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const MenuScreen(),
      );
    }

    return MaterialPageRoute(
      settings: RouteSettings(name: '/admin', arguments: settings.arguments),
      builder: (_) => const AdminDashboard(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final locale = LocaleProvider();
            unawaited(locale.load());
            return locale;
          },
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, locale, _) {
          return MaterialApp(
            title: 'Almenupro',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(isArabic: locale.isArabic),
            locale: Locale(locale.localeCode),
            builder: (context, child) {
              return Directionality(
                textDirection: locale.textDirection,
                child: child ?? const SizedBox.shrink(),
              );
            },
            onGenerateRoute: _onGenerateRoute,
            onUnknownRoute: _onGenerateRoute,
          );
        },
      ),
    );
  }
}
