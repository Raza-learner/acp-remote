import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:acp_remote/core/database/app_database.dart';
import 'package:acp_remote/core/models/connection_state.dart';
import 'package:acp_remote/core/providers/connection_provider.dart';
import 'package:acp_remote/core/providers/database_provider.dart';
import 'package:acp_remote/core/providers/session_list_provider.dart';

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

class _MockConn extends ConnectionNotifier {
  final _msgCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? lastRaw;
  int _rid = 0;

  _MockConn(super.ref) {
    state = AcpConnection(
      channel: _FakeChannel(),
      state: const AcpConnectionState.disconnected(),
    );
  }

  @override
  Stream<Map<String, dynamic>> get messages => _msgCtrl.stream;

  @override
  void sendRaw(Map<String, dynamic> message) {
    _rid = message['id'] as int;
    lastRaw = message;
  }

  void respond(Map<String, dynamic> result) {
    _msgCtrl.add({'id': _rid, 'result': result});
  }

  void setConnected() {
    state = state.copyWith(
      state: const AcpConnectionState.connected(),
      paired: true,
      daemonConnected: true,
    );
  }

  void injectMessage(Map<String, dynamic> msg) {
    _msgCtrl.add(msg);
  }

  @override
  void dispose() {
    _msgCtrl.close();
    super.dispose();
  }
}

ProviderContainer createContainer(AppDatabase db) {
  return ProviderContainer(overrides: [
    databaseProvider.overrideWith((ref) => db),
    connectionProvider.overrideWith((ref) => _MockConn(ref)),
  ]);
}

void main() {
  group('AcpSession', () {
    test('fromJson parses all fields', () {
      final s = AcpSession.fromJson({
        'id': 's-1',
        'title': 'Title',
        'cwd': '/home',
        'updatedAt': 1000,
        'agentId': 'a-1',
      });
      expect(s.id, 's-1');
      expect(s.title, 'Title');
      expect(s.cwd, '/home');
      expect(s.updatedAt, 1000);
      expect(s.agentId, 'a-1');
    });

    test('fromJson parses sessionId and name keys', () {
      final s = AcpSession.fromJson({
        'sessionId': 's-2',
        'name': 'Session 2',
        'cwd': '/work',
        'createdAt': 2000,
      });
      expect(s.id, 's-2');
      expect(s.title, 'Session 2');
      expect(s.cwd, '/work');
    });

    test('fromJson handles missing optionals', () {
      final s = AcpSession.fromJson({'id': 's-3', 'cwd': '/tmp'});
      expect(s.id, 's-3');
      expect(s.title, isNull);
      expect(s.cwd, '/tmp');
      expect(s.updatedAt, 0);
      expect(s.agentId, isNull);
    });

    test('fromJson normalizes ms timestamp to seconds', () {
      final s = AcpSession.fromJson({
        'id': 's-4',
        'cwd': '/tmp',
        'updatedAt': 1712345678000,
      });
      expect(s.updatedAt, closeTo(1712345678, 1));
    });

    test('fromJson keeps s timestamp as-is', () {
      final s = AcpSession.fromJson({
        'id': 's-5',
        'cwd': '/tmp',
        'updatedAt': 1712345678,
      });
      expect(s.updatedAt, 1712345678);
    });

    test('fromJson parses ISO string timestamp', () {
      final s = AcpSession.fromJson({
        'id': 's-6',
        'cwd': '/tmp',
        'updatedAt': '2024-04-05T12:34:56.000Z',
      });
      expect(s.updatedAt, greaterThan(0));
    });
  });

  group('SessionListNotifier', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.test();
    });

    tearDown(() async {
      await db.close();
    });

    test('deleteSession removes session from state', () async {
      final container = createContainer(db);
      final notifier = container.read(sessionListProvider.notifier);

      notifier.state = AsyncValue.data([
        AcpSession(id: 's-1', cwd: '/home', updatedAt: 1000, title: 'T'),
        AcpSession(id: 's-2', cwd: '/work', updatedAt: 2000, title: 'T2'),
      ]);

      await notifier.deleteSession('s-1');
      final state = container.read(sessionListProvider);
      expect(state.valueOrNull!.length, 1);
      expect(state.valueOrNull!.first.id, 's-2');
      container.dispose();
    });

    test('deleteSession also removes from cache DB', () async {
      final container = createContainer(db);
      final notifier = container.read(sessionListProvider.notifier);

      await db.cacheSession(
        id: 's-1', deviceCode: 'code', title: 'T', cwd: '/home', updatedAt: 1000,
      );

      await notifier.deleteSession('s-1');
      final cached = await db.getCachedSessions('code');
      expect(cached, isEmpty);
      container.dispose();
    });

    test('createSession adds session to state and cache', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;

      // Seed state with data so createSession can append to it
      final notifier = container.read(sessionListProvider.notifier);
      notifier.state = AsyncValue.data([]);

      final future = notifier.createSession('/home');
      await Future.delayed(Duration.zero);

      mock.respond({'sessionId': 'new-sess', 'title': 'New Session'});
      final session = await future;

      expect(session, isNotNull);
      expect(session!.id, 'new-sess');
      expect(session.title, 'New Session');
      expect(session.cwd, '/home');

      // Session should be cached in DB (deviceCode = '' since no pairingCode set)
      final cached = await db.getCachedSessions('');
      expect(cached.any((s) => s.id == 'new-sess'), isTrue);
      container.dispose();
    });

    test('createSession returns null when channel is null', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;
      // Set channel to null
      mock.state = mock.state.copyWith(clearChannel: true);

      await expectLater(
        container.read(sessionListProvider.notifier).createSession('/home'),
        throwsA(isA<SessionCreateException>()),
      );
      container.dispose();
    });

    test('loadSessions merges remote with cached sessions', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;

      // Seed a cached session with empty pairing code (mock has no pairingCode)
      await db.cacheSession(
        id: 'cached-1', deviceCode: '', title: 'Cached', cwd: '/old', updatedAt: 1000,
      );

      final notifier = container.read(sessionListProvider.notifier);
      notifier.loadSessions();
      await Future.delayed(Duration.zero);

      mock.respond({
        'sessions': [
          {'id': 'remote-1', 'cwd': '/new', 'updatedAt': 2000, 'title': 'Remote'},
        ],
      });

      await Future.delayed(Duration.zero);
      final state = container.read(sessionListProvider);

      expect(state.valueOrNull!.length, 2);
      expect(state.valueOrNull!.any((s) => s.id == 'cached-1'), isTrue);
      expect(state.valueOrNull!.any((s) => s.id == 'remote-1'), isTrue);
      container.dispose();
    });

    test('loadSessions filters out deleted session IDs', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;

      await db.cacheSession(
        id: 'deleted-sess', deviceCode: '', title: 'Gone', cwd: '/gone', updatedAt: 1000,
      );

      final notifier = container.read(sessionListProvider.notifier);
      await notifier.deleteSession('deleted-sess');

      notifier.loadSessions();
      await Future.delayed(Duration.zero);
      mock.respond({'sessions': []});
      await Future.delayed(Duration.zero);

      final state = container.read(sessionListProvider);
      expect(state.valueOrNull!.any((s) => s.id == 'deleted-sess'), isFalse);
      container.dispose();
    });

    test('loadSessions when disconnected returns empty', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;
      // Remove channel so connection.channel is null
      mock.state = mock.state.copyWith(clearChannel: true);

      await container.read(sessionListProvider.notifier).loadSessions();
      final state = container.read(sessionListProvider);
      expect(state.valueOrNull, isEmpty);
      container.dispose();
    });

    test('ActiveSessionsNotifier marks active and auto-expires after 5s', () async {
      final container = createContainer(db);
      final notifier = container.read(activeSessionsProvider.notifier);

      expect(notifier.state, isEmpty);
      notifier.markActive('sess-1');
      expect(notifier.state, contains('sess-1'));
      expect(notifier.latestSessionId, 'sess-1');

      await Future.delayed(const Duration(seconds: 6));
      expect(notifier.state, isEmpty);
      container.dispose();
    });

    test('ActiveSessionsNotifier markInactive removes session', () async {
      final container = createContainer(db);
      final notifier = container.read(activeSessionsProvider.notifier);

      notifier.markActive('sess-1');
      notifier.markInactive('sess-1');
      expect(notifier.state, isEmpty);
      container.dispose();
    });

    // ── Error handling ───────────────────────────────────────────────

    test('loadSessions handles remote error gracefully', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;
      mock.setConnected();

      final notifier = container.read(sessionListProvider.notifier);
      notifier.state = const AsyncValue.data([]);

      notifier.loadSessions();
      await Future.delayed(Duration.zero);

      // Simulate error response from relay
      mock.respond({});  // No sessions key
      await Future.delayed(Duration.zero);

      final state = container.read(sessionListProvider);
      expect(state.hasValue, isTrue);
      expect(state.valueOrNull, isEmpty);
      container.dispose();
    });

    test('createSession handles error response', () async {
      final container = createContainer(db);
      final mock = container.read(connectionProvider.notifier) as _MockConn;
      mock.setConnected();

      final notifier = container.read(sessionListProvider.notifier);
      notifier.state = const AsyncValue.data([]);

      final future = notifier.createSession('/home');
      await Future.delayed(Duration.zero);

      // Simulate error — no result key
      mock.respond({'error': 'failed'});

      await expectLater(future, throwsA(isA<SessionCreateException>()));
      container.dispose();
    });

    test('ActiveSessionsNotifier.clear removes all timers', () async {
      final container = createContainer(db);
      final notifier = container.read(activeSessionsProvider.notifier);

      notifier.markActive('sess-a');
      notifier.markActive('sess-b');
      expect(notifier.state.length, 2);

      notifier.clear();
      expect(notifier.state, isEmpty);
      expect(notifier.latestSessionId, isNull);
      container.dispose();
    });
  });
}
