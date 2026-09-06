import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/session_list_provider.dart';
import '../../../core/demo/demo_mode.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/ongoing_session_banner.dart';
import '../../../shared/widgets/daemon_offline_banner.dart';
import '../../../shared/widgets/demo_banner.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/command_palette.dart';
import 'widgets/session_card.dart';
import 'widgets/session_list_skeleton.dart';
import 'widgets/directory_picker_sheet.dart';

class SessionListScreen extends ConsumerStatefulWidget {
  const SessionListScreen({super.key});

  @override
  ConsumerState<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends ConsumerState<SessionListScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  String _searchQuery = '';
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(sessionListProvider.notifier).loadSessions();
    });
  }

  void _confirmDelete(AcpSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          session.title ?? 'Untitled',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(sessionListProvider.notifier)
                  .deleteSession(session.id);
              ref
                  .read(sessionListProvider.notifier)
                  .deleteSessionRemote(session.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createSession() async {
    final conn = ref.read(connectionProvider);
    if (conn.paired && !conn.daemonConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot create session — daemon is not running'),
          ),
        );
      }
      return;
    }

    final hasOnlineAgent = conn.agents.any((a) => a.online);
    if (!hasOnlineAgent && conn.agents.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to the AI agent on the desktop first'),
          ),
        );
      }
      return;
    }
    // Start the directory picker at the daemon's home directory.
    final notifier = ref.read(connectionProvider.notifier);
    final completer = Completer<String>();
    int? reqId;
    StreamSubscription<Map<String, dynamic>>? sub;
    sub = notifier.messages.listen((msg) {
      if (msg['id'] == reqId) {
        sub?.cancel();
        final result = msg['result'] as Map<String, dynamic>?;
        if (result != null) {
          completer.complete(result['home'] as String? ?? '/home');
        } else {
          completer.complete('/home');
        }
      }
    });
    reqId = notifier.getHome();
    final initialPath = await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        sub?.cancel();
        return '/home';
      },
    );

    if (!mounted) return;
    final pickedPath = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DirectoryPickerSheet(
        initialPath: initialPath,
        onSelected: (path) => Navigator.of(ctx).pop(path),
      ),
    );
    if (pickedPath == null || !mounted) return;

    try {
      await ref.read(sessionListProvider.notifier).createSession(pickedPath);
    } on SessionCreateException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create session — ${e.message}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create session — daemon may be disconnected')),
        );
      }
    }
  }

  String _timeAgo(double timestamp) {
    if (timestamp <= 0) return '';
    final diff = DateTime.now().millisecondsSinceEpoch - (timestamp * 1000).toInt();
    final seconds = diff ~/ 1000;
    if (seconds < 60) return 'just now';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    final days = hours ~/ 24;
    if (days < 7) return '${days}d ago';
    return '${days ~/ 7}w ago';
  }

  void _openPalette() {
    final cmds = [
      PaletteCommand(title: 'New Session', subtitle: 'Create a workspace', icon: Icons.add_rounded, onSelect: _createSession),
      PaletteCommand(title: 'Refresh Sessions', subtitle: 'Reload from agent', icon: Icons.refresh_rounded, onSelect: () => ref.read(sessionListProvider.notifier).loadSessions()),
      PaletteCommand(title: 'Go to Agents', subtitle: 'Switch agent', icon: Icons.smart_toy_outlined, onSelect: () => context.go('/agents')),
      PaletteCommand(title: 'Go to Settings', subtitle: 'Preferences & MCP', icon: Icons.settings_outlined, onSelect: () => context.go('/settings')),
      PaletteCommand(title: 'Search Sessions', subtitle: 'Filter sessions', icon: Icons.search_rounded, onSelect: () => setState(() => _showSearch = true)),
    ];
    showCommandPalette(context, ref, cmds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDemo = ref.watch(demoModeProvider);
    final connection = ref.watch(connectionProvider);
    final realSessionsAsync = ref.watch(sessionListProvider);
    final sessionsAsync = isDemo ? AsyncValue.data(mockSessions) : realSessionsAsync;
    final activeIds = ref.watch(activeSessionsProvider);

    return CommandPaletteShortcut(
      onOpen: _openPalette,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.1),
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.transparent),
            ),
          ),
          title: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search sessions...',
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: theme.textTheme.titleMedium,
                  onChanged: (v) => setState(() => _searchQuery = v),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sessions',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      connection.agentInfo?.name ?? 'Agent',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(tooltip: 'Command palette (Ctrl+K)', icon: const Icon(Icons.auto_awesome_rounded), onPressed: _openPalette),
            IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              }),
            ),
          ],
        ),
      body: AnimatedBackground(
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
            Expanded(
              child: sessionsAsync.when(
                loading: () => const SessionListSkeleton(),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (sessions) {
                  final supportsSessionList =
                      connection.capabilities?.supportsSessionList ?? true;
                  final filtered = _searchQuery.isEmpty
                      ? sessions
                      : sessions
                          .where((s) =>
                              (s.title ?? '')
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase()) ||
                              s.cwd.toLowerCase().contains(_searchQuery.toLowerCase()))
                          .toList();

                  return Column(
                    children: [
                      if (isDemo) const DemoBanner(),
                      const OngoingSessionBanner(),
                      if (!isDemo && connection.paired && !connection.daemonConnected)
                        const DaemonOfflineBanner(),
                      if (sessions.isNotEmpty)
                        _InsightsHeader(
                          total: sessions.length,
                          active: activeIds.length,
                          daemonOnline: connection.daemonConnected,
                          agentName: connection.agentInfo?.name,
                        ),
                      if (!supportsSessionList && sessions.isNotEmpty)
                        _LocalOnlyBanner(),
                      Expanded(
                        child: _buildSessionList(
                          theme,
                          filtered,
                          sessions,
                          _searchQuery,
                          activeIds,
                          !connection.daemonConnected,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _createSession();
        },
        child: const Icon(Icons.add),
      ),
    ));
  }

  Widget _buildSessionList(
    ThemeData theme,
    List<AcpSession> filtered,
    List<AcpSession> sessions,
    String searchQuery,
    Set<String> activeIds,
    bool isDaemonOffline,
  ) {
    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark 
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No sessions found',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Start your first workspace session to begin interacting with the agent.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _createSession,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New Session'),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty && searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No sessions match "$searchQuery"',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(sessionListProvider.notifier).loadSessions(),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final session = filtered[index];
          final isFiltering = searchQuery.isNotEmpty;
          final card = Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SessionCard(
              title: session.title,
              cwd: session.cwd,
              timeAgo: _timeAgo(session.updatedAt),
              isActive: activeIds.contains(session.id),
              isOffline: isDaemonOffline,
              onTap: () {
                final cwd = session.cwd;
                final path = cwd.isNotEmpty
                    ? '/chat/${session.id}?cwd=${Uri.encodeComponent(cwd)}'
                    : '/chat/${session.id}';
                context.push(path);
              },
              onDelete: () {
                _confirmDelete(session);
              },
            ),
          );
          if (isFiltering) return card;
          return Dismissible(
            key: ValueKey(session.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              _confirmDelete(session);
              return false;
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            child: card,
          );
        },
      ),
    );
  }
}

class _InsightsHeader extends StatelessWidget {
  final int total;
  final int active;
  final bool daemonOnline;
  final String? agentName;
  const _InsightsHeader({required this.total, required this.active, required this.daemonOnline, this.agentName});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : theme.colorScheme.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: daemonOnline ? const Color(0xFF22C55E) : Colors.orange,
                shape: BoxShape.circle,
                boxShadow: daemonOnline ? [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.4), blurRadius: 6)] : [],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    daemonOnline ? 'All systems operational' : 'Daemon offline',
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$total sessions · $active active${agentName != null ? ' · $agentName' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(daemonOnline ? Icons.check_circle_rounded : Icons.warning_amber_rounded, size: 16, color: daemonOnline ? const Color(0xFF22C55E) : Colors.orange),
          ],
        ),
      ),
    );
  }
}

class _LocalOnlyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 16,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Agent doesn\'t support remote listing — showing local sessions',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
