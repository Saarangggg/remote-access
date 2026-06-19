import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme.dart';
import '../../shared/providers/connection_provider.dart';
import '../../shared/services/api_service.dart';

class ScreenViewScreen extends ConsumerStatefulWidget {
  const ScreenViewScreen({super.key});

  @override
  ConsumerState<ScreenViewScreen> createState() => _ScreenViewScreenState();
}

class _ScreenViewScreenState extends ConsumerState<ScreenViewScreen> {
  Uint8List? _frameBytes;
  StreamSubscription? _frameSub;
  bool _isStreaming = false;
  int _fps = 15;
  String _quality = 'medium';
  int _frameCount = 0;
  DateTime? _lastFpsTime;
  double _actualFps = 0;

  // Screen size info from server
  double _remoteWidth = 1920;
  double _remoteHeight = 1080;

  // Touch drag state
  Offset? _lastDragPosition;

  // Touch cursor visual overlay
  Offset? _touchCursorPos;
  bool _isTouchActive = false;
  bool _showTapRipple = false;
  Offset? _tapRipplePos;
  Timer? _touchHideTimer;
  Timer? _rippleTimer;

  // Direct typing and screenshot support
  final _textFocusNode = FocusNode();
  final _textController = TextEditingController();

  // Modifier and collapsed state controls
  bool _ctrlActive = false;
  bool _altActive = false;
  bool _shiftActive = false;
  bool _metaActive = false;
  bool _isControlPanelExpanded = false;

  // Multi-Monitor and Coexistence states
  int _monitorIndex = 0;
  String _coexistMode = 'off'; // 'off', 'restore', 'independent'
  List<dynamic> _displays = [];
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.touch;

  @override
  void initState() {
    super.initState();
    _textController.text = ' ';
    _startStream();
    _loadDisplays();
  }

  Future<void> _loadDisplays() async {
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;
    try {
      final api = ref.read(apiServiceProvider);
      final displays = await api.getDisplays();
      if (mounted) {
        setState(() {
          _displays = displays;
          if (_displays.isNotEmpty && _monitorIndex < _displays.length) {
            final disp = _displays[_monitorIndex];
            _remoteWidth = (disp['width'] as num?)?.toDouble() ?? 1920;
            _remoteHeight = (disp['height'] as num?)?.toDouble() ?? 1080;
          }
        });
      }
    } catch (e) {
      // Ignore displays scan errors
    }
  }

  void _startStream() {
    final socket = ref.read(socketServiceProvider);
    _frameSub?.cancel();
    _frameSub = socket.onScreenFrame.listen((base64Frame) {
      if (!mounted) return;
      setState(() {
        _frameBytes = base64Decode(base64Frame);
        _frameCount++;
        _updateFps();
      });
    });
    socket.startScreenStream(fps: _fps, quality: _quality, monitorIndex: _monitorIndex);
    setState(() => _isStreaming = true);
  }

  void _stopStream() {
    final socket = ref.read(socketServiceProvider);
    socket.stopScreenStream();
    _frameSub?.cancel();
    setState(() {
      _isStreaming = false;
      _frameBytes = null;
    });
  }

  void _updateFps() {
    final now = DateTime.now();
    if (_lastFpsTime == null) {
      _lastFpsTime = now;
      return;
    }
    final elapsed = now.difference(_lastFpsTime!).inMilliseconds;
    if (elapsed >= 1000) {
      setState(() {
        _actualFps = _frameCount / (elapsed / 1000);
        _frameCount = 0;
        _lastFpsTime = now;
      });
    }
  }

  // Save screenshot locally
  Future<void> _takeScreenshot() async {
    if (_frameBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No screen frame received yet.')),
      );
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/RC_Screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(path);
      await file.writeAsBytes(_frameBytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screenshot saved to temp: $path'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => OpenFilex.open(path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture screenshot: $e')),
        );
      }
    }
  }

  // Map touch position to desktop coordinates
  Map<String, dynamic> _touchToDesktop(Offset local, Size widgetSize) {
    final rw = _remoteWidth;
    final rh = _remoteHeight;
    final lw = widgetSize.width;
    final lh = widgetSize.height;

    if (rw <= 0 || rh <= 0 || lw <= 0 || lh <= 0) {
      return {'x': 0, 'y': 0};
    }

    final scale = (lw / rw < lh / rh) ? (lw / rw) : (lh / rh);
    final iw = rw * scale;
    final ih = rh * scale;

    final dx = (lw - iw) / 2.0;
    final dy = (lh - ih) / 2.0;

    double touchX = local.dx - dx;
    double touchY = local.dy - dy;

    // Clamp coordinates to image boundaries
    touchX = touchX.clamp(0.0, iw);
    touchY = touchY.clamp(0.0, ih);

    final rx = (touchX / iw) * rw;
    final ry = (touchY / ih) * rh;

    return {
      'x': rx.round(),
      'y': ry.round(),
    };
  }

  void _sendText(String text) {
    if (text.isEmpty) return;
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;

    final modifiers = <String>[];
    if (_ctrlActive) modifiers.add('ctrl');
    if (_altActive) modifiers.add('alt');
    if (_shiftActive) modifiers.add('shift');
    if (_metaActive) modifiers.add('meta');

    final socket = ref.read(socketServiceProvider);
    if (modifiers.isNotEmpty) {
      socket.sendKeyEvent({
        'key': text,
        'modifiers': modifiers,
        'coexistMode': _coexistMode,
      });
      setState(() {
        _ctrlActive = false;
        _altActive = false;
        _shiftActive = false;
        _metaActive = false;
      });
    } else {
      socket.sendKeyEvent({
        'text': text,
        'coexistMode': _coexistMode,
      });
    }
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
      'coexistMode': _coexistMode,
    });

    setState(() {
      _ctrlActive = false;
      _altActive = false;
      _shiftActive = false;
      _metaActive = false;
    });
  }

  // Dynamic Apps List & Search Launcher Dialog
  void _showAppLauncher() {
    List<dynamic> allApps = [];
    List<dynamic> filteredApps = [];
    bool loading = true;
    String searchQ = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Lazy load apps
            if (loading && allApps.isEmpty) {
              final api = ref.read(apiServiceProvider);
              api.getInstalledApps().then((apps) {
                setModalState(() {
                  allApps = apps;
                  filteredApps = apps;
                  loading = false;
                });
              }).catchError((err) {
                setModalState(() {
                  loading = false;
                });
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Launch Host Application',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Search Input
                  TextField(
                    autofocus: false,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search installed apps...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                      fillColor: AppTheme.surfaceVariant,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchQ = val;
                        filteredApps = allApps
                            .where((app) => (app['name'] as String).toLowerCase().contains(val.toLowerCase()))
                            .toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Applications Scroller
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredApps.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.apps_outage_rounded, size: 48, color: AppTheme.textMuted),
                                    const SizedBox(height: 8),
                                    Text(
                                      searchQ.isEmpty ? 'No applications found' : 'No matching apps for "$searchQ"',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredApps.length,
                                itemBuilder: (context, index) {
                                  final app = filteredApps[index];
                                  final name = app['name'] as String;
                                  final path = app['path'] as String;
                                  return Card(
                                    color: AppTheme.surfaceVariant,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: AppTheme.surface,
                                        child: Icon(Icons.launch_rounded, color: AppTheme.primary, size: 18),
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
                                      ),
                                      subtitle: Text(
                                        path.split('/').last,
                                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _launchApp(command: path);
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                  
                  const SizedBox(height: 12),
                  const Divider(color: AppTheme.border, height: 1),
                  const SizedBox(height: 12),
                  
                  // Custom Command
                  const Text(
                    'Run Custom Command / Executable Path:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'e.g., cmd /c notepad.exe',
                            hintStyle: const TextStyle(color: AppTheme.textMuted),
                            fillColor: AppTheme.surfaceVariant,
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (val) {
                            final cmd = val.trim();
                            if (cmd.isNotEmpty) {
                              Navigator.pop(context);
                              _launchApp(command: cmd);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _launchApp({String? appName, String? command}) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.openApp(appName: appName, command: command);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Launched ${appName ?? command} successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch application: $e')),
        );
      }
    }
  }

  void _showTouchAt(Offset pos) {
    _touchHideTimer?.cancel();
    setState(() {
      _touchCursorPos = pos;
      _isTouchActive = true;
    });
  }

  void _hideTouchCursor({Duration delay = const Duration(milliseconds: 120)}) {
    _touchHideTimer?.cancel();
    _touchHideTimer = Timer(delay, () {
      if (mounted) setState(() => _isTouchActive = false);
    });
  }

  void _triggerTapRipple(Offset pos) {
    _rippleTimer?.cancel();
    setState(() {
      _tapRipplePos = pos;
      _showTapRipple = true;
    });
    _rippleTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showTapRipple = false);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _stopStream();
    _textFocusNode.dispose();
    _textController.dispose();
    _touchHideTimer?.cancel();
    _rippleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Handle status bar and navigation bar overlays in landscape dynamically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (isLandscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isLandscape ? null : AppBar(
        backgroundColor: Colors.black,
        title: Row(
          children: [
            const Text('Screen'),
            const SizedBox(width: 12),
            if (_isStreaming)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.online.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.online.withOpacity(0.5)),
                ),
                child: Text(
                  '${_actualFps.toStringAsFixed(0)} FPS',
                  style: const TextStyle(color: AppTheme.online, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        actions: [
          // Switch Monitor dropdown (Always enabled, showing at least 2 monitors)
          PopupMenuButton<int>(
            icon: const Icon(Icons.monitor_rounded, color: AppTheme.textSecondary),
            tooltip: 'Switch Monitor',
            initialValue: _monitorIndex,
            onSelected: (idx) {
              setState(() {
                _monitorIndex = idx;
                if (_displays.isNotEmpty && idx < _displays.length) {
                  final disp = _displays[idx];
                  _remoteWidth = (disp['width'] as num?)?.toDouble() ?? 1920;
                  _remoteHeight = (disp['height'] as num?)?.toDouble() ?? 1080;
                }
              });
              _stopStream();
              _startStream();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Streaming Monitor ${idx + 1}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            itemBuilder: (_) {
              final list = <PopupMenuEntry<int>>[];
              if (_displays.isNotEmpty) {
                for (final d in _displays) {
                  list.add(PopupMenuItem<int>(
                    value: d['index'] as int,
                    child: Text(d['name'] as String),
                  ));
                }
              }
              if (list.length < 2) {
                list.clear();
                list.add(const PopupMenuItem<int>(
                  value: 0,
                  child: Text('Monitor 1 (Primary)'),
                ));
                list.add(const PopupMenuItem<int>(
                  value: 1,
                  child: Text('Monitor 2 (Secondary)'),
                ));
              }
              return list;
            },
          ),
          // Quality picker
          PopupMenuButton<String>(
            icon: const Icon(Icons.hd_rounded, color: AppTheme.textSecondary),
            onSelected: (q) {
              setState(() => _quality = q);
              if (_isStreaming) { _stopStream(); _startStream(); }
            },
            itemBuilder: (_) => ['low', 'medium', 'high']
                .map((q) => PopupMenuItem(value: q, child: Text(q.toUpperCase())))
                .toList(),
          ),
          // FPS picker
          PopupMenuButton<int>(
            icon: const Icon(Icons.speed_rounded, color: AppTheme.textSecondary),
            onSelected: (f) {
              setState(() => _fps = f);
              if (_isStreaming) { _stopStream(); _startStream(); }
            },
            itemBuilder: (_) => [15, 30, 60]
                .map((f) => PopupMenuItem(value: f, child: Text('$f FPS')))
                .toList(),
          ),
          // Start/Stop
          IconButton(
            icon: Icon(
              _isStreaming ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
              color: _isStreaming ? AppTheme.error : AppTheme.primary,
            ),
            onPressed: connection.isConnected
                ? (_isStreaming ? _stopStream : _startStream)
                : null,
          ),
        ],
      ),
      floatingActionButton: isLandscape ? _buildLandscapeFAB() : null,
      body: !connection.isConnected
          ? _buildNotConnected()
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      _buildScreenView(context),
                      // Invisible text field to request focus and intercept keystrokes
                      Positioned(
                        left: -100,
                        top: -100,
                        width: 1,
                        height: 1,
                        child: TextField(
                          focusNode: _textFocusNode,
                          controller: _textController,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          onChanged: (text) {
                            if (text.length > 1) {
                              final typedChar = text.substring(1);
                              if (typedChar == '\n') {
                                _sendKey('Enter');
                              } else {
                                _sendText(typedChar);
                              }
                            } else if (text.isEmpty) {
                              _sendKey('Backspace');
                            }
                            _textController.value = const TextEditingValue(
                              text: ' ',
                              selection: TextSelection.collapsed(offset: 1),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLandscape) _buildBottomControlBar(),
              ],
            ),
    );
  }

  Widget _buildNotConnected() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_rounded, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text('Not connected', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('Connect to a device from the Dashboard', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildScreenView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: Listener(
            onPointerDown: (event) {
              _lastPointerKind = event.kind;
              if (event.kind == PointerDeviceKind.mouse) {
                final buttons = event.buttons;
                String btn = 'left';
                if ((buttons & 2) != 0) {
                  btn = 'right';
                } else if ((buttons & 4) != 0) {
                  btn = 'middle';
                }
                _sendMouseRawButton(event.localPosition, size, 'down', btn);
              } else {
                // Touch down — show cursor
                _showTouchAt(event.localPosition);
              }
            },
            onPointerMove: (event) {
              _lastPointerKind = event.kind;
              if (event.kind == PointerDeviceKind.mouse) {
                _sendMouseRaw(event.localPosition, size, 'move');
              } else {
                // Touch move — update cursor position
                _showTouchAt(event.localPosition);
              }
            },
            onPointerHover: (event) {
              _lastPointerKind = event.kind;
              if (event.kind == PointerDeviceKind.mouse) {
                _sendMouseRaw(event.localPosition, size, 'move');
              }
            },
            onPointerUp: (event) {
              _lastPointerKind = event.kind;
              if (event.kind == PointerDeviceKind.mouse) {
                final buttons = event.buttons;
                String btn = 'left';
                if ((buttons & 2) != 0) {
                  btn = 'right';
                } else if ((buttons & 4) != 0) {
                  btn = 'middle';
                }
                _sendMouseRawButton(event.localPosition, size, 'up', btn);
              } else {
                // Touch up — hide cursor
                _hideTouchCursor();
              }
            },
            onPointerCancel: (event) {
              if (event.kind != PointerDeviceKind.mouse) {
                _hideTouchCursor();
              }
            },
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.kind == PointerDeviceKind.mouse) {
                final socket = ref.read(socketServiceProvider);
                socket.sendMouseEvent({
                  'type': 'scroll',
                  'scrollDelta': {
                    'dx': event.scrollDelta.dx > 0 ? 1 : (event.scrollDelta.dx < 0 ? -1 : 0),
                    'dy': event.scrollDelta.dy > 0 ? 3 : (event.scrollDelta.dy < 0 ? -3 : 0),
                  },
                  'monitorIndex': _monitorIndex,
                  'coexistMode': _coexistMode,
                });
              }
            },
            child: GestureDetector(
              onTapDown: (d) {
                if (_lastPointerKind != PointerDeviceKind.mouse) {
                  _triggerTapRipple(d.localPosition);
                  _sendMouse(d.localPosition, size, 'click');
                }
              },
              onDoubleTapDown: (d) {
                if (_lastPointerKind != PointerDeviceKind.mouse) {
                  _triggerTapRipple(d.localPosition);
                  _sendMouse(d.localPosition, size, 'dblclick');
                }
              },
              onLongPressStart: (d) {
                if (_lastPointerKind != PointerDeviceKind.mouse) {
                  _triggerTapRipple(d.localPosition);
                  _sendMouse(d.localPosition, size, 'rclick');
                }
              },
              onScaleStart: (d) {
                if (_lastPointerKind != PointerDeviceKind.mouse) {
                  _lastDragPosition = d.localFocalPoint;
                  _showTouchAt(d.localFocalPoint);
                  _sendMouseRaw(d.localFocalPoint, size, 'down');
                }
              },
              onScaleUpdate: (d) {
                if (_lastPointerKind != PointerDeviceKind.mouse) {
                  if (d.pointerCount == 1) {
                    _showTouchAt(d.localFocalPoint);
                    _sendMouseRaw(d.localFocalPoint, size, 'move');
                    _lastDragPosition = d.localFocalPoint;
                  } else if (d.pointerCount == 2) {
                    final socket = ref.read(socketServiceProvider);
                    socket.sendMouseEvent({
                      'type': 'scroll',
                      'scrollDelta': {
                        'dx': 0,
                        'dy': d.focalPointDelta.dy > 0 ? 3 : -3,
                      },
                    });
                  }
                }
              },
              onScaleEnd: (_) {
                if (_lastPointerKind != PointerDeviceKind.mouse) {
                  if (_lastDragPosition != null) {
                    _sendMouseRaw(_lastDragPosition!, size, 'up');
                  }
                  _lastDragPosition = null;
                  _hideTouchCursor();
                }
              },
              child: Stack(
                children: [
                  // Screen content
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: _frameBytes == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(color: AppTheme.primary),
                                const SizedBox(height: 16),
                                Text(
                                  _isStreaming ? 'Waiting for frames...' : 'Press play to start',
                                  style: const TextStyle(color: AppTheme.textSecondary),
                                ),
                              ],
                            )
                          : Image.memory(
                              _frameBytes!,
                              fit: BoxFit.contain,
                              width: size.width,
                              height: size.height,
                              gaplessPlayback: true,
                            ),
                    ),
                  ),
                  // Touch cursor overlay
                  if (_touchCursorPos != null)
                    _buildTouchCursorOverlay(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTouchCursorOverlay() {
    final pos = _touchCursorPos!;
    const cursorSize = 28.0;
    const rippleSize = 56.0;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Moving cursor dot
            AnimatedPositioned(
              duration: const Duration(milliseconds: 16),
              left: pos.dx - cursorSize / 2,
              top: pos.dy - cursorSize / 2,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _isTouchActive ? 1.0 : 0.0,
                child: Container(
                  width: cursorSize,
                  height: cursorSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.25),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.9),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mouse_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
            // Tap ripple
            if (_showTapRipple && _tapRipplePos != null)
              Positioned(
                left: _tapRipplePos!.dx - rippleSize / 2,
                top: _tapRipplePos!.dy - rippleSize / 2,
                child: _TapRipple(size: rippleSize),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControlBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle / collapsed basic toolbar
            GestureDetector(
              onTap: () {
                setState(() {
                  _isControlPanelExpanded = !_isControlPanelExpanded;
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Quick Action Buttons
                    Row(
                      children: [
                        // Soft Keyboard Trigger
                        _buildQuickActionBtn(
                          icon: Icons.keyboard_alt_rounded,
                          tooltip: 'Keyboard',
                          onPressed: () {
                            if (!_textFocusNode.hasFocus) {
                              _textFocusNode.requestFocus();
                            } else {
                              _textFocusNode.unfocus();
                            }
                          },
                          color: _textFocusNode.hasFocus ? AppTheme.primary : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        // Screenshot Button
                        _buildQuickActionBtn(
                          icon: Icons.screenshot_rounded,
                          tooltip: 'Screenshot',
                          onPressed: _takeScreenshot,
                        ),
                        const SizedBox(width: 12),
                        // App launcher button
                        _buildQuickActionBtn(
                          icon: Icons.apps_rounded,
                          tooltip: 'Launch App',
                          onPressed: _showAppLauncher,
                        ),
                        const SizedBox(width: 12),
                        // Coexist Mode Button (Cycles through: Off -> Restore -> Independent)
                        _buildQuickActionBtn(
                          icon: _coexistMode == 'independent'
                              ? Icons.people_outline_rounded
                              : (_coexistMode == 'restore' ? Icons.people_rounded : Icons.person_rounded),
                          tooltip: _coexistMode == 'independent'
                              ? 'Coexist: Independent Seat Mode'
                              : (_coexistMode == 'restore' ? 'Coexist: Cursor Return Mode' : 'Single User Mode'),
                          onPressed: () {
                            setState(() {
                              if (_coexistMode == 'off') {
                                _coexistMode = 'restore';
                              } else if (_coexistMode == 'restore') {
                                _coexistMode = 'independent';
                              } else {
                                _coexistMode = 'off';
                              }
                            });
                            String modeText = _coexistMode == 'independent'
                                ? 'Independent (2 Mice, 2 Keyboards)'
                                : (_coexistMode == 'restore' ? 'Cursor Return (Coexist)' : 'Off (Single User)');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Coexist Mode: $modeText'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          color: _coexistMode == 'independent'
                              ? AppTheme.primary
                              : (_coexistMode == 'restore' ? AppTheme.secondary : AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    // Expand/Collapse Indicator
                    Row(
                      children: [
                        Text(
                          _isControlPanelExpanded ? 'Hide Controls' : 'Show Controls',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isControlPanelExpanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Expanded Modifier & Keys grid
            if (_isControlPanelExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    const Divider(color: AppTheme.border, height: 1),
                    const SizedBox(height: 12),
                    
                    // Modifiers Row
                    Row(
                      children: [
                        _modifierKey('CTRL', _ctrlActive, () => setState(() => _ctrlActive = !_ctrlActive)),
                        _modifierKey('ALT', _altActive, () => setState(() => _altActive = !_altActive)),
                        _modifierKey('SHIFT', _shiftActive, () => setState(() => _shiftActive = !_shiftActive)),
                        _modifierKey('WIN', _metaActive, () => setState(() => _metaActive = !_metaActive)),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Utility Keys Row
                    Row(
                      children: [
                        _actionKey('Esc', () => _sendKey('Escape')),
                        _actionKey('Tab', () => _sendKey('Tab')),
                        _actionKey('Bksp', () => _sendKey('Backspace'), flex: 2, icon: Icons.backspace_outlined),
                        _actionKey('Enter', () => _sendKey('Enter'), flex: 2, icon: Icons.keyboard_return_rounded),
                        _actionKey('Space', () => _sendKey('Space'), flex: 2, icon: Icons.space_bar_rounded),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Navigation/Arrow Pad & Quick Shortcuts split view
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left side: Quick Shortcuts
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 6),
                                child: Text(
                                  'QUICK SHORTCUTS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textMuted,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  _shortcutBtn('Copy', () {
                                    final socket = ref.read(socketServiceProvider);
                                    socket.sendMouseEvent({
                                      'type': 'key',
                                      'key': 'c',
                                      'modifiers': ['ctrl'],
                                      'monitorIndex': _monitorIndex,
                                      'coexistMode': _coexistMode,
                                    });
                                  }),
                                  const SizedBox(width: 6),
                                  _shortcutBtn('Paste', () {
                                    final socket = ref.read(socketServiceProvider);
                                    socket.sendMouseEvent({
                                      'type': 'key',
                                      'key': 'v',
                                      'modifiers': ['ctrl'],
                                      'monitorIndex': _monitorIndex,
                                      'coexistMode': _coexistMode,
                                    });
                                  }),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _shortcutBtn('Sel All', () {
                                    final socket = ref.read(socketServiceProvider);
                                    socket.sendMouseEvent({
                                      'type': 'key',
                                      'key': 'a',
                                      'modifiers': ['ctrl'],
                                      'monitorIndex': _monitorIndex,
                                      'coexistMode': _coexistMode,
                                    });
                                  }),
                                  const SizedBox(width: 6),
                                  _shortcutBtn('Show DT', () {
                                    final socket = ref.read(socketServiceProvider);
                                    socket.sendMouseEvent({
                                      'type': 'key',
                                      'key': 'd',
                                      'modifiers': ['meta'],
                                      'monitorIndex': _monitorIndex,
                                      'coexistMode': _coexistMode,
                                    });
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 16),
                        
                        // Right side: Arrows D-Pad
                        Expanded(
                          flex: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _arrowBtn(Icons.arrow_upward_rounded, () => _sendKey('ArrowUp')),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _arrowBtn(Icons.arrow_back_rounded, () => _sendKey('ArrowLeft')),
                                    const SizedBox(width: 24, height: 24),
                                    _arrowBtn(Icons.arrow_forward_rounded, () => _sendKey('ArrowRight')),
                                  ],
                                ),
                                _arrowBtn(Icons.arrow_downward_rounded, () => _sendKey('ArrowDown')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(8),
            color: color != null ? color.withOpacity(0.08) : AppTheme.surfaceVariant,
          ),
          child: Icon(
            icon,
            size: 20,
            color: color ?? AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _modifierKey(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 2),
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
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(String label, VoidCallback onTap, {int flex = 1, IconData? icon}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppTheme.textPrimary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcutBtn(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withOpacity(0.08),
                AppTheme.primary.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrowBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(
          icon,
          size: 18,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildLandscapeFAB() {
    return FloatingActionButton(
      backgroundColor: Colors.black.withOpacity(0.6),
      foregroundColor: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: Colors.white30, width: 1)),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppTheme.surface.withOpacity(0.9),
          barrierColor: Colors.black12,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Landscape Controls',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _landscapeOption(
                        icon: Icons.keyboard_alt_rounded,
                        label: 'Keyboard',
                        onTap: () {
                          Navigator.pop(context);
                          _textFocusNode.requestFocus();
                        },
                      ),
                      _landscapeOption(
                        icon: Icons.screenshot_rounded,
                        label: 'Screenshot',
                        onTap: () {
                          Navigator.pop(context);
                          _takeScreenshot();
                        },
                      ),
                      _landscapeOption(
                        icon: Icons.apps_rounded,
                        label: 'Apps',
                        onTap: () {
                          Navigator.pop(context);
                          _showAppLauncher();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _landscapeOption(
                        icon: Icons.monitor_rounded,
                        label: 'Monitor (${_monitorIndex + 1})',
                        onTap: () {
                          Navigator.pop(context);
                          final totalMonitors = _displays.length > 1 ? _displays.length : 2;
                          final nextIndex = (_monitorIndex + 1) % totalMonitors;
                          setState(() {
                            _monitorIndex = nextIndex;
                            if (_displays.isNotEmpty && nextIndex < _displays.length) {
                              final disp = _displays[nextIndex];
                              _remoteWidth = (disp['width'] as num?)?.toDouble() ?? 1920;
                              _remoteHeight = (disp['height'] as num?)?.toDouble() ?? 1080;
                            }
                          });
                          _stopStream();
                          _startStream();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Switched to Monitor ${nextIndex + 1}'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      _landscapeOption(
                        icon: _coexistMode == 'independent'
                            ? Icons.people_outline_rounded
                            : (_coexistMode == 'restore' ? Icons.people_rounded : Icons.person_rounded),
                        label: _coexistMode == 'independent'
                            ? 'Independent'
                            : (_coexistMode == 'restore' ? 'Coexist ON' : 'Coexist OFF'),
                        color: _coexistMode == 'independent'
                            ? AppTheme.primary
                            : (_coexistMode == 'restore' ? AppTheme.secondary : AppTheme.textSecondary),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            if (_coexistMode == 'off') {
                              _coexistMode = 'restore';
                            } else if (_coexistMode == 'restore') {
                              _coexistMode = 'independent';
                            } else {
                              _coexistMode = 'off';
                            }
                          });
                          String modeText = _coexistMode == 'independent'
                              ? 'Independent (2 Mice, 2 Keyboards)'
                              : (_coexistMode == 'restore' ? 'Cursor Return (Coexist)' : 'Off (Single User)');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Coexist Mode: $modeText'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
      child: const Icon(Icons.settings_suggest_rounded, size: 24),
    );
  }

  Widget _landscapeOption({required IconData icon, required String label, required VoidCallback onTap, Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(icon, color: color ?? AppTheme.primary, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMouse(Offset pos, Size size, String type) {
    final desktop = _touchToDesktop(pos, size);
    final socket = ref.read(socketServiceProvider);
    socket.sendMouseEvent({
      'type': type,
      ...desktop,
      'monitorIndex': _monitorIndex,
      'coexistMode': _coexistMode,
    });
  }

  void _sendMouseRaw(Offset pos, Size size, String type) {
    final desktop = _touchToDesktop(pos, size);
    final socket = ref.read(socketServiceProvider);
    socket.sendMouseEvent({
      'type': type,
      ...desktop,
      'button': 'left',
      'monitorIndex': _monitorIndex,
      'coexistMode': _coexistMode,
    });
  }

  void _sendMouseRawButton(Offset pos, Size size, String type, String button) {
    final desktop = _touchToDesktop(pos, size);
    final socket = ref.read(socketServiceProvider);
    socket.sendMouseEvent({
      'type': type,
      ...desktop,
      'button': button,
      'monitorIndex': _monitorIndex,
      'coexistMode': _coexistMode,
    });
  }
}

/// Animated tap ripple indicator — expands and fades on tap/click
class _TapRipple extends StatefulWidget {
  final double size;
  const _TapRipple({required this.size});

  @override
  State<_TapRipple> createState() => _TapRippleState();
}

class _TapRippleState extends State<_TapRipple> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _scaleAnim = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.85, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Opacity(
          opacity: _opacityAnim.value,
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.9),
                  width: 2.5,
                ),
                color: AppTheme.primary.withOpacity(0.15),
              ),
            ),
          ),
        );
      },
    );
  }
}
