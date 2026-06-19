import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../shared/services/api_service.dart';
import '../../shared/services/storage_service.dart';
import '../../shared/providers/connection_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isLoading = false;
  List<dynamic> _trustedDevices = [];
  int _fpsSetting = 15;
  String _qualitySetting = 'medium';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchTrustedDevices();
  }

  void _loadSettings() {
    final storage = ref.read(storageServiceProvider);
    setState(() {
      _fpsSetting = storage.getSetting<int>('default_fps', 15);
      _qualitySetting = storage.getSetting<String>('default_quality', 'medium');
    });
  }

  Future<void> _fetchTrustedDevices() async {
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;

    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final devices = await api.getTrustedDevices();
      if (mounted) {
        setState(() {
          _trustedDevices = devices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: const Text('Are you sure you want to untrust this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (decision == true) {
      final api = ref.read(apiServiceProvider);
      setState(() => _isLoading = true);
      try {
        await api.removeDevice(deviceId);
        _fetchTrustedDevices();
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove device: $e')),
        );
      }
    }
  }

  Future<void> _logoutAllDevices() async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke All Sessions'),
        content: const Text('This will disconnect and logout all devices connected to this PC. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (decision == true) {
      final api = ref.read(apiServiceProvider);
      setState(() => _isLoading = true);
      try {
        await api.logoutAll();
        ref.read(connectionProvider.notifier).disconnect();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logged out of all sessions.')),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Action failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _saveFps(int val) async {
    final storage = ref.read(storageServiceProvider);
    await storage.saveSetting('default_fps', val);
    setState(() => _fpsSetting = val);
  }

  Future<void> _saveQuality(String val) async {
    final storage = ref.read(storageServiceProvider);
    await storage.saveSetting('default_quality', val);
    setState(() => _qualitySetting = val);
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section 1: Stream Quality Preferences ────────────────────────
            Text('Streaming Preferences', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildPreferenceCard(),
            const SizedBox(height: 24),

            // ── Section 2: Security & Devices ───────────────────────────────
            if (connection.isConnected) ...[
              Text('Security & Trusted Devices', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildTrustedDevicesCard(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _logoutAllDevices,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Logout All Devices'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ] else
              _buildNotConnectedInfo(),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.speed_rounded, color: AppTheme.primary),
            title: const Text('Default Stream FPS'),
            subtitle: const Text('Choose default frame rate target'),
            trailing: DropdownButton<int>(
              value: _fpsSetting,
              dropdownColor: AppTheme.surfaceVariant,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 FPS')),
                DropdownMenuItem(value: 30, child: Text('30 FPS')),
                DropdownMenuItem(value: 60, child: Text('60 FPS')),
              ],
              onChanged: (val) {
                if (val != null) _saveFps(val);
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.hd_rounded, color: AppTheme.primary),
            title: const Text('Default Quality'),
            subtitle: const Text('Balance between quality and bandwidth'),
            trailing: DropdownButton<String>(
              value: _qualitySetting,
              dropdownColor: AppTheme.surfaceVariant,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('LOW (480p)')),
                DropdownMenuItem(value: 'medium', child: Text('MED (720p)')),
                DropdownMenuItem(value: 'high', child: Text('HIGH (1080p)')),
              ],
              onChanged: (val) {
                if (val != null) _saveQuality(val);
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildTrustedDevicesCard() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, color: AppTheme.secondary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Devices Registered to PC',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    onPressed: _fetchTrustedDevices,
                  )
              ],
            ),
          ),
          const Divider(),
          if (_trustedDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No other devices registered',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _trustedDevices.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, idx) {
                final device = _trustedDevices[idx];
                final isAndroid = device['platform'] == 'android';
                return ListTile(
                  leading: Icon(
                    isAndroid ? Icons.phone_android_rounded : Icons.laptop_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  title: Text(device['deviceName'] ?? 'Unknown Phone'),
                  subtitle: Text(
                    'Paired: ${device['pairedAt']?.split('T')?.first ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                    onPressed: () => _removeDevice(device['deviceId']),
                  ),
                );
              },
            ),
        ],
      ),
    ).animate().fadeIn(duration: 450.ms);
  }

  Widget _buildNotConnectedInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: AppTheme.textMuted, size: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security Settings Unavailable',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
                SizedBox(height: 4),
                Text(
                  'Connect to a computer to view its active sessions and pairing database.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
