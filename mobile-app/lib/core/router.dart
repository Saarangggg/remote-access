import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/screen_view/screen_view_screen.dart';
import '../features/files/files_screen.dart';
import '../features/clipboard/clipboard_screen.dart';
import '../features/keyboard/keyboard_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/pairing/pairing_screen.dart';
import '../shared/providers/connection_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      // ── Main Shell with Bottom Nav ────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
          GoRoute(path: '/screen', builder: (c, s) => const ScreenViewScreen()),
          GoRoute(path: '/files', builder: (c, s) => const FilesScreen()),
          GoRoute(path: '/clipboard', builder: (c, s) => const ClipboardScreen()),
          GoRoute(path: '/keyboard', builder: (c, s) => const KeyboardScreen()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        ],
      ),
      // ── Pairing Flow ──────────────────────────────────────────────────────
      GoRoute(path: '/pair', builder: (c, s) => const PairingScreen()),
    ],
  );
});

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  static const _routes = [
    '/dashboard',
    '/screen',
    '/files',
    '/clipboard',
    '/keyboard',
    '/settings',
  ];

  static const _navItems = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.monitor_outlined),
      selectedIcon: Icon(Icons.monitor_rounded),
      label: 'Screen',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder_rounded),
      label: 'Files',
    ),
    NavigationDestination(
      icon: Icon(Icons.content_paste_outlined),
      selectedIcon: Icon(Icons.content_paste_rounded),
      label: 'Clipboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.keyboard_outlined),
      selectedIcon: Icon(Icons.keyboard_rounded),
      label: 'Keyboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  void _onDestinationSelected(int index) {
    setState(() => _currentIndex = index);
    context.go(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _navItems,
        animationDuration: const Duration(milliseconds: 300),
      ),
    );
  }
}
