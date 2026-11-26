import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../rag/models.dart';
import '../rag/vector_math.dart';

/// 记忆类型（CONTEXT.md 术语：fact/preference/event/relation）。
enum MemoryKind { fact, preference, event, relation }

/// 检索投影（ADR-0016）：只带检索要用的字段，不拖 MemoryEntry 全量。
class MemoryVector {
  const MemoryVector({
    required this.id,
    required this.content,
    required this.importance,
    required this.vector,
  });

  final String id;
  final String content;

  /// 1–5，混合排序时按 0.15 权重参与。
  final int importance;

  /// 已 L2 归一化，余弦 = 点积。
  final Float32List vector;
}

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
/// 用量合计（今日 / 累计）。
class UsageSummary {
  const UsageSummary({
    required this.promptTokens,
    required this.completionTokens,
    required this.cost,
    required this.count,
  });

  final int promptTokens;
  final int completionTokens;
  final double cost;
  final int count;

  int get totalTokens => promptTokens + completionTokens;

  static const empty = UsageSummary(
    promptTokens: 0,
    completionTokens: 0,
    cost: 0,
    count: 0,
  );
}

/// 迁移沿用 VectorStore 模式：onCreate/onUpgrade 共用幂等 _createSchema。
class AppDb {
  AppDb._(this._db);

  final Database _db;

  /// v5 = ADR-0016 情景记忆向量检索：memories 加向量归属与时间。
  static const int schemaVersion = 5;

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
    // ---- v4（云端用量账本）----
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usage_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        model TEXT NOT NULL,
        prompt_tokens INTEGER NOT NULL,
        completion_tokens INTEGER NOT NULL,
        cost REAL NOT NULL DEFAULT 0
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
        active INTEGER NOT NULL DEFAULT 1,
        embedding_model TEXT,
        embedded_at INTEGER
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
    // ---- v5（ADR-0016：向量归属）----
    // 老库 memories 已存在，CREATE IF NOT EXISTS 不会补列，所以按 PRAGMA 逐列加；
    // 与 documents.category 同一套幂等写法，v3/v4 库都能升上来。
    final memCols = await db.rawQuery('PRAGMA table_info(memories)');
    bool hasMemCol(String name) => memCols.any((c) => c['name'] == name);
    if (!hasMemCol('embedding_model')) {
      await db.execute('ALTER TABLE memories ADD COLUMN embedding_model TEXT');
    }
    if (!hasMemCol('embedded_at')) {
      await db.execute('ALTER TABLE memories ADD COLUMN embedded_at INTEGER');
    }
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
    // 内容可能变了，旧向量一律作废（ADR-0016）：insert/replace 后由后台补算。
    'embedding': null,
    'embedding_model': null,
    'embedded_at': null,
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

  // ---- 情景记忆向量（ADR-0016）----

  /// 写入条目的向量。只动向量三列，不碰 updated_at：
  /// 补算不是用户改动，不该让它抢到排序前面。
  Future<void> setMemoryEmbedding(
    String id,
    Float32List vector, {
    required String modelId,
  }) async {
    await _db.update(
      'memories',
      {
        'embedding': encodeVector(vector),
        'embedding_model': modelId,
        'embedded_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 待补向量的 active 条目：没向量、或向量来自别的模型。
  /// 换模型/换量化后旧向量就是噪音，一律当作没算过（ADR-0016 决策 4）。
  Future<List<MemoryEntry>> memoriesNeedingEmbedding(
    String modelId, {
    int limit = 32,
  }) async {
    final rows = await _db.query(
      'memories',
      where:
          'active = 1 AND (embedding IS NULL OR embedding_model IS NULL '
          'OR embedding_model != ?)',
      whereArgs: [modelId],
      orderBy: 'importance DESC, updated_at DESC',
      limit: limit,
    );
    return [for (final r in rows) _memoryFromRow(r)];
  }

  /// 待补向量条数（记忆页/设置页展示进度用）。
  Future<int> pendingEmbeddingCount(String modelId) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM memories '
      'WHERE active = 1 AND (embedding IS NULL OR embedding_model IS NULL '
      'OR embedding_model != ?)',
      [modelId],
    );
    return r.first['n'] as int;
  }

  /// 检索用投影：限定模型、只取 active、向量已归一化（余弦退化成点积）。
  /// 当前模型下的脏数据（BLOB 长度不对）直接跳过，宁可少一条也不让检索崩。
  Future<List<MemoryVector>> memoryVectors(String modelId) async {
    final rows = await _db.query(
      'memories',
      columns: ['id', 'content', 'importance', 'embedding'],
      where: 'active = 1 AND embedding_model = ? AND embedding IS NOT NULL',
      whereArgs: [modelId],
    );
    final out = <MemoryVector>[];
    for (final r in rows) {
      final blob = r['embedding'];
      if (blob is! Uint8List) continue;
      final Float32List raw;
      try {
        raw = decodeVector(blob);
      } on ArgumentError {
        continue;
      }
      out.add(
        MemoryVector(
          id: r['id'] as String,
          content: r['content'] as String,
          importance: r['importance'] as int,
          vector: normalized(raw),
        ),
      );
    }
    return out;
  }

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

  /// 导出用：全部会话 + 轮次（纯 JSON 结构，不含 rowid）。
  Future<List<Map<String, Object?>>> dumpSessions() async {
    final sessions = await _db.query('sessions', orderBy: 'rowid ASC');
    final turns = await _db.query(
      'turns',
      orderBy: 'session_id ASC, turn_index ASC',
    );
    final bySession = <String, List<Map<String, Object?>>>{};
    for (final t in turns) {
      bySession
          .putIfAbsent(t['session_id'] as String, () => [])
          .add({
            'question': t['question'],
            'answer': t['answer'],
            'createdAt': t['created_at'],
          });
    }
    return [
      for (final s in sessions)
        {
          'id': s['id'],
          'createdAt': s['created_at'],
          'updatedAt': s['updated_at'],
          'turns': bySession[s['id']] ?? const [],
        },
    ];
  }

  /// 导入用：整库替换会话与记忆（在同一个事务里，失败自动回滚）。
  Future<void> restoreAll({
    required List<Map<String, Object?>> sessions,
    required List<MemoryEntry> memories,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('turns');
      await txn.delete('sessions');
      await txn.delete('memories');
      for (final s in sessions) {
        final sid = s['id'] as String;
        final created = (s['createdAt'] as num?)?.toInt() ?? _now();
        final updated = (s['updatedAt'] as num?)?.toInt() ?? created;
        await txn.insert('sessions', {
          'id': sid,
          'created_at': created,
          'updated_at': updated,
        });
        final turns = (s['turns'] as List?) ?? const [];
        for (var i = 0; i < turns.length; i++) {
          final t = turns[i] as Map<String, dynamic>;
          await txn.insert('turns', {
            'session_id': sid,
            'turn_index': i,
            'question': t['question'] as String? ?? '',
            'answer': t['answer'] as String? ?? '',
            'created_at': (t['createdAt'] as num?)?.toInt() ?? _now(),
          });
        }
      }
      for (final m in memories) {
        await txn.insert('memories', {
          'id': m.id,
          'content': m.content,
          'kind': m.kind.name,
          'importance': m.importance,
          'embedding': null,
          'created_at': m.createdAt.millisecondsSinceEpoch,
          'updated_at': m.updatedAt.millisecondsSinceEpoch,
          'last_used_at': m.lastUsedAt?.millisecondsSinceEpoch,
          'source': m.source,
          'active': m.active ? 1 : 0,
        });
      }
    });
  }

  /// 清空全部会话（清空数据入口用；记忆独立，不受影响）。
  Future<void> deleteAllSessions() async {
    await _db.transaction((txn) async {
      await txn.delete('turns');
      await txn.delete('sessions');
    });
  }

  /// 记一笔云端用量（token + 估算费用）。
  Future<void> insertUsage({
    required String model,
    required int promptTokens,
    required int completionTokens,
    required double cost,
    DateTime? at,
  }) async {
    await _db.insert('usage_log', {
      'ts': (at ?? DateTime.now()).millisecondsSinceEpoch,
      'model': model,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'cost': cost,
    });
  }

  /// 从 [since] 起的用量合计；不传就是全部。
  Future<UsageSummary> usageSince(DateTime? since) async {
    final rows = await _db.query(
      'usage_log',
      where: since == null ? null : 'ts >= ?',
      whereArgs: since == null ? null : [since.millisecondsSinceEpoch],
    );
    var prompt = 0, completion = 0, count = 0;
    var cost = 0.0;
    for (final r in rows) {
      prompt += (r['prompt_tokens'] as int?) ?? 0;
      completion += (r['completion_tokens'] as int?) ?? 0;
      cost += ((r['cost'] as num?) ?? 0).toDouble();
      count++;
    }
    return UsageSummary(
      promptTokens: prompt,
      completionTokens: completion,
      cost: cost,
      count: count,
    );
  }

  /// 清空用量账本（「删除全部聊天数据」时一起清）。
  Future<void> deleteAllUsage() async {
    await _db.delete('usage_log');
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> close() => _db.close();
}
