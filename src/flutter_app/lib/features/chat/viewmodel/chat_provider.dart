import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../core/models/chat_message.dart';
import '../../../core/models/assistant_segment.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/session_list_provider.dart';
import '../../../core/models/connection_state.dart';

class ConfigOption {
  final String id;
  final String name;
  final String? description;
  final String category;
  final String currentValue;
  final List<ConfigOptionValue> options;

  const ConfigOption({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    required this.currentValue,
    required this.options,
  });

  factory ConfigOption.fromJson(Map<String, dynamic> json) {
    return ConfigOption(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      description: json['description'] as String?,
      category: json['category'] as String? ?? '',
      currentValue: json['currentValue'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) =>
                  ConfigOptionValue.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'currentValue': currentValue,
    'options': options.map((e) => e.toJson()).toList(),
  };
}

class ConfigOptionValue {
  final String value;
  final String name;
  final String? description;

  const ConfigOptionValue({
    required this.value,
    required this.name,
    this.description,
  });

  factory ConfigOptionValue.fromJson(Map<String, dynamic> json) {
    return ConfigOptionValue(
      value: json['value'] as String,
      name: json['name'] as String? ?? json['value'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'value': value,
    'name': name,
    if (description != null) 'description': description,
  };
}

class SlashCommand {
  final String name;
  final String description;
  final String? inputHint;

  const SlashCommand({
    required this.name,
    required this.description,
    this.inputHint,
  });

  factory SlashCommand.fromJson(Map<String, dynamic> json) {
    return SlashCommand(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      inputHint: (json['input'] as Map<String, dynamic>?)?.let((m) => m['hint'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    if (inputHint != null) 'input': {'hint': inputHint},
  };
}

extension _Let<T extends Object> on T {
  R? let<R>(R? Function(T) f) => f(this);
}

class PermissionOption {
  final String optionId;
  final String name;
  final String kind;

  const PermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  factory PermissionOption.fromJson(Map<String, dynamic> json) {
    return PermissionOption(
      optionId: json['optionId'] as String,
      name: json['name'] as String? ?? json['optionId'] as String,
      kind: json['kind'] as String? ?? 'allow_once',
    );
  }

  Map<String, dynamic> toJson() => {
    'optionId': optionId,
    'name': name,
    'kind': kind,
  };
}

class PermissionRequest {
  final String sessionId;
  final int requestId;
  final String? title;
  final String? toolName;
  final List<Map<String, dynamic>> toolContent;
  final List<PermissionOption> options;

  const PermissionRequest({
    required this.sessionId,
    required this.requestId,
    this.title,
    this.toolName,
    this.toolContent = const [],
    this.options = const [],
  });
}

class ChatState {
  final List<ChatMessage> messages;
  final List<ConfigOption> configOptions;
  final String? currentModel;
  final String? currentMode;
  final bool isBusy;
  final List<SlashCommand> availableCommands;
  final PermissionRequest? permissionRequest;

  const ChatState({
    this.messages = const [],
    this.configOptions = const [],
    this.currentModel,
    this.currentMode,
    this.isBusy = false,
    this.availableCommands = const [],
    this.permissionRequest,
  });
}

class ChatNotifier extends StateNotifier<AsyncValue<ChatState>> {
  final Ref _ref;
  final String _sessionId;
  final String _cwd;
  final _uuid = const Uuid();
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _loaded = false;
  final List<ChatMessage> _buffer = [];
  final Set<int> _pendingIds = {};
  int? _loadPendingId;
  String? _timeoutMessageId;
  List<ConfigOption>? _pendingConfigs;
  Timer? _streamingTimer;

  /// Tracks whether the WebSocket connection is still alive. When the
  /// connection drops we cancel timers and skip work to avoid triggering
  /// UI rebuilds during the reconnect storm.
  bool _connected = true;

  ChatNotifier(this._ref, this._sessionId, this._cwd)
      : super(const AsyncValue.loading()) {
    debugPrint('[chat_provider] ChatNotifier created for session=$_sessionId cwd=$_cwd');
    _listenToRelay();
    _watchConnection();
    _loadSessionFromAgent();
    loadMessages();
  }

  void _watchConnection() {
    _ref.listen(connectionProvider, (prev, next) {
      if (next.state is Connected && prev?.state is! Connected) {
        _connected = true;
      } else if (next.state is Disconnected || next.state is Reconnecting) {
        _connected = false;
        _streamingTimer?.cancel();
      }
    });
  }

  void _logBusy(String label) {
    final pending = _pendingIds.toList();
    final streaming = _buffer.where((m) => m.isStreaming).map((m) => m.id).toList();
    debugPrint(
      '[ACP-DIAG] $label session=$_sessionId loadPending=$_loadPendingId pending=$pending streaming=$streaming isBusy=$_isBusy',
    );
  }

  Future<void> _loadSessionFromAgent() async {
    final connection = _ref.read(connectionProvider);
    final supportsLoad = connection.capabilities?.supportsLoadSession ?? true;
    if (!supportsLoad) {
      return;
    }
    final notifier = _ref.read(connectionProvider.notifier);
    final id = await notifier.loadSession(_sessionId, _cwd);
    _pendingIds.add(id);
    _loadPendingId = id;
    _logBusy('loadAgent');
    if (_loaded) _syncState();
  }

  bool get _isBusy {
    // Session load should not block the input field; only actual message
    // requests and streaming content should make the chat "busy".
    final busyPending = _pendingIds.where((id) => id != _loadPendingId).length;
    return busyPending > 0 || _buffer.any((m) => m.isStreaming);
  }

  /// Called periodically or after state changes to clean up streaming that
  /// was orphaned (no pending request IDs) — likely from another client.
  void _cleanOrphanedStream() {
    if (_buffer.any((m) => m.isStreaming) &&
        _pendingIds.where((id) => id != _loadPendingId).isEmpty) {
      debugPrint('[ACP-DIAG] orphaned stream detected; finalizing session=$_sessionId');
      _finalizeStreaming();
    }
  }

  List<SlashCommand> _slashCommands = [];
  PermissionRequest? _permissionRequest;

  void _syncState() {
    if (!mounted) return;
    if (!_connected) {
      debugPrint('[chat_provider] _syncState skipped: not connected');
      return;
    }
    _logBusy('sync');
    final current = state.valueOrNull;
    debugPrint('[chat_provider] _syncState: ${_buffer.length} messages, was loading=${state.isLoading}');
    state = AsyncValue.data(ChatState(
      messages: List.of(_buffer),
      configOptions: current?.configOptions ?? [],
      currentModel: current?.currentModel,
      currentMode: current?.currentMode,
      isBusy: _isBusy,
      availableCommands: _slashCommands,
      permissionRequest: _permissionRequest,
    ));
  }

  void _bumpStreamingTimer() {
    _streamingTimer?.cancel();
    if (!_buffer.any((m) => m.isStreaming)) return;
    _streamingTimer = Timer(const Duration(seconds: 30), () {
      if (_buffer.any((m) => m.isStreaming)) {
        // If no pending request IDs, this is an orphaned stream from
        // another client — finalize immediately.
        if (_pendingIds.where((id) => id != _loadPendingId).isEmpty) {
          debugPrint(
            '[ACP-DIAG] orphaned streaming timeout; finalizing session=$_sessionId',
          );
          _cleanOrphanedStream();
        } else {
          debugPrint(
            '[ACP-DIAG] streaming inactivity timeout; finalizing session=$_sessionId',
          );
          _finalizeStreaming();
        }
      }
    });
  }

  void _syncConfigAndState(List<ConfigOption> configs) {
    if (!_connected) return;
    final model = configs.where((c) => c.category == 'model').firstOrNull;
    final mode = configs.where((c) => c.category == 'mode').firstOrNull;
    state = AsyncValue.data(ChatState(
      messages: List.of(_buffer),
      configOptions: configs,
      currentModel: model?.currentValue,
      currentMode: mode?.currentValue,
      isBusy: _isBusy,
      availableCommands: _slashCommands,
      permissionRequest: _permissionRequest,
    ));
  }

  Future<void> loadMessages() async {
    try {
      final db = _ref.read(databaseProvider);
      final rows = await db.getRecentMessages(_sessionId, limit: 5);
      final dbMessages = rows.reversed.map(_dbRowToMessage).toList();
      if (_buffer.isNotEmpty) {
        _buffer.insertAll(0, dbMessages);
      } else {
        _buffer.addAll(dbMessages);
      }
    } catch (e) {
      debugPrint('[ACP-CHAT] _loadMessages error: $e');
    }
    _loaded = true;
    if (_pendingConfigs != null) {
      final configs = _pendingConfigs!;
      _pendingConfigs = null;
      _syncConfigAndState(configs);
      unawaited(_reapplySavedConfigChoices(configs));
    } else {
      _syncState();
    }
    if (_loadPendingId != null) {
      Future.delayed(const Duration(seconds: 10), () {
        if (_loadPendingId != null && _pendingIds.contains(_loadPendingId)) {
          _pendingIds.remove(_loadPendingId);
          _loadPendingId = null;
          _syncState();
        }
      });
    }

    // Orphaned stream safety net: if streaming messages exist after loading
    // with no pending request IDs (the original requester was another client),
    // finalize them after a short grace period so the UI doesn't stay stuck.
    Future.delayed(const Duration(seconds: 10), _cleanOrphanedStream);
  }

  void _setConfigOptions(List<ConfigOption> configs) {
    if (_loaded) {
      _syncConfigAndState(configs);
    } else {
      _pendingConfigs = configs;
    }
  }

  ChatMessage _dbRowToMessage(db.ChatMessage row) {
    List<AssistantSegment> segments = [];
    if (row.segmentsJson != null && row.segmentsJson!.isNotEmpty) {
      try {
        final list = jsonDecode(row.segmentsJson!) as List<dynamic>;
        segments = list
            .map((e) =>
                AssistantSegment.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return ChatMessage(
      id: row.id,
      role:
          row.role == 'user' ? ChatMessageRole.user : ChatMessageRole.assistant,
      content: row.content,
      segments: segments,
      isStreaming: false,
      createdAt: row.createdAt.toInt(),
    );
  }

  void _populateFromLoad(Map<String, dynamic> result) {
    try {
      final rawMessages = result['messages'] as List<dynamic>;
      final maxMessages = rawMessages.length > 50 ? rawMessages.sublist(rawMessages.length - 50) : rawMessages;
      var added = false;
      for (final raw in maxMessages) {
        if (raw is! Map<String, dynamic>) continue;
        final id = (raw['id'] as String?) ?? _uuid.v4();
        if (_buffer.any((m) => m.id == id)) continue;

        final roleStr = raw['role'] as String? ?? 'assistant';
        if (roleStr != 'user' && roleStr != 'assistant') continue;
        final role = roleStr == 'user'
            ? ChatMessageRole.user
            : ChatMessageRole.assistant;
        final content = raw['content'] as String? ?? '';

        List<AssistantSegment> segments = [];
        if (raw['segments'] is List) {
          for (final seg in raw['segments'] as List<dynamic>) {
            if (seg is Map<String, dynamic>) {
              try {
                segments.add(AssistantSegment.fromJson(seg));
              } catch (_) {}
            }
          }
        }

        _buffer.add(ChatMessage(
          id: id,
          role: role,
          content: content,
          segments: segments,
          isStreaming: false,
          createdAt: (raw['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ));
        added = true;
      }

      if (added) {
        _saveMessagesToDb();
        _finalizeStreaming();
        if (_loaded) _syncState();
      }
    } catch (e) {
      debugPrint('[ACP-CHAT] error parsing load response: $e');
    }
  }

  Future<void> _saveMessagesToDb() async {
    try {
      final db = _ref.read(databaseProvider);
      for (final m in _buffer) {
        if (m.role == ChatMessageRole.user) continue;
        await db.saveMessage(
          id: m.id,
          sessionId: _sessionId,
          role: 'assistant',
          content: m.content,
          isStreaming: false,
          createdAt: m.createdAt,
        );
      }
    } catch (e) {
      debugPrint('[ACP-CHAT] error saving to DB: $e');
    }
  }

  void _listenToRelay() {
    final notifier = _ref.read(connectionProvider.notifier);
    _sub = notifier.messages.listen(
      (msg) {
        final method = msg['method'] as String?;
        final params = msg['params'] as Map<String, dynamic>?;

        if (params != null && params['sessionId'] == _sessionId) {
          if (method == 'session/update') {
            _handleUpdate(params);
          } else if (method == 'session/notification') {
            _handleLegacyNotification(params);
          } else if (method == 'session/request_permission') {
            _handlePermissionRequest(msg['id'], params);
            return;
          }
        }

        // Detect JSON-RPC response to a pending request (prompt/load done).
        // Capture membership BEFORE removal so the configOptions block below
        // can tell whether a sessionId-less response answers OUR request.
        final msgId = msg['id'];
        final isOwnResponse = msgId != null && _pendingIds.contains(msgId);
        if (method == null && isOwnResponse) {
          _pendingIds.remove(msgId);
          _streamingTimer?.cancel();
          final wasLoad = msgId == _loadPendingId;
          if (wasLoad) {
            _loadPendingId = null;
            final result = msg['result'] as Map<String, dynamic>?;
            if (result != null && result['messages'] is List) {
              _populateFromLoad(result);
            }
            _finalizeStreaming();
            if (_loaded) _syncState();
          }

          // If the agent says the session doesn't exist, remove it locally
          // so the user sees why their message got no response.
          if (!wasLoad) {
            final error = msg['error'] as Map<String, dynamic>?;
            final errorMsg = error?['message'] as String? ?? '';
            if (errorMsg.contains('session not found')) {
              _buffer.add(ChatMessage(
                id: _uuid.v4(),
                role: ChatMessageRole.assistant,
                content: 'This session no longer exists on the agent side.',
                isStreaming: false,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ));
              _ref.read(sessionListProvider.notifier).deleteSession(_sessionId);
              _finalizeStreaming();
              _ref.read(activeSessionsProvider.notifier).markInactive(_sessionId);
              if (_loaded) _syncState();
              return;
            }
          }

          // Remove the "waiting" message once the agent actually responds.
          if (_timeoutMessageId != null) {
            _buffer.removeWhere((m) => m.id == _timeoutMessageId);
            _timeoutMessageId = null;
          }

          _finalizeStreaming();
          _ref.read(activeSessionsProvider.notifier).markInactive(_sessionId);
          if (!wasLoad) {
            _ref.read(sessionListProvider.notifier).loadSessions();
          }
          if (!wasLoad && _loaded) _syncState();
        }

        // Capture configOptions from session/new or session/load response.
        // Only process JSON-RPC responses (no method, has id) to prevent
        // notifications from accidentally setting config options.
        // Strictly scoped: apply only when the response names OUR session,
        // or when it answers one of OUR pending requests (some agents omit
        // sessionId from new/load results). Otherwise one agent's models
        // (e.g. opencode's) would leak into another agent's chat (e.g.
        // cursor's), since all chats share this relay stream.
        final result = msg['result'] as Map<String, dynamic>?;
        if (method == null && result != null && result['configOptions'] is List) {
          final respSessionId = result['sessionId'] as String?;
          final belongsToUs = respSessionId == _sessionId ||
              (respSessionId == null && isOwnResponse);
          if (!belongsToUs) {
            return;
          }
          final configs = (result['configOptions'] as List<dynamic>)
              .map((e) => ConfigOption.fromJson(e as Map<String, dynamic>))
              .toList();
          if (configs.isNotEmpty) {
            _setConfigOptions(configs);
            // Fresh (default) configs from the agent would wipe the user's
            // saved pick — re-apply it so the model choice sticks.
            unawaited(_reapplySavedConfigChoices(configs));
          }
        }
      },
      onError: (error) {
        debugPrint('[ACP-CHAT] stream error: $error');
      },
      onDone: () {
        debugPrint('[ACP-CHAT] stream closed');
      },
    );
  }

  String _extractText(dynamic content) {
    if (content is String) return content;
    if (content is Map) return (content['text'] as String?) ?? '';
    if (content is List) {
      return content.map((c) {
        if (c is Map) return (c['text'] as String?) ?? '';
        return c.toString();
      }).join();
    }
    return '';
  }

  void _handleUpdate(Map<String, dynamic> params) {
    final update = params['update'] as Map<String, dynamic>?;
    if (update == null) return;
    _finalizeTimer?.cancel();

    final type = update['sessionUpdate'] as String?;
    final text = _extractText(update['content']);
    final msgId = update['messageId'] as String?;


    switch (type) {
      case 'user_message_chunk':
        _finalizeStreaming();
        _upsertMessage(text, ChatMessageRole.user, msgId);
        break;
      case 'agent_message_chunk':
        _upsertMessage(text, ChatMessageRole.assistant, msgId);
        break;
      case 'agent_thought_chunk':
        _addThoughtChunk(text);
        break;
      case 'tool_call':
        _ensureAssistantMessage();
        _addSegment(
          SegmentKind.toolCall,
          update['title'] as String? ?? 'tool call',
          update['toolCallId'] as String? ?? '',
        );
        break;
      case 'tool_call_update':
        final toolOut = update['content'] as List<dynamic>?;
        final textParts = <String>[];
        final diffs = <Map<String, String>>[];
        String? terminalId;
        if (toolOut != null) {
          for (final c in toolOut) {
            final map = c as Map<String, dynamic>;
            if (map['type'] == 'diff') {
              diffs.add({
                'path': map['path'] as String? ?? '',
                'oldText': map['oldText'] as String? ?? '',
                'newText': map['newText'] as String? ?? '',
              });
            } else if (map['type'] == 'terminal') {
              terminalId = map['terminalId'] as String?;
            } else {
              textParts.add(map['text'] as String? ?? '');
            }
          }
        }
        final outText = textParts.join('\n');
        final toolId = update['toolCallId'] as String? ?? '';
        final toolStatus = update['status'] as String?;
        _updateToolOutput(toolId, outText, toolStatus,
            diffs: diffs, terminalId: terminalId);
        break;
      case 'plan':
        _ensureAssistantMessage();
        _addSegment(
          SegmentKind.plan,
          (update['entries'] as List<dynamic>?)
                  ?.map((e) => (e as Map<String, dynamic>)['content'] as String? ?? '')
                  .join('\n') ??
              'plan',
          '',
        );
        break;
      case 'config_option_update':
        final configs = update['configOptions'] as List<dynamic>?;
        if (configs != null) {
          _setConfigOptions(
            configs
                .map((e) => ConfigOption.fromJson(e as Map<String, dynamic>))
                .toList(),
          );
        }
        break;
      case 'available_commands_update':
        final raw = update['availableCommands'] as List<dynamic>?;
        if (raw != null) {
          _slashCommands = raw
              .map((e) => SlashCommand.fromJson(e as Map<String, dynamic>))
              .toList();
          if (_loaded) _syncState();
        }
        break;
      case 'usage_update':
        break;
      default:
        debugPrint('[ACP-CHAT] unhandled update type: $type');
        break;
    }
  }

  Timer? _finalizeTimer;

  void _finalizeStreaming() {
    if (!mounted) return;
    if (!_connected) return;
    _finalizeTimer?.cancel();
    _finalizeTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _doFinalizeStreaming();
    });
  }

  void _doFinalizeStreaming() {
    if (!mounted) return;
    if (!_connected) return;
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer[i].isStreaming) {
        _buffer[i] = _buffer[i].copyWith(isStreaming: false);
      }
    }
    if (_loaded) _syncState();
  }

  void _upsertMessage(String text, ChatMessageRole role, String? msgId) {
    if (role == ChatMessageRole.assistant) _finalizeTimer?.cancel();
    if (msgId != null) {
      for (var i = 0; i < _buffer.length; i++) {
        if (_buffer[i].id == msgId) {
          final existing = _buffer[i].content;
          // Some agents send cumulative/full-message chunks instead of deltas.
          final newContent = text.startsWith(existing) ? text : existing + text;
          _buffer[i] = _buffer[i].copyWith(content: newContent);
          if (_loaded) _syncState();
          return;
        }
      }
    }
    // If no msgId and role is assistant, append to last streaming assistant message
    if (role == ChatMessageRole.assistant && _buffer.isNotEmpty) {
      final last = _buffer.last;
      if (last.role == ChatMessageRole.assistant && last.isStreaming) {
        final newContent = last.content + text;
        _buffer[_buffer.length - 1] = last.copyWith(content: newContent);
        if (_loaded) _syncState();
        return;
      }
    }
    _buffer.add(ChatMessage(
      id: msgId ?? _uuid.v4(),
      role: role,
      content: text,
      isStreaming: role == ChatMessageRole.assistant,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (role == ChatMessageRole.assistant) _bumpStreamingTimer();
    if (_loaded) _syncState();
  }

  void _addThoughtChunk(String text) {
    _ensureAssistantMessage();
    final last = _buffer.last;
    final existing = last.segments
        .where((s) => s.kind == SegmentKind.thought)
        .toList();
    if (existing.isNotEmpty) {
      final found = existing.last;
      _buffer[_buffer.length - 1] = last.copyWith(
        segments: last.segments
            .map((s) => s == found
                ? s.copyWith(text: s.text + text)
                : s)
            .toList(),
      );
    } else {
      _buffer[_buffer.length - 1] = last.copyWith(
        segments: [
          ...last.segments,
          AssistantSegment(
            id: _uuid.v4(),
            kind: SegmentKind.thought,
            text: text,
          ),
        ],
      );
    }
    _bumpStreamingTimer();
    if (_loaded) _syncState();
  }

  void _ensureAssistantMessage() {
    if (_buffer.isEmpty || _buffer.last.role != ChatMessageRole.assistant) {
      _buffer.add(ChatMessage(
        id: _uuid.v4(),
        role: ChatMessageRole.assistant,
        content: '',
        isStreaming: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        segments: [],
      ));
      _bumpStreamingTimer();
    }
  }

  void _updateToolOutput(String toolId, String outText, String? status,
      {List<Map<String, String>> diffs = const [], String? terminalId}) {
    for (var i = 0; i < _buffer.length; i++) {
      final m = _buffer[i];
      for (final seg in m.segments) {
        if (seg.kind == SegmentKind.toolCall && seg.id == toolId) {
          final newMeta = Map<String, dynamic>.from(seg.metadata);
          if (outText.isNotEmpty) {
            newMeta['output'] = (newMeta['output'] ?? '') + outText;
          }
          if (status != null) {
            newMeta['status'] = status;
          }
          if (diffs.isNotEmpty) {
            final existing =
                (newMeta['diffs'] as List<dynamic>?)?.cast<Map<String, String>>() ??
                    [];
            newMeta['diffs'] = [...existing, ...diffs];
          }
          if (terminalId != null) {
            newMeta['terminalId'] = terminalId;
          }
          _buffer[i] = m.copyWith(
            segments: m.segments
                .map((s) => s == seg ? s.copyWith(metadata: newMeta) : s)
                .toList(),
          );
          _bumpStreamingTimer();
          if (_loaded) _syncState();
          return;
        }
      }
    }
  }

  void _handleLegacyNotification(Map<String, dynamic> params) {
    final isStreaming = params['isStreaming'] as bool? ?? false;
    final content = params['content'] as List<dynamic>? ?? [];

    if (!isStreaming) {
      for (var i = 0; i < _buffer.length; i++) {
        if (_buffer[i].isStreaming) {
          _buffer[i] = _buffer[i].copyWith(isStreaming: false);
        }
      }
      _syncState();
      return;
    }

    for (final block in content) {
      final type = block['type'] as String?;
      final text = block['text'] as String? ?? '';
      if (type == 'text') {
        _upsertMessage(text, ChatMessageRole.assistant, null);
      }
    }
  }

  void _addSegment(SegmentKind kind, String text, String toolId) {
    if (_buffer.isEmpty) return;
    final last = _buffer.last;
    final seg = AssistantSegment(
      id: toolId.isNotEmpty ? toolId : _uuid.v4(),
      kind: kind,
      text: text,
    );
    _buffer[_buffer.length - 1] = last.copyWith(segments: [...last.segments, seg]);
    if (_loaded) _syncState();
  }

  Future<void> sendMessage(String text, {List<Map<String, dynamic>>? extra}) async {
    final connection = _ref.read(connectionProvider);
    final notifier = _ref.read(connectionProvider.notifier);

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: ChatMessageRole.user,
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _buffer.add(userMsg);
    _syncState();

    final db = _ref.read(databaseProvider);
    await db.saveMessage(
      id: userMsg.id,
      sessionId: _sessionId,
      role: 'user',
      content: text,
      isStreaming: false,
    );

    if (connection.channel == null || connection.state is! Connected) {
      _buffer.add(ChatMessage(
        id: _uuid.v4(),
        role: ChatMessageRole.assistant,
        content: 'Not connected to agent. Please check the relay/daemon.',
        isStreaming: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _finalizeStreaming();
      if (_loaded) _syncState();
      return;
    }

    final id = notifier.sendSessionMessage(_sessionId, text, extra: extra);
    _pendingIds.add(id);
    _logBusy('sendMessage');
    _syncState();

    // After 30s, show a waiting message but keep the pending ID alive so
    // a late response is still processed (agent may be busy executing a tool).
    _timeoutMessageId = null;
    Future.delayed(const Duration(seconds: 30), () {
      if (!_pendingIds.contains(id)) return;
      final msg = ChatMessage(
        id: _uuid.v4(),
        role: ChatMessageRole.assistant,
        content: 'Agent is working... (may be busy executing a tool)',
        isStreaming: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      _timeoutMessageId = msg.id;
      _buffer.add(msg);
      _syncState();
    });

    // After 60s total, if the agent still hasn't responded, clean up the
    // pending ID and finalize any stuck streaming messages so isBusy
    // resets and the user can retry.
    Future.delayed(const Duration(seconds: 60), () {
      if (!_pendingIds.contains(id)) return;
      _pendingIds.remove(id);
      if (_timeoutMessageId != null) {
        for (var i = 0; i < _buffer.length; i++) {
          if (_buffer[i].id == _timeoutMessageId) {
            _buffer[i] = _buffer[i].copyWith(
              content:
                  'Agent did not respond within 60 seconds. You can try sending your message again.',
            );
            break;
          }
        }
      }
      _finalizeStreaming();
    });
  }

  /// Agent that owns this session, for per-agent preference keys.
  /// Falls back to the currently selected agent when the session list
  /// doesn't know this session (e.g. tests).
  String? get _agentIdForSession {
    try {
      final sessions = _ref.read(sessionListProvider).valueOrNull;
      if (sessions != null) {
        for (final s in sessions) {
          if (s.id == _sessionId && s.agentId != null) return s.agentId;
        }
      }
    } catch (_) {}
    try {
      return _ref.read(connectionProvider).selectedAgentId;
    } catch (_) {
      return null;
    }
  }

  /// Re-send the user's saved config choices (e.g. model) when the agent
  /// reports values that differ — e.g. defaults after a fresh load.
  /// Only applies choices the agent still offers, so stale picks are
  /// dropped silently instead of fighting the agent.
  Future<void> _reapplySavedConfigChoices(List<ConfigOption> configs) async {
    if (!_loaded || !_connected) return;
    final agentId = _agentIdForSession;
    if (agentId == null) return;
    Map<String, String> saved;
    try {
      final prefs = await _ref.read(preferencesServiceProvider.future);
      saved = prefs.getConfigChoices(agentId);
    } catch (_) {
      return;
    }
    if (saved.isEmpty || !mounted) return;
    for (final entry in saved.entries) {
      final opt = configs.where((c) => c.id == entry.key).firstOrNull;
      if (opt == null) continue;
      if (opt.currentValue == entry.value) continue;
      if (!opt.options.any((o) => o.value == entry.value)) continue;
      debugPrint(
          '[chat_provider] re-applying saved ${opt.id}=${entry.value} for session=$_sessionId');
      await setConfigOption(opt.id, entry.value);
      if (!mounted) return;
    }
  }

  Future<void> setConfigOption(String configId, String value) async {
    final notifier = _ref.read(connectionProvider.notifier);
    final connection = _ref.read(connectionProvider);

    // Persist per agent so the pick survives reloads/reconnects.
    try {
      final agentId = _agentIdForSession;
      if (agentId != null) {
        final prefs = await _ref.read(preferencesServiceProvider.future);
        await prefs.setConfigChoice(agentId, configId, value);
      }
    } catch (e) {
      debugPrint('[chat_provider] failed to persist config choice: $e');
    }

    notifier.sendRaw({
      'jsonrpc': '2.0',
      'id': DateTime.now().millisecondsSinceEpoch,
      'method': 'session/set_config_option',
      'params': {
        if (connection.selectedAgentId != null)
          'agentId': connection.selectedAgentId,
        'sessionId': _sessionId,
        'configId': configId,
        'value': value,
      },
    });

    final current = state.valueOrNull;
    if (current != null) {
      final updatedConfigs = current.configOptions.map((c) {
        if (c.id == configId) {
          return ConfigOption(
            id: c.id,
            name: c.name,
            description: c.description,
            category: c.category,
            currentValue: value,
            options: c.options,
          );
        }
        return c;
      }).toList();
      _setConfigOptions(updatedConfigs);
    }
  }

  void _handlePermissionRequest(int? requestId, Map<String, dynamic> params) {
    final toolCall = params['toolCall'] as Map<String, dynamic>?;
    final rawOptions = params['options'] as List<dynamic>?;
    _permissionRequest = PermissionRequest(
      sessionId: _sessionId,
      requestId: requestId ?? 0,
      title: toolCall?['title'] as String?,
      toolName: toolCall?['kind'] as String?,
      toolContent: (toolCall?['content'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          const [],
      options: rawOptions
              ?.map((e) => PermissionOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
    state = AsyncValue.data(ChatState(
      messages: List.of(_buffer),
      isBusy: _isBusy,
      availableCommands: _slashCommands,
      permissionRequest: _permissionRequest,
    ));
  }

  void respondToPermission(String optionId) {
    final req = _permissionRequest;
    if (req == null) return;
    final notifier = _ref.read(connectionProvider.notifier);
    notifier.sendRaw({
      'jsonrpc': '2.0',
      'id': req.requestId,
      'result': {
        'outcome': {
          'outcome': 'selected',
          'optionId': optionId,
        },
      },
    });
    _permissionRequest = null;
    state = AsyncValue.data(ChatState(
      messages: List.of(_buffer),
      isBusy: _isBusy,
      availableCommands: _slashCommands,
    ));
  }

  void dismissPermission() {
    final req = _permissionRequest;
    if (req == null) return;
    final notifier = _ref.read(connectionProvider.notifier);
    notifier.sendRaw({
      'jsonrpc': '2.0',
      'id': req.requestId,
      'result': {
        'outcome': {'outcome': 'cancelled'},
      },
    });
    _permissionRequest = null;
    state = AsyncValue.data(ChatState(
      messages: List.of(_buffer),
      isBusy: _isBusy,
      availableCommands: _slashCommands,
    ));
  }

  @override
  void dispose() {
    _streamingTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider.family<
    ChatNotifier, AsyncValue<ChatState>, (String, String)>(
  (ref, key) {
    final (sessionId, cwd) = key;
    return ChatNotifier(ref, sessionId, cwd);
  },
);
