import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../shared/providers/connection_provider.dart';

class KeyboardScreen extends ConsumerStatefulWidget {
  const KeyboardScreen({super.key});

  @override
  ConsumerState<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends ConsumerState<KeyboardScreen> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  // Active modifiers list
  bool _ctrlActive = false;
  bool _altActive = false;
  bool _shiftActive = false;
  bool _metaActive = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  void _sendKey(String key) {
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;

    final modifiers = <String>[];
    if (_ctrlActive) modifiers.add('ctrl');
    if (_altActive) modifiers.add('alt');
    if (_shiftActive) modifiers.add('shift');
    if (_metaActive) modifiers.add('meta');

    final socket = ref.read(socketServiceProvider);
    socket.sendKeyEvent({
      'key': key,
      'modifiers': modifiers,
    });

    // Reset non-locked modifiers after pressing a non-modifier key
    setState(() {
      _ctrlActive = false;
      _altActive = false;
      _shiftActive = false;
      _metaActive = false;
    });
  }

  void _sendText(String text) {
    if (text.isEmpty) return;
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;

    final socket = ref.read(socketServiceProvider);
    socket.sendKeyEvent({
      'text': text,
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Keyboard Controller'),
      ),
      body: !connection.isConnected
          ? _buildNotConnected()
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: AppSpacing.pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Text Capture Area ───────────────────────────────
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tap below to open phone keyboard & start typing directly onto PC:',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _inputController,
                                    focusNode: _focusNode,
                                    maxLines: null,
                                    keyboardType: TextInputType.multiline,
                                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                                    decoration: const InputDecoration(
                                      hintText: 'Start typing...',
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (text) {
                                      if (text.isNotEmpty) {
                                        _sendText(text.substring(text.length - 1));
                                      }
                                    },
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.keyboard_hide_rounded),
                                      onPressed: () => _focusNode.unfocus(),
                                      tooltip: 'Hide Keyboard',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_sweep_outlined),
                                      onPressed: () => _inputController.clear(),
                                      tooltip: 'Clear History',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Special Keys Row ───────────────────────────────
                        _buildKeyboardOverlay(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNotConnected() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.keyboard_hide_rounded, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text('Not connected', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('Connect to a device to send keystrokes', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildKeyboardOverlay() {
    return Column(
      children: [
        // Modifier Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _modifierKey('CTRL', _ctrlActive, () => setState(() => _ctrlActive = !_ctrlActive)),
            _modifierKey('ALT', _altActive, () => setState(() => _altActive = !_altActive)),
            _modifierKey('SHIFT', _shiftActive, () => setState(() => _shiftActive = !_shiftActive)),
            _modifierKey('WIN', _metaActive, () => setState(() => _metaActive = !_metaActive)),
          ],
        ),
        const SizedBox(height: 10),

        // Navigation & Edit row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _actionKey('Esc', () => _sendKey('Escape')),
            _actionKey('Tab', () => _sendKey('Tab')),
            _actionKey('Backspace', () => _sendKey('Backspace'), flex: 2),
            _actionKey('Enter', () => _sendKey('Enter'), flex: 2),
          ],
        ),
        const SizedBox(height: 10),

        // Directions & Navigation row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _actionKey('Home', () => _sendKey('Home')),
            _actionKey('PgUp', () => _sendKey('PageUp')),
            _actionKey('▲', () => _sendKey('ArrowUp'), color: AppTheme.primary),
            _actionKey('PgDn', () => _sendKey('PageDown')),
            _actionKey('End', () => _sendKey('End')),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _actionKey('Del', () => _sendKey('Delete')),
            _actionKey('◀', () => _sendKey('ArrowLeft'), color: AppTheme.primary),
            _actionKey('▼', () => _sendKey('ArrowDown'), color: AppTheme.primary),
            _actionKey('▶', () => _sendKey('ArrowRight'), color: AppTheme.primary),
            _actionKey('Space', () => _sendKey('Space'), flex: 2),
          ],
        ),
        const SizedBox(height: 10),

        // Function row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(12, (index) {
              final num = index + 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _actionKey('F$num', () => _sendKey('F$num'), width: 54),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _modifierKey(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? AppTheme.primaryLight : AppTheme.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(String label, VoidCallback onTap, {int flex = 1, Color? color, double? width}) {
    final widget = Container(
      height: 44,
      decoration: BoxDecoration(
        color: color?.withOpacity(0.15) ?? AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color?.withOpacity(0.5) ?? AppTheme.border,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color ?? AppTheme.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );

    return width != null
        ? SizedBox(
            width: width,
            child: GestureDetector(onTap: onTap, child: widget),
          )
        : Expanded(
            flex: flex,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(onTap: onTap, child: widget),
            ),
          );
  }
}
