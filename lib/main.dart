import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/admin_dashboard.dart';
import 'screens/client_menu_page.dart';
import 'screens/menu_screen.dart';
import 'services/menu_storage_service.dart';
import 'services/molton_upload_service.dart';
import 'services/seed_service.dart';
import 'utils/configure_url_strategy.dart';

Future<void> main() async {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await MenuStorageService.instance.initialize();
    unawaited(SeedService().seedMenuIfEmpty());
    unawaited(MoltonUploadService().uploadMoltonDataIfEmpty());
  } catch (e) {
    debugPrint('Firebase Error: $e');
    await MenuStorageService.instance.initialize();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Almenupro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.brown),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/admin' || settings.name == 'admin') {
          return MaterialPageRoute(builder: (_) => const AdminDashboard());
        }
        if (settings.name == '/legacy-menu') {
          return MaterialPageRoute(builder: (_) => const ClientMenuPage());
        }
        return MaterialPageRoute(builder: (_) => const MenuScreen());
      },
    );
  }
}
