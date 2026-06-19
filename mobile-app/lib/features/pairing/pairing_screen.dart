import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../shared/services/api_service.dart';
import '../../shared/services/storage_service.dart';
import '../../shared/providers/connection_provider.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(
    text: const String.fromEnvironment('DEFAULT_URL',  defaultValue: 'https://your-domain.com' ),
  );
  final _usernameController = TextEditingController(
    text: const String.fromEnvironment('DEFAULT_USER', defaultValue: 'Admin'),
  );
  final _passwordController = TextEditingController(
    text: const String.fromEnvironment('DEFAULT_PASSWORD', defaultValue: 'Admin'),
  );
  final _nameController = TextEditingController(text: 'My Phone');
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _submitPairing() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final url = _urlController.text.trim().replaceAll(RegExp(r'/$'), ''); // strip trailing slash
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final phoneName = _nameController.text.trim();

    try {
      final api = ref.read(apiServiceProvider);
      final storage = ref.read(storageServiceProvider);
      var phoneId = storage.getSetting<String>('phone_device_id', '');
      if (phoneId.isEmpty) {
        phoneId = const Uuid().v4();
        await storage.saveSetting('phone_device_id', phoneId);
      }

      final res = await api.login(
        username: username,
        password: password,
        deviceId: phoneId,
        deviceName: phoneName,
        baseUrl: url,
      );

      if (res['success'] == true) {
        final config = DeviceConfig(
          deviceId: phoneId,
          deviceName: res['device']['desktopDeviceName'] ?? 'Remote PC',
          baseUrl: url,
          accessToken: res['accessToken'],
          refreshToken: res['refreshToken'],
          pairedAt: DateTime.now(),
        );

        await storage.saveDevice(config);
        await storage.setActiveDevice(phoneId);

        ref.read(apiServiceProvider).configure(url, res['accessToken']);
        await ref.read(connectionProvider.notifier).connect(config);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully authenticated with desktop!')),
          );
          context.go('/dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Login to PC Agent'),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.lock_person_rounded, color: AppTheme.primary, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Private Connection Settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect securely through your domain mapping by providing agent login credentials.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 24),

              // ── Fields ────────────────────────────────────────────────────
              TextFormField(
                controller: _urlController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Desktop URL (Tunnel or IP)',
                  hintText: 'http://192.168.1.100:9678',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'URL is required';
                  if (!val.startsWith('http://') && !val.startsWith('https://')) {
                    return 'URL must start with http:// or https://';
                  }
                  return null;
                },
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 16),

              TextFormField(
                controller: _usernameController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter agent login username',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Username is required';
                  return null;
                },
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                style: const TextStyle(color: AppTheme.textPrimary),
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter agent login password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Password is required';
                  return null;
                },
              ).animate().fadeIn(delay: 250.ms),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Your Phone Display Name',
                  hintText: 'E.g. Pixel 8, iPhone 15',
                  prefixIcon: Icon(Icons.phone_android_rounded),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Phone display name is required';
                  return null;
                },
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitPairing,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: const Text('Login & Connect'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ).animate().fadeIn(delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
