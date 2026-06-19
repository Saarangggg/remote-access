import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../shared/services/api_service.dart';
import '../../shared/providers/connection_provider.dart';
import '../../shared/widgets/gradient_card.dart';

class ClipboardScreen extends ConsumerStatefulWidget {
  const ClipboardScreen({super.key});

  @override
  ConsumerState<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends ConsumerState<ClipboardScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  bool _autoSync = false;
  StreamSubscription? _socketClipSub;
  Timer? _localClipboardPollTimer;
  String _lastSentText = '';
  String _lastReceivedText = '';

  @override
  void initState() {
    super.initState();
    _fetchDesktopClipboard();
    _listenToSocketClipboard();
    _startLocalClipboardMonitoring();
  }

  // Fetch current desktop clipboard via REST API
  Future<void> _fetchDesktopClipboard() async {
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;

    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final text = await api.getClipboard();
      if (mounted && text.isNotEmpty) {
        setState(() {
          _controller.text = text;
          _lastReceivedText = text;
        });
      }
    } catch (e) {
      debugPrint('Error getting clipboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Subscribe to realtime clipboard changes from desktop
  void _listenToSocketClipboard() {
    final socket = ref.read(socketServiceProvider);
    _socketClipSub = socket.onClipboardUpdate.listen((data) async {
      if (!mounted) return;
      final text = data['text'] as String? ?? '';
      if (text.isNotEmpty && text != _lastSentText) {
        setState(() {
          _controller.text = text;
          _lastReceivedText = text;
        });

        if (_autoSync) {
          await Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Desktop clipboard auto-copied to phone!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  // Periodically check local phone clipboard to push to desktop if autoSync is on
  void _startLocalClipboardMonitoring() {
    _localClipboardPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_autoSync || !mounted) return;
      final connection = ref.read(connectionProvider);
      if (!connection.isConnected) return;

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isNotEmpty && text != _lastSentText && text != _lastReceivedText) {
        _lastSentText = text;
        final socket = ref.read(socketServiceProvider);
        socket.setClipboard(text);
      }
    });
  }

  // Explicitly write phone clipboard content to desktop clipboard
  Future<void> _pushToDesktop() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.setClipboard(text);
      _lastSentText = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pushed to desktop clipboard!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Explicitly copy local text box to phone clipboard
  Future<void> _copyToPhone() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to phone clipboard!')),
      );
    }
  }

  @override
  void dispose() {
    _socketClipSub?.cancel();
    _localClipboardPollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Clipboard Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchDesktopClipboard,
          ),
        ],
      ),
      body: !connection.isConnected
          ? _buildNotConnected()
          : SingleChildScrollView(
              padding: AppSpacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Overview Card ─────────────────────────────────────────
                  _buildControlCard(),
                  const SizedBox(height: 24),

                  // ── Clipboard Content Area ────────────────────────────────
                  Text(
                    'Shared Content',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _controller,
                          maxLines: 8,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Type text here to send, or view synced clipboard history...',
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppTheme.border),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _controller.clear,
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              label: const Text('Clear'),
                              style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: _copyToPhone,
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('Copy to Phone'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : _pushToDesktop,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.arrow_upward_rounded, size: 18),
                              label: const Text('Push to PC'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms),
                ],
              ),
            ),
    );
  }

  Widget _buildNotConnected() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.content_paste_off_rounded, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text('Not connected', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('Connect to a device to sync clipboard', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildControlCard() {
    return GradientCard(
      gradient: AppGradients.cardGradient,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sync_rounded, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto Sync Mode',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Instantly share clipboard between devices in background',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoSync,
                onChanged: (val) {
                  setState(() => _autoSync = val);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
