import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../viewmodel/chat_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/session_list_provider.dart';
import '../../../core/providers/usage_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/demo/demo_mode.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/command_palette.dart';
import '../../../shared/widgets/demo_banner.dart';
import '../../../shared/widgets/daemon_offline_banner.dart';
import '../../../shared/widgets/animated_background.dart';
import 'widgets/chat_skeleton.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String cwd;

  const ChatScreen({super.key, required this.sessionId, required this.cwd});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _showScrollButton = false;
  final List<Map<String, String>> _attachments = [];
  late String _title;
  bool _showSkeleton = true;

  @override
  void initState() {
    super.initState();
    _title = _fallbackTitle(widget.cwd);
    _scrollController.addListener(_onScroll);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSkeleton = false);
    });
  }

  String _fallbackTitle(String cwd) {
    if (cwd.isNotEmpty && cwd != '/') {
      final parts = cwd.split('/');
      return parts.lastWhere((p) => p.isNotEmpty, orElse: () => cwd);
    }
    return 'Chat';
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pixels = _scrollController.position.pixels;
    final show = pixels > 160;

    if (show != _showScrollButton) {
      setState(() => _showScrollButton = show);
    }
  }

  static const _imageExts = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'bmp',
    'svg',
  };

  static const _docExts = {
    'pdf',
    'doc',
    'docx',
    'txt',
    'md',
    'csv',
    'json',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'rtf',
    'xml',
    'yaml',
    'yml',
    'html',
    'htm',
  };

  String _mimeForExtension(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'rtf':
        return 'application/rtf';
      case 'xml':
        return 'application/xml';
      case 'yaml':
      case 'yml':
        return 'text/yaml';
      case 'html':
      case 'htm':
        return 'text/html';
      default:
        return 'application/octet-stream';
    }
  }

  bool _isImageExt(String ext) => _imageExts.contains(ext);
  bool _isTextMime(String mime) =>
      mime.startsWith('text/') || mime == 'application/json' || mime == 'application/xml';

  IconData _iconForAttachment(Map<String, String> att) {
    final mime = att['mimeType'] ?? '';
    final name = att['name'] ?? '';
    final ext = name.split('.').last.toLowerCase();
    if (_isImageExt(ext) || mime.startsWith('image/')) return Icons.image_outlined;
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (ext == 'doc' || ext == 'docx') return Icons.description_outlined;
    if (ext == 'xls' || ext == 'xlsx') return Icons.table_chart_outlined;
    if (ext == 'ppt' || ext == 'pptx') return Icons.slideshow_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _showAttachmentOptions() async {
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.photo_outlined, color: theme.colorScheme.primary),
              title: const Text('Photo / Image'),
              subtitle: const Text('JPG, PNG, GIF, WebP'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage();
              },
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined, color: theme.colorScheme.primary),
              title: const Text('Document'),
              subtitle: const Text('PDF, Word, Excel, Text, Markdown, CSV, JSON'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickDocument();
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
              title: const Text('Other file'),
              subtitle: const Text('Any file type'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAnyFile();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      await _handlePickedFiles(result.files);
    } catch (e) {
      debugPrint('[RUNMOTE] image pick error: $e');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _docExts.toList(),
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      await _handlePickedFiles(result.files);
    } catch (e) {
      debugPrint('[RUNMOTE] document pick error: $e');
    }
  }

  Future<void> _pickAnyFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      await _handlePickedFiles(result.files);
    } catch (e) {
      debugPrint('[RUNMOTE] any file pick error: $e');
    }
  }

  Future<void> _handlePickedFiles(List<PlatformFile> files) async {
    const maxBytes = 10 * 1024 * 1024; // 10 MB per file
    for (final file in files) {
      final bytes = file.bytes ?? (await _readFile(file.path));
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not read ${file.name}')),
          );
        }
        continue;
      }
      if (bytes.length > maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.name} is too large (>10 MB)')),
          );
        }
        continue;
      }
      final ext = (file.extension ?? file.name.split('.').last).toLowerCase();
      final mime = _mimeForExtension(ext);

      // For text-like resources, also store decoded text for embeddedContext.
      String? decodedText;
      if (_isTextMime(mime)) {
        try {
          decodedText = utf8.decode(bytes);
          // Sanity: if decoded text is mostly non-printable, treat as binary.
          if (decodedText.length > 200000) {
            decodedText = decodedText.substring(0, 200000);
          }
        } catch (_) {
          decodedText = null;
        }
      }

      setState(() {
        _attachments.add({
          'name': file.name,
          'mimeType': mime,
          'data': base64Encode(bytes),
          if (decodedText != null) 'text': decodedText,
          'kind': _isImageExt(ext) ? 'image' : 'resource',
          'ext': ext,
        });
      });
    }
  }

  Future<Uint8List?> _readFile(String? path) async {
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    HapticFeedback.lightImpact();
    _textController.clear();
    // Demo mode: don't actually send, show CTA
    final isDemoSend = ref.read(demoModeProvider) && demoSessionIds.contains(widget.sessionId);
    if (isDemoSend) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Demo mode – Pair your daemon to chat with real agents'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Pair now',
              onPressed: () {
                ref.read(demoModeProvider.notifier).state = false;
                context.go('/');
              },
            ),
          ),
        );
      }
      if (_attachments.isNotEmpty) setState(() => _attachments.clear());
      return;
    }

    List<Map<String, dynamic>>? extra;
    if (_attachments.isNotEmpty) {
      extra = _attachments.map((a) {
        final kind = a['kind'] ?? 'image';
        final mime = a['mimeType'] ?? 'application/octet-stream';
        final name = a['name'] ?? 'file';
        final data = a['data'] ?? '';
        final decodedText = a['text'];

        if (kind == 'image') {
          return <String, dynamic>{
            'type': 'image',
            'data': data,
            'mimeType': mime,
            if (name.isNotEmpty) 'uri': 'file:///$name',
          };
        }

        // Document / generic file -> ACP resource block.
        // Text-like: use {resource: {uri, mimeType, text}}
        // Binary:  use {resource: {uri, mimeType, blob}} + top-level mimeType/data for compat.
        if (decodedText != null) {
          return <String, dynamic>{
            'type': 'resource',
            'resource': {
              'uri': 'file:///$name',
              'mimeType': mime,
              'text': decodedText,
            },
          };
        }
        return <String, dynamic>{
          'type': 'resource',
          'resource': {
            'uri': 'file:///$name',
            'mimeType': mime,
            'blob': data,
          },
          // Some agents also look at top-level blob/data, keep for compat.
          'mimeType': mime,
          'data': data,
          'uri': 'file:///$name',
        };
      }).toList();
      setState(() => _attachments.clear());
    }

    ref
        .read(chatProvider((widget.sessionId, widget.cwd)).notifier)
        .sendMessage(text, extra: extra);
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    if (animate) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
  }

  String _sessionTitle(List<AcpSession> sessions) {
    final match = sessions.where((s) => s.id == widget.sessionId).firstOrNull;
    if (match?.title != null && match!.title!.isNotEmpty) {
      return match.title!;
    }
    if (widget.cwd.isNotEmpty && widget.cwd != '/') {
      final parts = widget.cwd.split('/');
      final last =
          parts.lastWhere((p) => p.isNotEmpty, orElse: () => widget.cwd);
      return last;
    }
    return 'Chat';
  }

  void _openSlashPalette() {
    final cs = ref.read(chatProvider((widget.sessionId, widget.cwd))).valueOrNull;
    final cmds = cs?.availableCommands ?? [];
    final palette = <PaletteCommand>[
      if (cmds.isEmpty)
        PaletteCommand(title: 'No slash commands', subtitle: 'Agent has not exposed commands', icon: Icons.info_outline, onSelect: () {}),
      for (final c in cmds)
        PaletteCommand(
          title: '/${c.name}',
          subtitle: c.description + (c.inputHint != null ? ' — ${c.inputHint}' : ''),
          icon: Icons.terminal_rounded,
          onSelect: () {
            _textController.text = '/${c.name} ';
            _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
            // Keep keyboard focused on input
            Future.microtask(() => _focusNode.requestFocus());
          },
        ),
      PaletteCommand(title: 'Copy Session ID', subtitle: widget.sessionId, icon: Icons.copy_rounded, onSelect: () async { await Clipboard.setData(ClipboardData(text: widget.sessionId)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session ID copied'))) ;}),
      PaletteCommand(title: 'Copy CWD', subtitle: widget.cwd, icon: Icons.folder_outlined, onSelect: () async { await Clipboard.setData(ClipboardData(text: widget.cwd)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CWD copied'))) ;}),
    ];
    showCommandPalette(context, ref, palette);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daemonDown = ref.watch(
      connectionProvider.select((c) => c.paired && !c.daemonConnected),
    );
    final agentName = ref.watch(
      connectionProvider.select((c) => c.agentInfo?.name),
    );

    ref.listen(
      chatProvider((widget.sessionId, widget.cwd)),
      (previous, next) {
        final prevReq = previous?.valueOrNull?.permissionRequest;
        final nextReq = next.valueOrNull?.permissionRequest;
        if (nextReq != null && prevReq != nextReq) {
          Future.microtask(() {
            if (mounted) _showPermissionDialog(context, nextReq);
          });
        }
      },
    );

    ref.listen(
      sessionListProvider,
      (previous, next) {
        final sessions = next.valueOrNull;
        if (sessions == null) return;
        final newTitle = _sessionTitle(sessions);
        if (newTitle.isNotEmpty && newTitle != _title) {
          setState(() => _title = newTitle);
        }
      },
    );

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            if (agentName != null)
              Text(
                agentName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(tooltip: 'Commands (Ctrl+K)', icon: const Icon(Icons.auto_awesome_rounded), onPressed: _openSlashPalette),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close session',
            onPressed: () {
              ref.read(connectionProvider.notifier).closeSession(widget.sessionId);
              context.pop();
            },
          ),
        ],
      ),
      body: AnimatedBackground(
        showGrid: false,
        animate: false,
        child: Column(
          children: [
            if (ref.watch(demoModeProvider) && demoSessionIds.contains(widget.sessionId))
              const DemoBanner(),
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final isDemo = ref.watch(demoModeProvider) && demoSessionIds.contains(widget.sessionId);
                  final realChatState = ref.watch(
                  chatProvider((widget.sessionId, widget.cwd)).select(
                    (state) => state,
                  ),
                );
                  final chatState = isDemo
                      ? AsyncValue.data(ChatState(
                          messages: widget.sessionId == 'demo-1' ? mockMessagesDemo1 : mockMessagesDemo2,
                          availableCommands: mockSlashCommands,
                        ))
                      : realChatState;
                  final showSkeleton = isDemo ? false : (_showSkeleton || chatState.isLoading);
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: showSkeleton
                        ? Column(
                            key: const ValueKey('skeleton'),
                            children: [
                              if (daemonDown) const DaemonOfflineBanner(),
                              const Expanded(child: ChatSkeleton()),
                            ],
                          )
                        : Column(
                            key: const ValueKey('chat'),
                            children: [
                              if (daemonDown) const DaemonOfflineBanner(),
                              Consumer(
                        builder: (context, ref, child) {
                          final isDemoCfg = ref.watch(demoModeProvider) && demoSessionIds.contains(widget.sessionId);
                          final configOptions = isDemoCfg
                              ? const <ConfigOption>[]
                              : ref.watch(
                                  chatProvider((widget.sessionId, widget.cwd)).select(
                                    (state) =>
                                        state.valueOrNull?.configOptions ??
                                        const <ConfigOption>[],
                                  ),
                          );
                          final modeOptions = configOptions
                              .where((c) => c.category == 'mode')
                              .toList();
                          if (modeOptions.isEmpty || modeOptions.first.options.length <= 1) {
                            return const SizedBox.shrink();
                          }
                          return _buildModeSelector(theme, modeOptions.first);
                        },
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: chatState.whenOrNull(
                                  data: (cs) {
                                  final messages = cs.messages;
                                  if (messages.isEmpty) {
                                    final t = Theme.of(context);
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 48),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(24),
                                              decoration: BoxDecoration(
                                                color: t.brightness == Brightness.dark 
                                                    ? Colors.white.withValues(alpha: 0.05)
                                                    : Colors.black.withValues(alpha: 0.03),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.chat_bubble_outline_rounded,
                                                size: 64,
                                                color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                              ),
                                            ),
                                            const SizedBox(height: 24),
                                            Text(
                                              'Ready to help',
                                              style: t.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Type a message below to start your conversation with the agent.',
                                              style: t.textTheme.bodyMedium?.copyWith(
                                                color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                                height: 1.5,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 20),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              alignment: WrapAlignment.center,
                                              children: [
                                                for (final chip in const [
                                                  ('Explain this repo', Icons.description_outlined),
                                                  ('Fix failing tests', Icons.bug_report_outlined),
                                                  ('Review last diff', Icons.rate_review_outlined),
                                                ])
                                                  ActionChip(
                                                    avatar: Icon(chip.$2, size: 14, color: t.colorScheme.primary),
                                                    label: Text(chip.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                                    onPressed: () {
                                                      HapticFeedback.selectionClick();
                                                      _textController.text = chip.$1;
                                                      _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  final reversedMessages = messages.reversed.toList();
                                  return ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                                    child: ListView.builder(
                                      reverse: true,
                                      controller: _scrollController,
                                      padding: const EdgeInsets.all(16),
                                      itemCount: reversedMessages.length,
                                      cacheExtent: 400,
                                      addAutomaticKeepAlives: false,
                                      addRepaintBoundaries: true,
                                      itemBuilder: (context, index) {
                                        final msg = reversedMessages[index];
                                        return RepaintBoundary(
                                          key: ValueKey(msg.id),
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 4),
                                            child: MessageBubble(message: msg),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                                error: (e, _) {
                                  final t = Theme.of(context);
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            size: 56,
                                            color: t.colorScheme.error,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Could not load chat',
                                            style: t.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            e.toString(),
                                            textAlign: TextAlign.center,
                                            style: t.textTheme.bodyMedium?.copyWith(
                                              color: t.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton.tonal(
                                            onPressed: () => ref
                                                .read(chatProvider((
                                                        widget.sessionId, widget.cwd))
                                                    .notifier)
                                                .loadMessages(),
                                            child: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ) ?? const Center(child: Text('Could not load chat')),
                            ),
                            if (_showScrollButton)
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: FloatingActionButton.small(
                                  onPressed: _scrollToBottom,
                                  child: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              ),
            ),
            _buildInputArea(theme, daemonDown),
          ],
        ),
      ),
    );
  }

  List<SlashCommand> _filterSlashCommands(List<SlashCommand> commands, String query) {
    if (query.isEmpty) return commands;
    final q = query.toLowerCase();
    return commands.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  Widget _buildInputArea(ThemeData theme, bool daemonDown) {
    return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.12),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Consumer(
          builder: (context, ref, child) {
            final isDemoInput = ref.watch(demoModeProvider) && demoSessionIds.contains(widget.sessionId);
            final realCs = ref.watch(
              chatProvider((widget.sessionId, widget.cwd)).select(
                (s) => (
                  isBusy: s.valueOrNull?.isBusy ?? false,
                  configOptions:
                      s.valueOrNull?.configOptions ?? const <ConfigOption>[],
                  availableCommands:
                      s.valueOrNull?.availableCommands ??
                          const <SlashCommand>[],
                  currentModel: s.valueOrNull?.currentModel,
                ),
              ),
            );
            final cs = isDemoInput
                ? (isBusy: false, configOptions: realCs.configOptions, availableCommands: mockSlashCommands, currentModel: realCs.currentModel)
                : realCs;
            final isBusy = cs.isBusy;
            final configOptions = cs.configOptions;
            final availableCommands = cs.availableCommands;

            final modelConfig = configOptions
                .where((c) => c.category == 'model')
                .firstOrNull;
            final modelLabel = modelConfig != null
                ? (modelConfig.currentValue.isNotEmpty
                    ? modelConfig.currentValue
                    : modelConfig.name.isNotEmpty
                        ? modelConfig.name
                        : null)
                : (cs.currentModel?.isNotEmpty ?? false)
                    ? cs.currentModel
                    : ref.read(connectionProvider).agentInfo?.name;
            final t = Theme.of(context);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attachments.isNotEmpty)
                  Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachments.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final att = _attachments[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: t.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.colorScheme.outlineVariant),
                          ),
                          padding: const EdgeInsets.only(left: 10, right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_iconForAttachment(att), size: 16, color: t.colorScheme.primary),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: Text(
                                  att['name'] ?? 'file',
                                  style: t.textTheme.labelMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() => _attachments.removeAt(index)),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, _) {
                    final text = value.text;
                    final slashMatch =
                        text.startsWith('/') ? text.substring(1) : null;
                    if (slashMatch == null) {
                      return const SizedBox.shrink();
                    }
                    final slashCommands =
                        _filterSlashCommands(availableCommands, slashMatch);
                    if (slashCommands.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: t.colorScheme.outlineVariant.withValues(alpha: 0.15),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: slashCommands.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: t.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                          padding: EdgeInsets.zero,
                          itemBuilder: (ctx, i) {
                            final cmd = slashCommands[i];
                            final hint = cmd.inputHint != null
                                ? ' ${cmd.inputHint}'
                                : '';
                            return InkWell(
                              onTap: () {
                                _textController.text = '/${cmd.name} ';
                                _textController.selection =
                                    TextSelection.collapsed(
                                  offset: _textController.text.length,
                                );
                                // Keep keyboard focused on input after selecting slash command
                                _focusNode.requestFocus();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '/${cmd.name}',
                                      style: t.textTheme.labelLarge?.copyWith(
                                        color: t.colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '${cmd.description}$hint',
                                        style: t.textTheme.bodyMedium?.copyWith(
                                          color: t.colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                  child: Row(
                    children: [
                      if (modelLabel != null)
                        _ModelChip(
                          label: modelLabel,
                          onTap: configOptions.isNotEmpty
                              ? () => _showConfigSheet(context, configOptions)
                              : null,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: t.colorScheme.surfaceContainerHighest,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            onPressed: (isBusy || daemonDown)
                                ? null
                                : () {
                                    HapticFeedback.selectionClick();
                                    _showAttachmentOptions();
                                  },
                            icon: const Icon(Icons.add_rounded, size: 22),
                            color: t.colorScheme.onSurfaceVariant,
                            tooltip: 'Attach file',
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          readOnly: isBusy || daemonDown,
                          minLines: 1,
                          maxLines: 6,
                          style: t.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText: daemonDown ? 'Daemon not connected' : 'Message...',
                            hintStyle: t.textTheme.bodyLarge?.copyWith(
                              color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                            filled: true,
                            fillColor: t.colorScheme.surfaceContainerHigh,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: t.colorScheme.primary.withValues(alpha: 0.45),
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _textController,
                        builder: (context, value, _) {
                          final canSend = !isBusy &&
                              !daemonDown &&
                              (value.text.trim().isNotEmpty ||
                                  _attachments.isNotEmpty);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) => ScaleTransition(
                                  scale: anim,
                                  child: FadeTransition(opacity: anim, child: child),
                                ),
                                child: isBusy
                                    ? IconButton.filled(
                                        key: const ValueKey('stop'),
                                        tooltip: 'Stop response',
                                        onPressed: () => ref
                                            .read(chatProvider((
                                              widget.sessionId,
                                              widget.cwd))
                                                .notifier)
                                            .cancelResponse(),
                                        icon: const Icon(Icons.stop_rounded, size: 22),
                                        style: IconButton.styleFrom(
                                          backgroundColor: t.colorScheme.errorContainer,
                                          foregroundColor: t.colorScheme.onErrorContainer,
                                        ),
                                      )
                                    : IconButton.filled(
                                        key: const ValueKey('send'),
                                        onPressed: canSend ? _sendMessage : null,
                                        icon: const Icon(Icons.arrow_upward, size: 22),
                                        style: IconButton.styleFrom(
                                          backgroundColor: t.colorScheme.primary,
                                          foregroundColor: t.colorScheme.onPrimary,
                                          disabledBackgroundColor: t.colorScheme.surfaceContainerHighest,
                                          disabledForegroundColor: t.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
            ),
          ),
    );
  }

  Widget _buildModeSelector(
    ThemeData theme,
    ConfigOption opt,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: opt.options.map((v) {
              final selected = v.value == opt.currentValue;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(v.name, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: true,
                  onSelected: (_) {
                    ref
                        .read(chatProvider(
                                (widget.sessionId, widget.cwd))
                            .notifier)
                        .setConfigOption(opt.id, v.value);
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showPermissionDialog(BuildContext context, PermissionRequest req) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                req.title ?? 'Permission Requested',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (req.toolName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        req.toolName!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (req.toolContent.isNotEmpty)
              ...req.toolContent.map((c) {
                final text = c['text'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            const SizedBox(height: 12),
            Text(
              'Allow the agent to perform this action?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(chatProvider(
                          (widget.sessionId, widget.cwd))
                      .notifier)
                  .dismissPermission();
            },
            child: const Text('Cancel'),
          ),
          ...req.options.map((opt) {
            final isAllow = opt.kind.contains('allow');
            return isAllow
                ? FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(chatProvider(
                                  (widget.sessionId, widget.cwd))
                              .notifier)
                          .respondToPermission(opt.optionId);
                    },
                    child: Text(opt.name),
                  )
                : TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(chatProvider(
                                  (widget.sessionId, widget.cwd))
                              .notifier)
                          .respondToPermission(opt.optionId);
                    },
                    child: Text(opt.name),
                  );
          }),
        ],
      ),
    );
  }

  void _showConfigSheet(BuildContext context, List<ConfigOption> configOptions) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SheetUsageBlock(
                    sessionId: widget.sessionId,
                    cwd: widget.cwd,
                  ),
                  ...configOptions.map((opt) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            opt.name,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Consumer(
                            builder: (ctx2, ref2, _) {
                              final live = ref2
                                  .watch(chatProvider((
                                          widget.sessionId, widget.cwd)))
                                  .valueOrNull;
                              final liveOpt = live?.configOptions
                                  .where((o) => o.id == opt.id)
                                  .firstOrNull;
                              final currentValue =
                                  liveOpt?.currentValue ?? opt.currentValue;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: opt.options.map((v) {
                                  final selected =
                                      v.value == currentValue;
                                  return ChoiceChip(
                                    label: Text(v.name),
                                    selected: selected,
                                    onSelected: (_) {
                                      ref2
                                          .read(chatProvider((
                                                  widget.sessionId,
                                                  widget.cwd))
                                              .notifier)
                                          .setConfigOption(
                                              opt.id, v.value);
                                    },
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact read-only usage glance at the top of the model/config sheet.
/// Hidden entirely when the agent hasn't reported any usage yet, so the
/// sheet looks exactly as before for fresh sessions.
class _SheetUsageBlock extends ConsumerWidget {
  final String sessionId;
  final String cwd;

  const _SheetUsageBlock({required this.sessionId, required this.cwd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final agentId = ref
        .read(chatProvider((sessionId, cwd)).notifier)
        .agentIdForSession;
    final usage = ref.watch(usageTrackerProvider);
    final snap = agentId != null ? usage.byAgent[agentId] : null;
    if (snap == null || !snap.hasData) return const SizedBox.shrink();

    final fraction = snap.contextFraction;
    final over = agentId != null &&
        ref.read(usageTrackerProvider.notifier).isOverThreshold(agentId);
    final barColor =
        over ? theme.colorScheme.error : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsUsage,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (fraction != null)
                Text(
                  '${(fraction * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: over
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: over ? FontWeight.w600 : null,
                  ),
                ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ModelChip({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer
                .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                size: 13,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
