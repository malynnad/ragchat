import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../rag/models.dart';

/// 记忆类型（CONTEXT.md 术语：fact/preference/event/relation）。
enum MemoryKind { fact, preference, event, relation }

/// 记忆条目：一句稳定事实 + 类型 + 重要度（ADR-0009 复活 ADR-0001）。
/// 被取代的条目 active=false，不物理删除，可追溯。
class MemoryEntry {
  MemoryEntry({
    required this.id,
    required this.content,
    this.kind = MemoryKind.fact,
    this.importance = 3,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastUsedAt,
    this.source,
    this.active = true,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String content;
  final MemoryKind kind;

  /// 1–5，提取时模型打分；system 注入按此排序。
  final int importance;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 检索命中时刷新（v2 情景记忆衰减清理用，MVP 只记录）。
  final DateTime? lastUsedAt;

  /// 来源会话 id，导出继承时可溯源。
  final String? source;
  final bool active;

  MemoryEntry copyWith({
    String? content,
    MemoryKind? kind,
    int? importance,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool? active,
  }) => MemoryEntry(
    id: id,
    content: content ?? this.content,
    kind: kind ?? this.kind,
    importance: importance ?? this.importance,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    source: source,
    active: active ?? this.active,
  );
}

/// 会话记录：turns 的宿主（ADR-0009：会话持久化）。
class SessionRecord {
  SessionRecord({required this.id, DateTime? createdAt, DateTime? updatedAt})
    : createdAt = createdAt ?? DateTime.now(),
      updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// App 数据库接缝：memories / sessions / turns（schema v3，ADR-0009）。
/// 由 RAG 时代的 rag.db 演进：v1/v2 表（documents/chunks/categories/meta）
/// 保留不动——代码删、数据留（ADR-0009 决策 1）。
/// 迁移沿用 VectorStore 模式：onCreate/onUpgrade 共用幂等 _createSchema。
class AppDb {
  AppDb._(this._db);

  final Database _db;

  static const int schemaVersion = 3;

  /// 打开（或升级）持久化库。旧 v2 库（RAG 版覆盖安装）自动升 v3，数据完好。
  static Future<AppDb> openFile(String path) async {
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _createSchema,
      onUpgrade: (db, oldVersion, newVersion) => _createSchema(db, newVersion),
    );
    return AppDb._(db);
  }

  /// 用已打开的 Database 构造（测试注入 ffi 内存库）。
  static Future<AppDb> fromDatabase(Database db) async {
    await _createSchema(db, schemaVersion);
    return AppDb._(db);
  }

  /// 全部 IF NOT EXISTS + 幂等，可重入（v1→v2→v3 任意起点）。
  /// 新装也会建出空置的旧表：无害，且恢复备份场景语义一致。
  static Future<void> _createSchema(Database db, int version) async {
    // ---- v1/v2（RAG 遗产，仅建表不再使用）----
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        format TEXT NOT NULL,
        chunk_count INTEGER NOT NULL,
        ingested_at INTEGER NOT NULL,
        content BLOB
      )''');
    final cols = await db.rawQuery('PRAGMA table_info(documents)');
    if (!cols.any((c) => c['name'] == 'category')) {
      await db.execute(
        "ALTER TABLE documents ADD COLUMN category TEXT NOT NULL DEFAULT '未分类'",
      );
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chunks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        chunk_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        vector BLOB NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(doc_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories(
        name TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )''');
    await db.insert('categories', {
      'name': '未分类',
      'created_at': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    // ---- v3（陪聊：记忆 + 会话）----
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories(
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        kind TEXT NOT NULL,
        importance INTEGER NOT NULL DEFAULT 3,
        embedding BLOB,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_used_at INTEGER,
        source TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions(
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS turns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        turn_index INTEGER NOT NULL,
        question TEXT NOT NULL,
        answer TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_turns_session ON turns(session_id)',
    );
  }

  // ---- 记忆条目 ----

  /// 写入或整条覆盖（按 id）。提取新增与导入 upsert 共用。
  Future<void> upsertMemory(MemoryEntry m) async {
    await _db.insert(
      'memories',
      _memoryRow(m),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// active 记忆，按 importance 降序、同分按更新时间新者在前（system 注入序）。
  Future<List<MemoryEntry>> activeMemories() async {
    final rows = await _db.query(
      'memories',
      where: 'active = 1',
      orderBy: 'importance DESC, updated_at DESC',
    );
    return [for (final r in rows) _memoryFromRow(r)];
  }

  /// 全部记忆（含停用），记忆页展示用。
  Future<List<MemoryEntry>> allMemories() async {
    final rows = await _db.query(
      'memories',
      orderBy: 'active DESC, importance DESC, updated_at DESC',
    );
    return [for (final r in rows) _memoryFromRow(r)];
  }

  Future<MemoryEntry?> memory(String id) async {
    final rows = await _db.query('memories', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _memoryFromRow(rows.first);
  }

  Future<void> deactivateMemory(String id) async {
    await _db.update(
      'memories',
      {'active': 0, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMemory(String id) async {
    await _db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> memoryCount() async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM memories WHERE active = 1',
    );
    return r.first['n'] as int;
  }

  static Map<String, Object?> _memoryRow(MemoryEntry m) => {
    'id': m.id,
    'content': m.content,
    'kind': m.kind.name,
    'importance': m.importance,
    'embedding': null, // v2 情景记忆再启用，导入导出均不携带
    'created_at': m.createdAt.millisecondsSinceEpoch,
    'updated_at': m.updatedAt.millisecondsSinceEpoch,
    'last_used_at': m.lastUsedAt?.millisecondsSinceEpoch,
    'source': m.source,
    'active': m.active ? 1 : 0,
  };

  static MemoryEntry _memoryFromRow(Map<String, Object?> r) => MemoryEntry(
    id: r['id'] as String,
    content: r['content'] as String,
    kind: MemoryKind.values.byName(r['kind'] as String),
    importance: r['importance'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    lastUsedAt: r['last_used_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['last_used_at'] as int),
    source: r['source'] as String?,
    active: (r['active'] as int) == 1,
  );

  // ---- 会话与轮次（ADR-0009：持久化）----

  /// 新建会话，返回记录。id 用时间戳 + 随机后缀，纯 Dart 无需 uuid 依赖。
  Future<SessionRecord> createSession() async {
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(0xffff).toRadixString(36).padLeft(4, '0')}';
    final s = SessionRecord(id: id);
    await _db.insert('sessions', {
      'id': s.id,
      'created_at': s.createdAt.millisecondsSinceEpoch,
      'updated_at': s.updatedAt.millisecondsSinceEpoch,
    });
    return s;
  }

  /// 最近一个会话（重启恢复用），无则 null。
  /// 按 rowid 取：插入序单调，不受毫秒精度撞车影响。
  Future<SessionRecord?> latestSession() async {
    final rows = await _db.query('sessions', orderBy: 'rowid DESC', limit: 1);
    if (rows.isEmpty) return null;
    return SessionRecord(
      id: rows.first['id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        rows.first['created_at'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        rows.first['updated_at'] as int,
      ),
    );
  }

  /// 追加一轮（仅成功完成的轮次进历史，错误轮由调用方跳过）。
  Future<void> appendTurn(String sessionId, SessionTurn turn) async {
    await _db.transaction((txn) async {
      final r = await txn.rawQuery(
        'SELECT COALESCE(MAX(turn_index), -1) + 1 AS next FROM turns WHERE session_id = ?',
        [sessionId],
      );
      await txn.insert('turns', {
        'session_id': sessionId,
        'turn_index': r.first['next'] as int,
        'question': turn.question,
        'answer': turn.answer,
        'created_at': _now(),
      });
      await txn.update(
        'sessions',
        {'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  /// 某会话的全部轮次，按 turn_index 升序。
  Future<List<SessionTurn>> sessionTurns(String sessionId) async {
    final rows = await _db.query(
      'turns',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'turn_index ASC',
    );
    return [
      for (final r in rows)
        SessionTurn(
          question: r['question'] as String,
          answer: r['answer'] as String,
        ),
    ];
  }

  /// 清空全部会话（清空数据入口用；记忆独立，不受影响）。
  Future<void> deleteAllSessions() async {
    await _db.transaction((txn) async {
      await txn.delete('turns');
      await txn.delete('sessions');
    });
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> close() => _db.close();
}
