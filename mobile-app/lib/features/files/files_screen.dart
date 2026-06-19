import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../shared/services/api_service.dart';
import '../../shared/providers/connection_provider.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _currentPath = ''; // Empty string means root-level folders
  List<dynamic> _items = [];
  bool _isLoading = false;
  String _searchQuery = '';
  bool _isSearching = false;
  double _transferProgress = 0.0;
  String _transferStatus = '';
  List<dynamic> _shortcuts = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _fetchFiles();
      _fetchShortcuts();
    });
  }

  Future<void> _fetchShortcuts() async {
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.listFiles('');
      final items = res['items'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _shortcuts = items
              .where((item) =>
                  item['type'] == 'directory' &&
                  (item['name'] as String).startsWith('⭐'))
              .toList();
        });
      }
    } catch (e) {
      // Silently fail to load shortcuts
    }
  }

  Future<void> _fetchFiles() async {
    final connection = ref.read(connectionProvider);
    if (!connection.isConnected) return;

    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final res = await api.listFiles(_currentPath);
      if (mounted) {
        setState(() {
          _items = res['items'] as List<dynamic>? ?? [];
          if (_currentPath.isEmpty) {
            _shortcuts = _items
                .where((item) =>
                    item['type'] == 'directory' &&
                    (item['name'] as String).startsWith('⭐'))
                .toList();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading files: $e')),
        );
      }
    }
  }

  void _navigateTo(String targetPath) {
    setState(() {
      _currentPath = targetPath;
      _isSearching = false;
      _searchQuery = '';
    });
    _fetchFiles();
  }

  void _goBack() {
    if (_currentPath.isEmpty || _currentPath == '/') return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _navigateTo(parts.join('/'));
  }

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (decision == true && nameController.text.trim().isNotEmpty) {
      final api = ref.read(apiServiceProvider);
      final fullNewPath = _currentPath.isEmpty
          ? nameController.text.trim()
          : '$_currentPath/${nameController.text.trim()}';

      setState(() => _isLoading = true);
      try {
        await api.createFolder(fullNewPath);
        _fetchFiles();
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create folder: $e')),
        );
      }
    }
  }

  Future<void> _uploadFiles() async {
    if (_currentPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot upload to the roots dashboard. Choose a folder first.')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.paths.isEmpty) return;

    final filePaths = result.paths.whereType<String>().toList();
    final api = ref.read(apiServiceProvider);

    setState(() {
      _transferProgress = 0.05;
      _transferStatus = 'Uploading ${filePaths.length} file(s)...';
    });

    try {
      await api.uploadFiles(
        _currentPath,
        filePaths,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() {
              _transferProgress = sent / total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _transferProgress = 0.0;
          _transferStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Files uploaded successfully!')),
        );
        _fetchFiles();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transferProgress = 0.0;
          _transferStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> item) async {
    final api = ref.read(apiServiceProvider);
    setState(() {
      _transferProgress = 0.1;
      _transferStatus = 'Downloading ${item['name']}...';
    });

    try {
      final res = await api.downloadFile(item['path']);
      final bytes = res.data as List<int>;

      // Save to external storage or app documents
      final dir = await getTemporaryDirectory();
      final localFile = File('${dir.path}/${item['name']}');
      await localFile.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _transferProgress = 0.0;
          _transferStatus = '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to temporary path: ${localFile.path}'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                OpenFilex.open(localFile.path);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transferProgress = 0.0;
          _transferStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete ${item['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (decision == true) {
      final api = ref.read(apiServiceProvider);
      setState(() => _isLoading = true);
      try {
        await api.deleteFile(item['path']);
        _fetchFiles();
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _renameItem(Map<String, dynamic> item) async {
    final nameController = TextEditingController(text: item['name']);
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Item'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rename')),
        ],
      ),
    );

    if (decision == true && nameController.text.trim().isNotEmpty) {
      final api = ref.read(apiServiceProvider);
      setState(() => _isLoading = true);
      try {
        await api.renameFile(item['path'], nameController.text.trim());
        _fetchFiles();
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }
  }

  Future<void> _searchFilesQuery(String q) async {
    if (q.trim().isEmpty) {
      _fetchFiles();
      return;
    }
    final api = ref.read(apiServiceProvider);
    setState(() => _isLoading = true);
    try {
      final res = await api.searchFiles(q, path: _currentPath.isEmpty ? null : _currentPath);
      setState(() {
        _items = res['results'] as List<dynamic>? ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search files...',
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                  _searchFilesQuery(val);
                },
              )
            : Text(_currentPath.isEmpty ? 'Files' : _currentPath.split('/').last),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _fetchFiles();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (_currentPath.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createFolder,
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: _uploadFiles,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchFiles,
          ),
        ],
      ),
      body: !connection.isConnected
          ? _buildNotConnected()
          : Column(
              children: [
                if (_transferProgress > 0) _buildProgressBar(),
                _buildBreadcrumbs(),
                _buildShortcutsBar(),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _fetchFiles,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: _items.length,
                                itemBuilder: (context, idx) {
                                  final item = Map<String, dynamic>.from(_items[idx]);
                                  return _buildFileItem(item);
                                },
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
          Icon(Icons.folder_off_rounded, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text('Not connected', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('Connect to a device to browse files', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      color: AppTheme.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _transferStatus,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _transferProgress,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    if (_currentPath.isEmpty) return const SizedBox.shrink();

    final parts = _currentPath.split('/');
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppTheme.surface,
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          TextButton.icon(
            onPressed: () => _navigateTo(''),
            icon: const Icon(Icons.home_outlined, size: 16),
            label: const Text('Roots & Shortcuts'),
          ),
          for (int i = 0; i < parts.length; i++) ...[
            const Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.textMuted),
            TextButton(
              onPressed: () {
                final target = parts.sublist(0, i + 1).join('/');
                _navigateTo(target);
              },
              child: Text(parts[i]),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open_rounded, size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            _isSearching ? 'No results found' : 'This folder is empty',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(Map<String, dynamic> item) {
    final isDir = item['type'] == 'directory';
    final name = item['name'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isDir ? Icons.folder_rounded : _getFileIcon(name),
          color: isDir ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: isDir
            ? null
            : Text(
                _formatBytes((item['size'] as num?)?.toInt() ?? 0),
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
        onTap: () {
          if (isDir) {
            _navigateTo(item['path'] as String);
          } else {
            _downloadFile(item);
          }
        },
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (val) {
            if (val == 'rename') {
              _renameItem(item);
            } else if (val == 'delete') {
              _deleteItem(item);
            } else if (val == 'download') {
              _downloadFile(item);
            }
          },
          itemBuilder: (ctx) => [
            if (!isDir)
              const PopupMenuItem(value: 'download', child: Text('Download')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.video_file_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'flac':
        return Icons.audio_file_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.archive_rounded;
      case 'txt':
      case 'md':
      case 'json':
      case 'xml':
      case 'csv':
        return Icons.article_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildShortcutsBar() {
    if (_shortcuts.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 48,
      color: AppTheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _shortcuts.length,
        itemBuilder: (context, index) {
          final item = _shortcuts[index];
          final name = (item['name'] as String).replaceFirst('⭐ ', '');
          final isCurrent = _currentPath == item['path'];

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(
                _getShortcutIcon(name),
                size: 14,
                color: isCurrent ? Colors.white : AppTheme.primary,
              ),
              label: Text(name),
              backgroundColor: isCurrent ? AppTheme.primary : AppTheme.surfaceVariant,
              side: BorderSide(color: isCurrent ? AppTheme.primaryLight : AppTheme.border),
              labelStyle: TextStyle(
                fontSize: 11,
                color: isCurrent ? Colors.white : AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
              onPressed: () => _navigateTo(item['path'] as String),
            ),
          );
        },
      ),
    );
  }

  IconData _getShortcutIcon(String name) {
    switch (name.toLowerCase()) {
      case 'desktop':
        return Icons.desktop_windows_rounded;
      case 'downloads':
        return Icons.download_rounded;
      case 'documents':
        return Icons.description_rounded;
      case 'pictures':
        return Icons.image_rounded;
      case 'videos':
        return Icons.video_library_rounded;
      default:
        return Icons.folder_special_rounded;
    }
  }
}
