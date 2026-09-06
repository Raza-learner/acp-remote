import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class PairedDevices extends Table {
  TextColumn get code => text()();
  TextColumn get deviceName => text()();
  RealColumn get pairedAt => real()();
  RealColumn get lastConnectedAt => real()();

  @override
  Set<Column> get primaryKey => {code};
}

class SessionCache extends Table {
  TextColumn get id => text()();
  TextColumn get deviceCode => text()();
  TextColumn get title => text().nullable()();
  TextColumn get cwd => text()();
  RealColumn get updatedAt => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get segmentsJson => text().nullable()();
  IntColumn get isStreaming => integer()();
  RealColumn get createdAt => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class SessionSettings extends Table {
  TextColumn get targetId => text()();
  TextColumn get cwd => text()();

  @override
  Set<Column> get primaryKey => {targetId};
}

@DriftDatabase(
  tables: [
    PairedDevices,
    SessionCache,
    ChatMessages,
    SessionSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openDb());
  AppDatabase.test() : super(NativeDatabase.memory());

  static LazyDatabase _openDb() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'acp.sqlite'));
      return NativeDatabase(file);
    });
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // v2: clear session cache so existing cross-agent cached sessions
          // are reloaded cleanly with the new agent-aware relay logic.
          await delete(sessionCache).go();
        }
        if (from < 3) {
          // v3: clear session cache once so sessions leaked from a different
          // PC (via the shared relay store) are evicted. The relay now
          // scopes session/list per daemon, so the list repopulates cleanly.
          await delete(sessionCache).go();
        }
      },
    );
  }

  Future<void> savePairedDevice(String code, String deviceName) async {
    await into(pairedDevices).insertOnConflictUpdate(
      PairedDevicesCompanion(
        code: Value(code),
        deviceName: Value(deviceName),
        pairedAt: Value(DateTime.now().millisecondsSinceEpoch.toDouble()),
        lastConnectedAt: Value(DateTime.now().millisecondsSinceEpoch.toDouble()),
      ),
    );
  }

  Future<void> updateLastConnected(String code) async {
    await (update(pairedDevices)..where((t) => t.code.equals(code))).write(
      PairedDevicesCompanion(
        lastConnectedAt: Value(DateTime.now().millisecondsSinceEpoch.toDouble()),
      ),
    );
  }

  Future<PairedDevice?> getPairedDevice(String code) async {
    return (select(pairedDevices)..where((t) => t.code.equals(code))).getSingleOrNull();
  }

  Future<List<PairedDevice>> getAllPairedDevices() async {
    return select(pairedDevices).get();
  }

  Future<void> removePairedDevice(String code) async {
    await (delete(pairedDevices)..where((t) => t.code.equals(code))).go();
  }

  Future<void> cacheSession({
    required String id,
    required String deviceCode,
    String? title,
    required String cwd,
    required double updatedAt,
  }) async {
    await into(sessionCache).insertOnConflictUpdate(
      SessionCacheCompanion(
        id: Value(id),
        deviceCode: Value(deviceCode),
        title: Value(title),
        cwd: Value(cwd),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<List<SessionCacheData>> getCachedSessions(String deviceCode) async {
    return (select(sessionCache)..where((t) => t.deviceCode.equals(deviceCode)))
        .get();
  }

  Future<void> removeCachedSession(String id) async {
    await (delete(sessionCache)..where((t) => t.id.equals(id))).go();
  }

  Future<void> saveMessage({
    required String id,
    required String sessionId,
    required String role,
    required String content,
    String? segmentsJson,
    required bool isStreaming,
    int? createdAt,
  }) async {
    await into(chatMessages).insertOnConflictUpdate(
      ChatMessagesCompanion(
        id: Value(id),
        sessionId: Value(sessionId),
        role: Value(role),
        content: Value(content),
        segmentsJson: Value(segmentsJson),
        isStreaming: Value(isStreaming ? 1 : 0),
        createdAt: Value((createdAt ?? DateTime.now().millisecondsSinceEpoch).toDouble()),
      ),
    );
  }

  Future<List<ChatMessage>> getMessages(String sessionId) async {
    return (select(chatMessages)..where((t) => t.sessionId.equals(sessionId)))
        .get();
  }

  Future<List<ChatMessage>> getRecentMessages(String sessionId, {int limit = 5}) async {
    return (select(chatMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
  }

  Future<void> deleteSessionMessages(String sessionId) async {
    await (delete(chatMessages)..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  Future<String?> getDefaultCwd() async {
    final setting = await (select(sessionSettings)
          ..where((t) => t.targetId.equals('default')))
        .getSingleOrNull();
    return setting?.cwd;
  }

  Future<void> setDefaultCwd(String cwd) async {
    await into(sessionSettings).insertOnConflictUpdate(
      SessionSettingsCompanion(
        targetId: const Value('default'),
        cwd: Value(cwd),
      ),
    );
  }

  Future<void> clearAll() async {
    await delete(pairedDevices).go();
    await delete(sessionCache).go();
    await delete(chatMessages).go();
  }
}
