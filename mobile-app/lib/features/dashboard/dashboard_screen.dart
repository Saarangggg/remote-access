import 'dart:async';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shared/providers/connection_provider.dart';
import '../../shared/services/storage_service.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/info_tile.dart';
import '../../shared/widgets/gradient_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Map<String, dynamic>? _deviceStatus;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _listenToDeviceStatus();
  }

  void _listenToDeviceStatus() {
    final socket = ref.read(socketServiceProvider);
    _statusSub = socket.onDeviceStatus.listen((status) {
      if (mounted) setState(() => _deviceStatus = status);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);
    final socket = ref.read(socketServiceProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ───────────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: AppTheme.background,
            surfaceTintColor: Colors.transparent,
            expandedHeight: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(color: AppTheme.background),
            ),
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('RemoteConnect'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                tooltip: 'Add Device',
                onPressed: () => context.push('/pair'),
              ),
              const SizedBox(width: 4),
            ],
          ),

          SliverPadding(
            padding: AppSpacing.pagePadding,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Connection Status Card ─────────────────────────────────
                _buildConnectionCard(context, connection, socket),
                const SizedBox(height: 20),

                // ── Device Stats Grid ──────────────────────────────────────
                if (connection.isConnected && _deviceStatus != null) ...[
                  Text(
                    'System Status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildStatsGrid(),
                  const SizedBox(height: 20),

                  // ── Quick Actions ─────────────────────────────────────────
                  Text('Quick Access', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildQuickActions(context),
                ],

                // ── No Device Card ────────────────────────────────────────
                if (!connection.isConnected && !connection.isConnecting)
                  _buildNoPairCard(context),

                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context, ConnectionState conn, SocketService socket) {
    final isConnected = conn.isConnected;
    final isConnecting = conn.isConnecting;
    final deviceName = _deviceStatus?['deviceName'] ?? 'Unknown Device';
    final ip = (_deviceStatus?['networkInterfaces'] as List?)?.firstOrNull?['address'] ?? '—';
    final tunnelUrl = _deviceStatus?['tunnelUrl'] ?? '';

    return GradientCard(
      gradient: isConnected ? AppGradients.primaryGradient : AppGradients.cardGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isConnected ? Icons.computer_rounded : Icons.computer_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected ? deviceName : 'Not Connected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    StatusBadge(
                      status: isConnected
                          ? 'Online'
                          : isConnecting
                              ? 'Connecting...'
                              : 'Offline',
                      isOnline: isConnected,
                    ),
                  ],
                ),
              ),
              // Connect/Disconnect button
              _buildConnectButton(conn),
            ],
          ),
          if (isConnected) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                _infoChip(Icons.wifi_rounded, ip),
                const SizedBox(width: 8),
                if (tunnelUrl.isNotEmpty)
                  Expanded(
                    child: _infoChip(
                      Icons.cloud_rounded,
                      Uri.tryParse(tunnelUrl)?.host ?? tunnelUrl,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildConnectButton(ConnectionState conn) {
    if (conn.isConnecting) {
      return Container(
        padding: const EdgeInsets.all(8),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      );
    }

    return GestureDetector(
      onTap: conn.isConnected
          ? () => ref.read(connectionProvider.notifier).disconnect()
          : () => context.push('/pair'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white30),
        ),
        child: Text(
          conn.isConnected ? 'Disconnect' : 'Connect',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final status = _deviceStatus!;
    final freeMemMB = ((status['freeMemory'] as int? ?? 0) / 1024 / 1024).round();
    final totalMemMB = ((status['totalMemory'] as int? ?? 1) / 1024 / 1024).round();
    final uptimeH = ((status['uptime'] as int? ?? 0) / 3600).round();
    final cpuCount = status['cpus'] as int? ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.0,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        InfoTile(icon: Icons.memory_rounded, label: 'RAM Free', value: '${freeMemMB}MB'),
        InfoTile(icon: Icons.storage_rounded, label: 'Total RAM', value: '${(totalMemMB / 1024).toStringAsFixed(1)}GB'),
        InfoTile(icon: Icons.timer_rounded, label: 'Uptime', value: '${uptimeH}h'),
        InfoTile(icon: Icons.developer_board_rounded, label: 'CPU Cores', value: '$cpuCount cores'),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(Icons.monitor_rounded, 'Screen', '/screen', AppTheme.primary),
      _QuickAction(Icons.folder_rounded, 'Files', '/files', const Color(0xFF00D4AA)),
      _QuickAction(Icons.content_paste_rounded, 'Clipboard', '/clipboard', const Color(0xFFFFBE0B)),
      _QuickAction(Icons.keyboard_rounded, 'Keyboard', '/keyboard', const Color(0xFFFF6B9D)),
    ];

    return Row(
      children: actions.map((action) {
        return Expanded(
          child: GestureDetector(
            onTap: () => context.go(action.route),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: action.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: action.color.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(action.icon, color: action.color, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    action.label,
                    style: TextStyle(
                      color: action.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildNoPairCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppGradients.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            'No Device Paired',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Install the RemoteConnect desktop agent on your PC and scan the QR code to get started.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.push('/pair'),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Connect to PC'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95));
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String route;
  final Color color;
  const _QuickAction(this.icon, this.label, this.route, this.color);
}
