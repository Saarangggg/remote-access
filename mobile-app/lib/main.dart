import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'core/router.dart';
import 'core/theme.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'shared/services/storage_service.dart';
import 'shared/services/api_service.dart';
import 'shared/providers/connection_provider.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait + landscape support
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);

  // Initialize local notifications
  const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
  const initSettings = InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(initSettings);

  // Immersive status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0F),
  ));

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const RemoteConnectApp(),
    ),
  );
}

class RemoteConnectApp extends ConsumerStatefulWidget {
  const RemoteConnectApp({super.key});

  @override
  ConsumerState<RemoteConnectApp> createState() => _RemoteConnectAppState();
}

class _RemoteConnectAppState extends ConsumerState<RemoteConnectApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  void _autoConnect() {
    try {
      final storage = ref.read(storageServiceProvider);
      final activeDevice = storage.getActiveDevice();
      if (activeDevice != null) {
        ref.read(apiServiceProvider).configure(activeDevice.baseUrl, activeDevice.accessToken);
        ref.read(connectionProvider.notifier).connect(activeDevice);
      }
    } catch (e) {
      debugPrint('Auto-connect failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'RemoteConnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
