import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart' show Color;

import 'models.dart';

class CueDatabase extends GeneratedDatabase {
  CueDatabase() : super(_openConnection());

  final _catchphrasesChanged = StreamController<void>.broadcast();
  final _transcriptChanged = StreamController<void>.broadcast();
  final _hitsChanged = StreamController<void>.broadcast();
  final _sessionsChanged = StreamController<void>.broadcast();
  final _summaryChanged = StreamController<void>.broadcast();
  final _remindersChanged = StreamController<void>.broadcast();

  @override
  int get schemaVersion => 4;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await _createCatchphrases();
      await _createDailyTranscripts();
      await _createRecordingSessions();
      await _createCatchphraseHits();
      await _createDailySummaries();
      await _createReminders();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _addColumnIfMissing(
          table: 'catchphrases',
          column: 'audio_path',
          sql: 'ALTER TABLE catchphrases ADD COLUMN audio_path TEXT;',
        );
      }
      if (from < 3) {
        await _createDailySummaries();
        await _createReminders();
      }
      if (from < 4) {
        // Add tag column to catchphrases.
        await _addColumnIfMissing(
          table: 'catchphrases',
          column: 'tag',
          sql:
              "ALTER TABLE catchphrases ADD COLUMN tag TEXT NOT NULL DEFAULT 'countOnly';",
        );
        // Add session_id to catchphrase_hits (nullable for old rows).
        await _addColumnIfMissing(
          table: 'catchphrase_hits',
          column: 'session_id',
          sql:
              'ALTER TABLE catchphrase_hits ADD COLUMN session_id INTEGER NOT NULL DEFAULT 0;',
        );
        // Add microsoft_todo_id to reminders.
        await _addColumnIfMissing(
          table: 'reminders',
          column: 'microsoft_todo_id',
          sql: 'ALTER TABLE reminders ADD COLUMN microsoft_todo_id TEXT;',
        );
        // Drop mood / acknowledged from hits – SQLite can't DROP COLUMN until
        // 3.35 which is not guaranteed on older iOS, so we just leave columns
        // in place but stop reading/writing them.
        await _createDailySummaries();
        await _createReminders();
      }
    },
  );

  // ──────────────────────────────────────────────────────── table DDL ──────

  Future<void> _createCatchphrases() => customStatement('''
CREATE TABLE IF NOT EXISTS catchphrases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phrase TEXT NOT NULL UNIQUE,
  color_value INTEGER NOT NULL,
  audio_path TEXT,
  tag TEXT NOT NULL DEFAULT 'countOnly',
  created_at INTEGER NOT NULL
);
''');

  Future<void> _createDailyTranscripts() => customStatement('''
CREATE TABLE IF NOT EXISTS daily_transcripts (
  day TEXT PRIMARY KEY,
  text TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL
);
''');

  Future<void> _createRecordingSessions() => customStatement('''
CREATE TABLE IF NOT EXISTS recording_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  audio_path TEXT,
  source TEXT NOT NULL
);
''');

  Future<void> _createCatchphraseHits() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS catchphrase_hits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  catchphrase_id INTEGER NOT NULL REFERENCES catchphrases(id)
    ON DELETE CASCADE,
  phrase TEXT NOT NULL,
  spoken_at INTEGER NOT NULL,
  latitude REAL,
  longitude REAL,
  context TEXT NOT NULL,
  session_id INTEGER NOT NULL DEFAULT 0
);
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS catchphrase_hits_spoken_at '
      'ON catchphrase_hits(spoken_at);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS catchphrase_hits_phrase '
      'ON catchphrase_hits(catchphrase_id);',
    );
  }

  Future<void> _createDailySummaries() => customStatement('''
CREATE TABLE IF NOT EXISTS daily_summaries (
  day TEXT PRIMARY KEY,
  summary TEXT NOT NULL,
  word_count INTEGER NOT NULL,
  catchphrase_count INTEGER NOT NULL,
  reminder_count INTEGER NOT NULL,
  keywords TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

  Future<void> _createReminders() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_key TEXT NOT NULL UNIQUE,
  text TEXT NOT NULL,
  source_text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  due_at INTEGER,
  completed INTEGER NOT NULL DEFAULT 0,
  completed_at INTEGER,
  microsoft_todo_id TEXT
);
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS reminders_completed_due '
      'ON reminders(completed, due_at);',
    );
  }

  // ──────────────────────────────────────────────── catchphrases ────────────

  Stream<List<Catchphrase>> watchCatchphrases() =>
      _watch(_catchphrasesChanged.stream, getCatchphrases);

  Future<List<Catchphrase>> getCatchphrases() async {
    final rows = await customSelect(
      'SELECT * FROM catchphrases ORDER BY created_at DESC;',
    ).get();
    return rows.map(_catchphraseFromRow).toList(growable: false);
  }

  Future<Catchphrase> addCatchphrase({
    required String phrase,
    required Color color,
    required String audioPath,
    CatchphraseTag tag = CatchphraseTag.countOnly,
  }) async {
    if (phrase.trim().isEmpty) {
      throw ArgumentError('Add a text label for this audio catchphrase.');
    }
    final normalized = phrase.trim().toLowerCase();
    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO catchphrases (phrase, color_value, audio_path, tag, created_at)
VALUES (?, ?, ?, ?, ?);
''',
      [
        normalized,
        color.toARGB32(),
        audioPath,
        tag.name,
        now.millisecondsSinceEpoch,
      ],
    );
    final id = await _lastInsertId();
    _catchphrasesChanged.add(null);
    return Catchphrase(
      id: id,
      phrase: normalized,
      color: color,
      audioPath: audioPath,
      tag: tag,
      createdAt: now,
    );
  }

  Future<void> updateCatchphraseTag(int id, CatchphraseTag tag) async {
    await customStatement('UPDATE catchphrases SET tag = ? WHERE id = ?;', [
      tag.name,
      id,
    ]);
    _catchphrasesChanged.add(null);
  }

  Future<void> deleteCatchphrase(int id) async {
    await customStatement('DELETE FROM catchphrases WHERE id = ?;', [id]);
    _catchphrasesChanged.add(null);
    _hitsChanged.add(null);
  }

  // ──────────────────────────────────────────────── transcripts ─────────────

  Stream<DailyTranscript> watchTodayTranscript() =>
      watchDailyTranscript(DateTime.now());

  Stream<DailyTranscript> watchDailyTranscript(DateTime day) =>
      _watch(_transcriptChanged.stream, () => getDailyTranscript(day));

  Future<DailyTranscript> getDailyTranscript(DateTime day) async {
    final key = _dayKey(day);
    final rows = await customSelect(
      'SELECT * FROM daily_transcripts WHERE day = ? LIMIT 1;',
      variables: [Variable.withString(key)],
    ).get();
    if (rows.isEmpty) {
      return DailyTranscript(day: _dateOnly(day), text: '', updatedAt: day);
    }
    return _transcriptFromRow(rows.single);
  }

  Future<void> replaceDailyTranscript(DateTime day, String text) async {
    await customStatement(
      '''
INSERT INTO daily_transcripts (day, text, updated_at)
VALUES (?, ?, ?)
ON CONFLICT(day) DO UPDATE SET
  text = excluded.text,
  updated_at = excluded.updated_at;
''',
      [_dayKey(day), text, DateTime.now().millisecondsSinceEpoch],
    );
    _transcriptChanged.add(null);
  }

  Future<void> appendTranscript(DateTime day, String text) async {
    final addition = text.trim();
    if (addition.isEmpty) return;
    final existing = await getDailyTranscript(day);
    final timestamped = '[${_dateTimeLabel(DateTime.now())}] $addition';
    final separator = existing.text.trim().isEmpty ? '' : '\n\n';
    await replaceDailyTranscript(day, '${existing.text}$separator$timestamped');
  }

  // ──────────────────────────────────────────────── catchphrase hits ─────────

  /// Returns all hits grouped by catchphrase for today.
  Stream<List<CatchphraseStat>> watchTodayCatchphraseStats() {
    return _watch(_hitsChanged.stream, getTodayCatchphraseStats);
  }

  Future<List<CatchphraseStat>> getTodayCatchphraseStats() async {
    final catchphrases = await getCatchphrases();
    if (catchphrases.isEmpty) return [];
    final hits = await getHitsForDay(DateTime.now());
    final map = <int, List<CatchphraseHit>>{};
    for (final hit in hits) {
      map.putIfAbsent(hit.catchphraseId, () => []).add(hit);
    }
    return catchphrases
        .where((c) => map.containsKey(c.id))
        .map((c) => CatchphraseStat(catchphrase: c, hits: map[c.id]!))
        .toList(growable: false);
  }

  Future<List<CatchphraseHit>> getHitsForCatchphrase(int catchphraseId) async {
    final rows = await customSelect(
      'SELECT * FROM catchphrase_hits WHERE catchphrase_id = ? ORDER BY spoken_at DESC;',
      variables: [Variable.withInt(catchphraseId)],
    ).get();
    return rows.map(_hitFromRow).toList(growable: false);
  }

  Future<List<CatchphraseHit>> getHitsForDay(DateTime day) async {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    final rows = await customSelect(
      '''
SELECT * FROM catchphrase_hits
WHERE spoken_at >= ? AND spoken_at < ?
ORDER BY spoken_at DESC;
''',
      variables: [
        Variable.withInt(start.millisecondsSinceEpoch),
        Variable.withInt(end.millisecondsSinceEpoch),
      ],
    ).get();
    return rows.map(_hitFromRow).toList(growable: false);
  }

  Future<CatchphraseHit> logCatchphraseHit({
    required Catchphrase catchphrase,
    required String context,
    required int sessionId,
    double? latitude,
    double? longitude,
  }) async {
    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO catchphrase_hits (
  catchphrase_id, phrase, spoken_at, latitude, longitude, context, session_id
) VALUES (?, ?, ?, ?, ?, ?, ?);
''',
      [
        catchphrase.id,
        catchphrase.phrase,
        now.millisecondsSinceEpoch,
        latitude,
        longitude,
        context,
        sessionId,
      ],
    );
    final id = await _lastInsertId();
    _hitsChanged.add(null);
    return CatchphraseHit(
      id: id,
      catchphraseId: catchphrase.id,
      phrase: catchphrase.phrase,
      spokenAt: now,
      latitude: latitude,
      longitude: longitude,
      context: context,
      sessionId: sessionId,
    );
  }

  // ──────────────────────────────────────────────── sessions ────────────────

  Future<RecordingSession> startSession({
    required String source,
    String? audioPath,
  }) async {
    final now = DateTime.now();
    await customStatement(
      'INSERT INTO recording_sessions (started_at, audio_path, source) VALUES (?, ?, ?);',
      [now.millisecondsSinceEpoch, audioPath, source],
    );
    final id = await _lastInsertId();
    _sessionsChanged.add(null);
    return RecordingSession(
      id: id,
      startedAt: now,
      audioPath: audioPath,
      source: source,
    );
  }

  Future<void> endSession(int id) async {
    await customStatement(
      'UPDATE recording_sessions SET ended_at = ? WHERE id = ? AND ended_at IS NULL;',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
    _sessionsChanged.add(null);
  }

  Stream<List<RecordingSession>> watchRecentRecordingSessions({
    int limit = 20,
  }) {
    return _watch(
      _sessionsChanged.stream,
      () => getRecentRecordingSessions(limit: limit),
    );
  }

  Future<List<RecordingSession>> getRecentRecordingSessions({
    int limit = 20,
  }) async {
    final rows = await customSelect(
      '''
SELECT * FROM recording_sessions
WHERE audio_path IS NOT NULL
ORDER BY started_at DESC
LIMIT ?;
''',
      variables: [Variable.withInt(limit)],
    ).get();
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  // ──────────────────────────────────────────────── daily summaries ─────────

  Stream<DailySummary?> watchTodaySummary() =>
      watchDailySummary(DateTime.now());

  Stream<DailySummary?> watchDailySummary(DateTime day) =>
      _watch(_summaryChanged.stream, () => getDailySummary(day));

  Future<DailySummary?> getDailySummary(DateTime day) async {
    final rows = await customSelect(
      'SELECT * FROM daily_summaries WHERE day = ? LIMIT 1;',
      variables: [Variable.withString(_dayKey(day))],
    ).get();
    if (rows.isEmpty) return null;
    return _summaryFromRow(rows.single);
  }

  Future<void> upsertDailySummary(DailySummary summary) async {
    await customStatement(
      '''
INSERT INTO daily_summaries (
  day, summary, word_count, catchphrase_count, reminder_count, keywords, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(day) DO UPDATE SET
  summary = excluded.summary,
  word_count = excluded.word_count,
  catchphrase_count = excluded.catchphrase_count,
  reminder_count = excluded.reminder_count,
  keywords = excluded.keywords,
  updated_at = excluded.updated_at;
''',
      [
        _dayKey(summary.day),
        summary.summary,
        summary.wordCount,
        summary.catchphraseCount,
        summary.reminderCount,
        summary.keywords.join(','),
        summary.updatedAt.millisecondsSinceEpoch,
      ],
    );
    _summaryChanged.add(null);
  }

  // ──────────────────────────────────────────────── reminders ──────────────

  Stream<List<CueReminder>> watchOpenReminders() =>
      _watch(_remindersChanged.stream, getOpenReminders);

  Future<List<CueReminder>> getOpenReminders() async {
    final rows = await customSelect('''
SELECT * FROM reminders
WHERE completed = 0
ORDER BY due_at IS NULL, due_at ASC, created_at DESC;
''').get();
    return rows.map(_reminderFromRow).toList(growable: false);
  }

  Future<List<CueReminder>> getRemindersForDay(DateTime day) async {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    final rows = await customSelect(
      'SELECT * FROM reminders WHERE created_at >= ? AND created_at < ? ORDER BY created_at DESC;',
      variables: [
        Variable.withInt(start.millisecondsSinceEpoch),
        Variable.withInt(end.millisecondsSinceEpoch),
      ],
    ).get();
    return rows.map(_reminderFromRow).toList(growable: false);
  }

  Future<CueReminder?> addReminderIfAbsent({
    required String text,
    required String sourceText,
    DateTime? dueAt,
  }) async {
    final key = _reminderKey(text);
    if (key.isEmpty) return null;
    final existing = await customSelect(
      'SELECT * FROM reminders WHERE source_key = ? LIMIT 1;',
      variables: [Variable.withString(key)],
    ).get();
    if (existing.isNotEmpty) return null;
    final now = DateTime.now();
    await customStatement(
      'INSERT INTO reminders (source_key, text, source_text, created_at, due_at) VALUES (?, ?, ?, ?, ?);',
      [
        key,
        text,
        sourceText,
        now.millisecondsSinceEpoch,
        dueAt?.millisecondsSinceEpoch,
      ],
    );
    final id = await _lastInsertId();
    _remindersChanged.add(null);
    return CueReminder(
      id: id,
      text: text,
      sourceText: sourceText,
      createdAt: now,
      dueAt: dueAt,
      completed: false,
    );
  }

  Future<void> completeReminder(int id) async {
    await customStatement(
      'UPDATE reminders SET completed = 1, completed_at = ? WHERE id = ?;',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
    _remindersChanged.add(null);
  }

  Future<void> setReminderMicrosoftToDoId(int id, String todoId) async {
    await customStatement(
      'UPDATE reminders SET microsoft_todo_id = ? WHERE id = ?;',
      [todoId, id],
    );
    _remindersChanged.add(null);
  }

  // ──────────────────────────────────────────────── helpers ─────────────────

  Future<int> _lastInsertId() async {
    final row = await customSelect(
      'SELECT last_insert_rowid() AS id;',
    ).getSingle();
    return row.read<int>('id');
  }

  Future<void> _addColumnIfMissing({
    required String table,
    required String column,
    required String sql,
  }) async {
    if (await _hasColumn(table, column)) return;
    await customStatement(sql);
  }

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table);').get();
    for (final row in rows) {
      if (row.read<String>('name') == column) {
        return true;
      }
    }
    return false;
  }

  Stream<T> _watch<T>(Stream<void> changed, Future<T> Function() load) async* {
    yield await load();
    await for (final _ in changed) {
      yield await load();
    }
  }

  Catchphrase _catchphraseFromRow(QueryRow row) {
    final tagName = row.readNullable<String>('tag') ?? 'countOnly';
    final tag = CatchphraseTag.values.firstWhere(
      (t) => t.name == tagName,
      orElse: () => CatchphraseTag.countOnly,
    );
    return Catchphrase(
      id: row.read<int>('id'),
      phrase: row.read<String>('phrase'),
      color: Color(row.read<int>('color_value')),
      audioPath: row.readNullable<String>('audio_path'),
      tag: tag,
      createdAt: _dateFromMillis(row.read<int>('created_at')),
    );
  }

  DailyTranscript _transcriptFromRow(QueryRow row) {
    return DailyTranscript(
      day: _dateFromKey(row.read<String>('day')),
      text: row.read<String>('text'),
      updatedAt: _dateFromMillis(row.read<int>('updated_at')),
    );
  }

  DailySummary _summaryFromRow(QueryRow row) {
    final keywords = row
        .read<String>('keywords')
        .split(',')
        .where((k) => k.trim().isNotEmpty)
        .toList(growable: false);
    return DailySummary(
      day: _dateFromKey(row.read<String>('day')),
      summary: row.read<String>('summary'),
      wordCount: row.read<int>('word_count'),
      catchphraseCount: row.read<int>('catchphrase_count'),
      reminderCount: row.read<int>('reminder_count'),
      keywords: keywords,
      updatedAt: _dateFromMillis(row.read<int>('updated_at')),
    );
  }

  CueReminder _reminderFromRow(QueryRow row) {
    return CueReminder(
      id: row.read<int>('id'),
      text: row.read<String>('text'),
      sourceText: row.read<String>('source_text'),
      createdAt: _dateFromMillis(row.read<int>('created_at')),
      dueAt: _nullableDateFromMillis(row.readNullable<int>('due_at')),
      completed: row.read<int>('completed') == 1,
      completedAt: _nullableDateFromMillis(
        row.readNullable<int>('completed_at'),
      ),
      microsoftToDoId: row.readNullable<String>('microsoft_todo_id'),
    );
  }

  CatchphraseHit _hitFromRow(QueryRow row) {
    return CatchphraseHit(
      id: row.read<int>('id'),
      catchphraseId: row.read<int>('catchphrase_id'),
      phrase: row.read<String>('phrase'),
      spokenAt: _dateFromMillis(row.read<int>('spoken_at')),
      latitude: row.readNullable<double>('latitude'),
      longitude: row.readNullable<double>('longitude'),
      context: row.read<String>('context'),
      sessionId: row.readNullable<int>('session_id') ?? 0,
    );
  }

  RecordingSession _sessionFromRow(QueryRow row) {
    return RecordingSession(
      id: row.read<int>('id'),
      startedAt: _dateFromMillis(row.read<int>('started_at')),
      endedAt: _nullableDateFromMillis(row.readNullable<int>('ended_at')),
      audioPath: row.readNullable<String>('audio_path'),
      source: row.read<String>('source'),
    );
  }

  @override
  Future<void> close() async {
    await _catchphrasesChanged.close();
    await _transcriptChanged.close();
    await _hitsChanged.close();
    await _sessionsChanged.close();
    await _summaryChanged.close();
    await _remindersChanged.close();
    return super.close();
  }
}

QueryExecutor _openConnection() => driftDatabase(name: 'cue.sqlite');

String _dayKey(DateTime day) {
  final d = _dateOnly(day);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _dateTimeLabel(DateTime value) {
  final hour12 = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} $hour12:$minute $period';
}

DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

DateTime _dateFromKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

DateTime _dateFromMillis(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis);

DateTime? _nullableDateFromMillis(int? millis) =>
    millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

String _reminderKey(String text) => text
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]+'), '')
    .replaceAll(RegExp(r'\s+'), ' ');
