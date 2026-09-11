import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:acp_remote/core/database/app_database.dart';
import 'package:acp_remote/core/models/assistant_segment.dart';
import 'package:acp_remote/core/models/chat_message.dart';
import 'package:acp_remote/core/models/connection_state.dart';
import 'package:acp_remote/core/providers/connection_provider.dart';
import 'package:acp_remote/core/providers/database_provider.dart';
import 'package:acp_remote/core/providers/session_list_provider.dart';
import 'package:acp_remote/core/providers/usage_provider.dart';
import 'package:acp_remote/features/chat/viewmodel/chat_provider.dart';

class _FakeSink implements WebSocketSink {
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => Future.value();
  @override
  Future<dynamic> get done => Future.value();
  @override
  Future<void> close([int? code, String? reason]) => Future.value();
}

class _FakeChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
  @override
  WebSocketSink get sink => _FakeSink();
  @override
  Stream<dynamic> get stream => const Stream.empty();
}

class MockConnectionNotifier extends ConnectionNotifier {
  final _messageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  int _counter = 100;

  MockConnectionNotifier(super.ref) {
    state = AcpConnection(
      channel: _FakeChannel(),
      state: const AcpConnectionState.connected(),
      paired: true,
      daemonConnected: true,
    );
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messageCtrl.stream;

  final sentPrompts = <Map<String, dynamic>>[];

  @override
  int sendSessionMessage(
    String sessionId,
    String text, {
    List<Map<String, dynamic>>? extra,
  }) {
    sentPrompts.add({'sessionId': sessionId, 'text': text});
    return ++_counter;
  }

  @override
  Future<int> loadSession(String sessionId, String cwd) async {
    return ++_counter;
  }

  final sentMessages = <Map<String, dynamic>>[];

  @override
  void sendRaw(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  void injectMessage(Map<String, dynamic> msg) {
    _messageCtrl.add(msg);
  }

  @override
  void dispose() {
    _messageCtrl.close();
    super.dispose();
  }
}

class _NoopSessionList extends SessionListNotifier {
  _NoopSessionList(super.ref);

  @override
  Future<void> loadSessions() async {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer createContainer({bool noopSessionList = false}) {
    return ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => db),
      connectionProvider.overrideWith((ref) {
        return MockConnectionNotifier(ref);
      }),
      // Prompt responses trigger a background session-list refresh (5s
      // timeout); neutralize it in tests that inject prompt responses so
      // no timers/state writes outlive the container.
      if (noopSessionList)
        sessionListProvider.overrideWith((ref) => _NoopSessionList(ref)),
    ]);
  }

  group('ChatNotifier', () {
    test('load messages and transition to data', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);

      final chat = container.read(chatProvider(('test-session', '/home')));

      // Initial state is loading
      expect(chat, isA<AsyncLoading<ChatState>>());

      // Wait for loadMessages() to complete
      await Future.delayed(const Duration(milliseconds: 100));

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.hasValue, isTrue);
      expect(state.valueOrNull!.messages, isEmpty);

      container.dispose();
    });

    test('sendMessage adds user message and isBusy', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.sendMessage('hello');

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 1);
      expect(state.valueOrNull!.messages.first.content, 'hello');
      expect(state.valueOrNull!.messages.first.role, ChatMessageRole.user);
      expect(state.valueOrNull!.isBusy, isTrue);

      container.dispose();
    });

    test('setConfigOption updates config options', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.injectMessage({
        'result': {
          'sessionId': 'test-session',
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'gpt-4',
              'options': [
                {'value': 'gpt-4', 'name': 'GPT-4'},
              ],
            },
          ],
        },
      });

      await Future.delayed(Duration.zero);

      await notifier.setConfigOption('model', 'gpt-3.5');

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.configOptions.length, 1);
      expect(state.valueOrNull!.configOptions.first.currentValue, 'gpt-3.5');
      expect(state.valueOrNull!.currentModel, 'gpt-3.5');

      container.dispose();
    });

    test('ignores configOptions from another session', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      // Inject configOptions with a different sessionId — must be ignored
      mock.injectMessage({
        'result': {
          'sessionId': 'other-session',
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'other-model',
              'options': [
                {'value': 'other-model', 'name': 'Other Model'},
              ],
            },
          ],
        },
      });

      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.configOptions, isEmpty);
      expect(state.valueOrNull!.currentModel, isNull);

      container.dispose();
    });

    test('ignores sessionId-less configOptions for another request', () async {
      // Regression: opencode's session/load result (no sessionId field) was
      // applied to every open chat, so opencode models showed in cursor's
      // model sheet. Responses that don't name our session AND don't answer
      // one of our pending requests must be ignored.
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.injectMessage({
        'id': 9999,
        'result': {
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'leaked-model',
              'options': [
                {'value': 'leaked-model', 'name': 'Leaked Model'},
              ],
            },
          ],
        },
      });

      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.configOptions, isEmpty);
      expect(state.valueOrNull!.currentModel, isNull);

      container.dispose();
    });

    test('applies sessionId-less configOptions from own load response',
        () async {
      // Agents may omit sessionId from new/load results; as long as the
      // response answers OUR pending load request it belongs to us.
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      // Mock loadSession() returns 101 for the first call, which the
      // ChatNotifier issues on construction and tracks as pending.
      mock.injectMessage({
        'id': 101,
        'result': {
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'own-model',
              'options': [
                {'value': 'own-model', 'name': 'Own Model'},
              ],
            },
          ],
        },
      });

      await Future.delayed(const Duration(milliseconds: 100));

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.configOptions.length, 1);
      expect(state.valueOrNull!.currentModel, 'own-model');

      container.dispose();
    });

    test('persists model choice and reapplies it on fresh configs', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.state = mock.state.copyWith(selectedAgentId: 'cursor');
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      Map<String, dynamic> modelResult(String current) => {
            'result': {
              'sessionId': 'test-session',
              'configOptions': [
                {
                  'id': 'model',
                  'name': 'Model',
                  'category': 'model',
                  'currentValue': current,
                  'options': [
                    {'value': 'cursor-default', 'name': 'Default'},
                    {'value': 'my-model', 'name': 'My Model'},
                  ],
                },
              ],
            },
          };

      mock.injectMessage(modelResult('cursor-default'));
      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.setConfigOption('model', 'my-model');
      expect(
        container
            .read(chatProvider(('test-session', '/home')))
            .valueOrNull!
            .currentModel,
        'my-model',
      );

      // Agent reports defaults again (fresh load) — saved pick must win.
      mock.sentMessages.clear();
      mock.injectMessage(modelResult('cursor-default'));
      await Future.delayed(const Duration(milliseconds: 200));

      final resent = mock.sentMessages.where(
        (m) =>
            m['method'] == 'session/set_config_option' &&
            (m['params'] as Map)['value'] == 'my-model',
      );
      expect(resent, isNotEmpty);
      expect(
        container
            .read(chatProvider(('test-session', '/home')))
            .valueOrNull!
            .currentModel,
        'my-model',
      );

      // A saved pick the agent no longer offers must NOT be re-sent.
      mock.sentMessages.clear();
      mock.injectMessage({
        'result': {
          'sessionId': 'test-session',
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'brand-new',
              'options': [
                {'value': 'brand-new', 'name': 'Brand New'},
              ],
            },
          ],
        },
      });
      await Future.delayed(const Duration(milliseconds: 200));

      expect(
        mock.sentMessages
            .where((m) => m['method'] == 'session/set_config_option'),
        isEmpty,
      );
      expect(
        container
            .read(chatProvider(('test-session', '/home')))
            .valueOrNull!
            .currentModel,
        'brand-new',
      );

      container.dispose();
    });

    test('cancelResponse sends session/cancel and clears busy', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.sendMessage('hello');
      expect(
        container
            .read(chatProvider(('test-session', '/home')))
            .valueOrNull!
            .isBusy,
        isTrue,
      );

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.sentMessages.clear();
      await notifier.cancelResponse();

      final cancel = mock.sentMessages.where(
        (m) => m['method'] == 'session/cancel',
      );
      expect(cancel, isNotEmpty);
      expect(
        (cancel.first['params'] as Map)['sessionId'],
        'test-session',
      );
      expect(
        container
            .read(chatProvider(('test-session', '/home')))
            .valueOrNull!
            .isBusy,
        isFalse,
      );

      container.dispose();
    });

    test('/usage answers locally from reported usage', () async {
      final container = createContainer(noopSessionList: true);
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'usage_update',
            'used': 8072,
            'size': 200000,
            'cost': {'amount': 0, 'currency': 'USD'},
          },
        },
      });
      await Future.delayed(Duration.zero);

      // Prompt id 102: 101 is the construction-time loadSession call.
      await notifier.sendMessage('hello');
      mock.injectMessage({
        'id': 102,
        'result': {
          'stopReason': 'end_turn',
          'usage': {
            'inputTokens': 6216,
            'outputTokens': 15,
            'cachedReadTokens': 1856,
          },
        },
      });
      await Future.delayed(Duration.zero);

      mock.sentPrompts.clear();
      await notifier.sendMessage('/usage');
      await Future.delayed(const Duration(milliseconds: 100));

      // No prompt left the phone — answered from accumulated usage data.
      expect(mock.sentPrompts, isEmpty);
      final messages =
          container.read(chatProvider(('test-session', '/home'))).valueOrNull!.messages;
      expect(messages.last.role, ChatMessageRole.assistant);
      expect(messages.last.content, contains('8,072 / 200,000'));
      expect(messages.last.content, contains('6,216 in'));
      expect(messages.last.content, contains('15 out'));
      expect(messages.last.content, contains('Cost: \$0'));

      container.dispose();
    });

    test('usage_update is mirrored into the usage tracker', () async {
      final container = createContainer(noopSessionList: true);
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.state = mock.state.copyWith(selectedAgentId: 'cursor');
      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'usage_update',
            'used': 9000,
            'size': 100000,
          },
        },
      });
      await Future.delayed(const Duration(milliseconds: 100));

      final snap = container
          .read(usageTrackerProvider)
          .byAgent['cursor'];
      expect(snap, isNotNull);
      expect(snap!.ctxUsed, 9000);
      expect(snap.contextFraction, closeTo(0.09, 0.0001));

      container.dispose();
    });

    test('/usage with no data explains instead of asking the agent', () async {
      final container = createContainer(noopSessionList: true);
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      await notifier.sendMessage('/usage');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mock.sentPrompts, isEmpty);
      final messages =
          container.read(chatProvider(('test-session', '/home'))).valueOrNull!.messages;
      expect(messages.last.content, contains('No usage data yet'));

      container.dispose();
    });

    test('other slash commands still forward to the agent', () async {
      // Documents the no-regression rule: agents execute unadvertised
      // native built-ins (e.g. opencode's /models), so only /usage is
      // ever answered locally.
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'available_commands_update',
            'availableCommands': [
              {'name': 'review', 'description': 'Review changes'},
            ],
          },
        },
      });
      await Future.delayed(Duration.zero);

      await notifier.sendMessage('/models');
      expect(mock.sentPrompts.length, 1);
      expect(mock.sentPrompts.first['text'], '/models');

      container.dispose();
    });

    test('stream update appends assistant content', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': 'Hello from agent',
            'messageId': 'msg-1',
          },
        },
      });

      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 1);
      expect(state.valueOrNull!.messages.first.content, 'Hello from agent');
      expect(
        state.valueOrNull!.messages.first.role,
        ChatMessageRole.assistant,
      );

      container.dispose();
    });

    test('respondToPermission clears permission request', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.injectMessage({
        'method': 'session/request_permission',
        'id': 42,
        'params': {
          'sessionId': 'test-session',
          'toolCall': {
            'title': 'Read file',
            'kind': 'read_file',
            'content': [],
          },
          'options': [
            {
              'optionId': 'allow_once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
            {'optionId': 'deny', 'name': 'Deny', 'kind': 'deny'},
          ],
        },
      });

      await Future.delayed(Duration.zero);

      var state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.permissionRequest, isNotNull);

      notifier.respondToPermission('allow_once');

      state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.permissionRequest, isNull);

      container.dispose();
    });

    test('dismissPermission clears permission request', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      mock.injectMessage({
        'method': 'session/request_permission',
        'id': 43,
        'params': {
          'sessionId': 'test-session',
          'toolCall': {
            'title': 'Execute',
            'kind': 'bash',
            'content': [],
          },
          'options': [
            {'optionId': 'allow_once', 'kind': 'allow_once'},
          ],
        },
      });

      await Future.delayed(Duration.zero);

      notifier.dismissPermission();

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.permissionRequest, isNull);

      container.dispose();
    });

    // ── Streaming types ──────────────────────────────────────────────

    test('stream thought_chunk adds thought segment', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': 'I am thinking...',
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 1);
      expect(state.valueOrNull!.messages.first.isStreaming, isTrue);
      expect(state.valueOrNull!.messages.first.segments.length, 1);
      expect(state.valueOrNull!.messages.first.segments.first.kind, SegmentKind.thought);
      expect(state.valueOrNull!.messages.first.segments.first.text, 'I am thinking...');

      container.dispose();
    });

    test('stream thought_chunk accumulates into existing thought', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': 'First part ',
          },
        },
      });
      await Future.delayed(Duration.zero);

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_thought_chunk',
            'content': 'second part',
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.first.segments.length, 1);
      expect(state.valueOrNull!.messages.first.segments.first.text, 'First part second part');

      container.dispose();
    });

    test('stream tool_call adds toolCall segment', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'tool_call',
            'title': 'read_file',
            'toolCallId': 'tool-1',
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 1);
      expect(state.valueOrNull!.messages.first.segments.length, 1);
      expect(state.valueOrNull!.messages.first.segments.first.kind, SegmentKind.toolCall);
      expect(state.valueOrNull!.messages.first.segments.first.id, 'tool-1');

      container.dispose();
    });

    test('stream tool_call_update appends output', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'tool_call',
            'title': 'bash',
            'toolCallId': 'tool-1',
          },
        },
      });
      await Future.delayed(Duration.zero);

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'tool-1',
            'content': [
              {'type': 'text', 'text': 'Command output'},
            ],
            'status': 'completed',
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      final seg = state.valueOrNull!.messages.first.segments.first;
      expect(seg.metadata['output'], 'Command output');
      expect(seg.metadata['status'], 'completed');

      container.dispose();
    });

    test('stream tool_call_update with diffs and terminalId', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'tool_call',
            'title': 'edit',
            'toolCallId': 'tool-2',
          },
        },
      });
      await Future.delayed(Duration.zero);

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'tool-2',
            'content': [
              {
                'type': 'diff',
                'path': 'file.txt',
                'oldText': 'old content',
                'newText': 'new content',
              },
              {'type': 'terminal', 'terminalId': 'term-42'},
            ],
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      final seg = state.valueOrNull!.messages.first.segments.first;
      expect(seg.metadata['diffs'], isList);
      expect((seg.metadata['diffs'] as List).length, 1);
      expect((seg.metadata['diffs'] as List).first['path'], 'file.txt');
      expect(seg.metadata['terminalId'], 'term-42');

      container.dispose();
    });

    test('stream plan adds plan segment', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'plan',
            'entries': [
              {'content': 'Step 1: Analyze'},
              {'content': 'Step 2: Implement'},
            ],
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.first.segments.length, 1);
      expect(state.valueOrNull!.messages.first.segments.first.kind, SegmentKind.plan);
      expect(state.valueOrNull!.messages.first.segments.first.text, contains('Step 1'));
      expect(state.valueOrNull!.messages.first.segments.first.text, contains('Step 2'));

      container.dispose();
    });

    test('stream config_option_update refreshes config options', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'config_option_update',
            'configOptions': [
              {
                'id': 'model',
                'name': 'Model',
                'category': 'model',
                'currentValue': 'claude-3',
                'options': [
                  {'value': 'claude-3', 'name': 'Claude 3'},
                  {'value': 'gpt-4', 'name': 'GPT-4'},
                ],
              },
              {
                'id': 'mode',
                'name': 'Mode',
                'category': 'mode',
                'currentValue': 'plan',
                'options': [],
              },
            ],
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.configOptions.length, 2);
      expect(state.valueOrNull!.currentModel, 'claude-3');
      expect(state.valueOrNull!.currentMode, 'plan');

      container.dispose();
    });

    test('stream available_commands_update updates slash commands', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'available_commands_update',
            'availableCommands': [
              {'name': '/help', 'description': 'Show help'},
              {'name': '/clear', 'description': 'Clear chat'},
            ],
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.availableCommands.length, 2);
      expect(state.valueOrNull!.availableCommands.first.name, '/help');

      container.dispose();
    });

    test('multiple agent_message_chunks accumulate in one message', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Same messageId — should accumulate
      for (final chunk in ['Hello ', 'world', '!']) {
        mock.injectMessage({
          'method': 'session/update',
          'params': {
            'sessionId': 'test-session',
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': chunk,
              'messageId': 'msg-chunk',
            },
          },
        });
      }
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 1);
      expect(state.valueOrNull!.messages.first.content, 'Hello world!');

      container.dispose();
    });

    test('agent_message_chunk without msgId appends to last streaming message',
        () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': 'First ',
          },
        },
      });
      await Future.delayed(Duration.zero);

      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': 'Second',
          },
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 1);
      expect(state.valueOrNull!.messages.first.content, 'First Second');

      container.dispose();
    });

    test('JSON-RPC response finalizes streaming and clears isBusy', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.sendMessage('hello');
      var state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.isBusy, isTrue);

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Inject a JSON-RPC response for the pending prompt request (id = 102)
      mock.injectMessage({
        'id': 102,
        'result': {'status': 'ok'},
      });
      await Future.delayed(Duration.zero);

      state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.isBusy, isFalse);

      container.dispose();
    });

    test('session/notification finalizes streaming', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Start a streaming assistant message
      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': 'streaming...',
          },
        },
      });
      await Future.delayed(Duration.zero);

      var state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.first.isStreaming, isTrue);

      // Legacy notification with isStreaming=false finalizes
      mock.injectMessage({
        'method': 'session/notification',
        'params': {
          'sessionId': 'test-session',
          'isStreaming': false,
          'content': [],
        },
      });
      await Future.delayed(Duration.zero);

      state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.first.isStreaming, isFalse);

      container.dispose();
    });

    // ── Multi-model selection ────────────────────────────────────────

    test('config options from session/new set model and mode', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'result': {
          'sessionId': 'test-session',
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'claude-opus',
              'options': [
                {'value': 'claude-opus', 'name': 'Claude Opus'},
                {'value': 'gpt-4', 'name': 'GPT-4'},
              ],
            },
            {
              'id': 'mode',
              'name': 'Mode',
              'category': 'mode',
              'currentValue': 'architect',
              'options': [],
            },
          ],
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.currentModel, 'claude-opus');
      expect(state.valueOrNull!.currentMode, 'architect');

      container.dispose();
    });

    test('setConfigOption switches model and updates state', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Pre-populate config options
      mock.injectMessage({
        'result': {
          'sessionId': 'test-session',
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'gpt-4',
              'options': [
                {'value': 'gpt-4', 'name': 'GPT-4'},
              ],
            },
          ],
        },
      });
      await Future.delayed(Duration.zero);

      // Switch model
      await notifier.setConfigOption('model', 'claude-opus');

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.currentModel, 'claude-opus');
      expect(state.valueOrNull!.configOptions.first.currentValue, 'claude-opus');

      container.dispose();
    });

    test('config option with mode category sets currentMode', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'result': {
          'sessionId': 'test-session',
          'configOptions': [
            {
              'id': 'mode',
              'name': 'Mode',
              'category': 'mode',
              'currentValue': 'code',
              'options': [],
            },
          ],
        },
      });
      await Future.delayed(Duration.zero);

      var state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.currentMode, 'code');

      await notifier.setConfigOption('mode', 'architect');
      state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.currentMode, 'architect');

      container.dispose();
    });

    test('config options from different sessionId are filtered', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      mock.injectMessage({
        'result': {
          'sessionId': 'wrong-session',
          'configOptions': [
            {
              'id': 'model',
              'name': 'Model',
              'category': 'model',
              'currentValue': 'wrong-model',
              'options': [],
            },
          ],
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.currentModel, isNull);

      container.dispose();
    });

    // ── Message persistence ──────────────────────────────────────────

    test('sendMessage saves user message to database', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.sendMessage('persist this');

      final saved = await db.getMessages('test-session');
      expect(saved.length, 1);
      expect(saved.first.role, 'user');
      expect(saved.first.content, 'persist this');

      container.dispose();
    });

    test('loadMessages loads persisted messages from database', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);

      // Pre-save messages to DB
      await db.saveMessage(
        id: 'existing-1',
        sessionId: 'test-session',
        role: 'user',
        content: 'Hello from before',
        isStreaming: false,
        createdAt: 1000,
      );
      await db.saveMessage(
        id: 'existing-2',
        sessionId: 'test-session',
        role: 'assistant',
        content: 'Response from before',
        isStreaming: false,
        createdAt: 2000,
      );

      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final state = container.read(chatProvider(('test-session', '/home')));
      // Should have loaded the pre-existing messages
      expect(state.valueOrNull!.messages.isNotEmpty, isTrue);
      expect(state.valueOrNull!.messages.map((m) => m.id),
          containsAll(['existing-1', 'existing-2']));

      container.dispose();
    });

    test('populateFromLoad saves assistant messages to database', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Simulate the load response (id=101 is the mock's loadSession return)
      mock.injectMessage({
        'id': 101,
        'result': {
          'messages': [
            {
              'id': 'loaded-msg-1',
              'role': 'assistant',
              'content': 'I was loaded from agent',
              'segments': [],
              'createdAt': 3000,
            },
          ],
        },
      });
      await Future.delayed(Duration.zero);

      // Verify message is in the buffer
      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.any((m) => m.id == 'loaded-msg-1'), isTrue);

      // Verify it's persisted to DB
      final saved = await db.getMessages('test-session');
      expect(saved.any((m) => m.id == 'loaded-msg-1'), isTrue);

      container.dispose();
    });

    test('populateFromLoad deduplicates existing messages', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));

      // Save a message that will already be in the buffer
      await db.saveMessage(
        id: 'existing-load',
        sessionId: 'test-session',
        role: 'assistant',
        content: 'Existing content',
        isStreaming: false,
        createdAt: 4000,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Load response includes message that's already in buffer + new one
      mock.injectMessage({
        'id': 101,
        'result': {
          'messages': [
            {
              'id': 'existing-load',
              'role': 'assistant',
              'content': 'Existing content',
              'segments': [],
              'createdAt': 4000,
            },
            {
              'id': 'new-load',
              'role': 'assistant',
              'content': 'New content from load',
              'segments': [],
              'createdAt': 5000,
            },
          ],
        },
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      // existing-load should only appear once
      final existingCount = state.valueOrNull!.messages
          .where((m) => m.id == 'existing-load').length;
      expect(existingCount, 1);
      // new-load should be present
      expect(state.valueOrNull!.messages.any((m) => m.id == 'new-load'), isTrue);

      container.dispose();
    });

    // ── Error handling ───────────────────────────────────────────────

    test('sendMessage when disconnected shows not connected message', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);

      // Override connection to be disconnected (no channel)
      final disconnectedMock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;
      disconnectedMock.state = disconnectedMock.state.copyWith(clearChannel: true);

      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.sendMessage('hello');

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.messages.length, 2);
      expect(state.valueOrNull!.messages.first.role, ChatMessageRole.user);
      expect(state.valueOrNull!.messages.last.content,
          contains('Not connected'));
      expect(state.valueOrNull!.isBusy, isFalse);

      container.dispose();
    });

    test('handles JSON-RPC error response gracefully', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      final notifier = container.read(
        chatProvider(('test-session', '/home')).notifier,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      await notifier.sendMessage('hello');
      expect(container.read(chatProvider(('test-session', '/home')))
          .valueOrNull!.isBusy, isTrue);

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Inject an error response
      mock.injectMessage({
        'id': 102,
        'error': {'code': -32000, 'message': 'session not found'},
      });
      await Future.delayed(Duration.zero);

      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.valueOrNull!.isBusy, isFalse);
      // Should add a message about the session
      expect(state.valueOrNull!.messages.any((m) =>
          m.content.contains('no longer exists')), isTrue);

      container.dispose();
    });

    test('handles malformed stream payload without crashing', () async {
      final container = createContainer();
      container.read(activeSessionsProvider);
      container.read(chatProvider(('test-session', '/home')));
      await Future.delayed(const Duration(milliseconds: 100));

      final mock = container.read(connectionProvider.notifier)
          as MockConnectionNotifier;

      // Missing 'update' key
      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
        },
      });

      // Unknown update type
      mock.injectMessage({
        'method': 'session/update',
        'params': {
          'sessionId': 'test-session',
          'update': {
            'sessionUpdate': 'unknown_type',
            'content': 'test',
          },
        },
      });

      await Future.delayed(Duration.zero);

      // State should still be valid
      final state = container.read(chatProvider(('test-session', '/home')));
      expect(state.hasValue, isTrue);

      container.dispose();
    });
  });
}
