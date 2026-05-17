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
  int get schemaVersion => 3;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement('''
CREATE TABLE catchphrases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phrase TEXT NOT NULL UNIQUE,
  polarity TEXT NOT NULL CHECK (polarity IN ('+', '-')),
  color_value INTEGER NOT NULL,
  audio_path TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL
);
''');
      await customStatement('''
CREATE TABLE daily_transcripts (
  day TEXT PRIMARY KEY,
  text TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL
);
''');
      await customStatement('''
CREATE TABLE recording_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  audio_path TEXT,
  source TEXT NOT NULL
);
''');
      await customStatement('''
CREATE TABLE catchphrase_hits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  catchphrase_id INTEGER NOT NULL REFERENCES catchphrases(id)
    ON DELETE CASCADE,
  phrase TEXT NOT NULL,
  spoken_at INTEGER NOT NULL,
  latitude REAL,
  longitude REAL,
  mood TEXT,
  context TEXT NOT NULL,
  acknowledged INTEGER NOT NULL DEFAULT 0
);
''');
      await _createDailySummariesTable();
      await _createRemindersTable();
      await customStatement(
        'CREATE INDEX catchphrase_hits_spoken_at '
        'ON catchphrase_hits(spoken_at);',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement(
          'ALTER TABLE catchphrases ADD COLUMN audio_path TEXT;',
        );
      }
      if (from < 3) {
        await _createDailySummariesTable();
        await _createRemindersTable();
      }
    },
  );

  Future<void> _createDailySummariesTable() {
    return customStatement('''
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
  }

  Future<void> _createRemindersTable() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_key TEXT NOT NULL UNIQUE,
  text TEXT NOT NULL,
  source_text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  due_at INTEGER,
  completed INTEGER NOT NULL DEFAULT 0,
  completed_at INTEGER
);
''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS reminders_completed_due '
      'ON reminders(completed, due_at);',
    );
  }

  Stream<List<Catchphrase>> watchCatchphrases() {
    return _watch(_catchphrasesChanged.stream, getCatchphrases);
  }

  Future<List<Catchphrase>> getCatchphrases() async {
    final rows = await customSelect(
      'SELECT * FROM catchphrases ORDER BY created_at DESC;',
    ).get();
    return rows.map(_catchphraseFromRow).toList(growable: false);
  }

  Future<Catchphrase> addCatchphrase({
    required String phrase,
    required HabitPolarity polarity,
    required Color color,
    required String audioPath,
    String? notes,
  }) async {
    _validateCatchphrase(phrase);
    final normalized = phrase.trim().toLowerCase();
    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO catchphrases (
  phrase,
  polarity,
  color_value,
  audio_path,
  notes,
  created_at
) VALUES (?, ?, ?, ?, ?, ?);
''',
      [
        normalized,
        polarity.symbol,
        color.toARGB32(),
        audioPath,
        notes == null || notes.trim().isEmpty ? null : notes.trim(),
        now.millisecondsSinceEpoch,
      ],
    );
    final id = await _lastInsertId();
    _catchphrasesChanged.add(null);
    return Catchphrase(
      id: id,
      phrase: normalized,
      polarity: polarity,
      color: color,
      audioPath: audioPath,
      notes: notes?.trim(),
      createdAt: now,
    );
  }

  Future<void> deleteCatchphrase(int id) async {
    await customStatement('DELETE FROM catchphrases WHERE id = ?;', [id]);
    _catchphrasesChanged.add(null);
    _hitsChanged.add(null);
  }

  Stream<DailyTranscript> watchTodayTranscript() {
    return watchDailyTranscript(DateTime.now());
  }

  Stream<DailyTranscript> watchDailyTranscript(DateTime day) {
    return _watch(_transcriptChanged.stream, () => getDailyTranscript(day));
  }

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
    final separator = existing.text.trim().isEmpty ? '' : '\n';
    await replaceDailyTranscript(day, '${existing.text}$separator$addition');
  }

  Stream<List<CatchphraseHit>> watchRecentHits({int limit = 25}) {
    return _watch(_hitsChanged.stream, () => getRecentHits(limit: limit));
  }

  Future<List<CatchphraseHit>> getRecentHits({int limit = 25}) async {
    final rows = await customSelect(
      '''
SELECT * FROM catchphrase_hits
ORDER BY spoken_at DESC
LIMIT ?;
''',
      variables: [Variable.withInt(limit)],
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

  Stream<DailySummary?> watchTodaySummary() {
    return watchDailySummary(DateTime.now());
  }

  Stream<DailySummary?> watchDailySummary(DateTime day) {
    return _watch(_summaryChanged.stream, () => getDailySummary(day));
  }

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
  day,
  summary,
  word_count,
  catchphrase_count,
  reminder_count,
  keywords,
  updated_at
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

  Stream<List<CueReminder>> watchOpenReminders() {
    return _watch(_remindersChanged.stream, getOpenReminders);
  }

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
      '''
SELECT * FROM reminders
WHERE created_at >= ? AND created_at < ?
ORDER BY created_at DESC;
''',
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
    final normalized = _reminderKey(text);
    if (normalized.isEmpty) return null;
    final existing = await customSelect(
      'SELECT * FROM reminders WHERE source_key = ? LIMIT 1;',
      variables: [Variable.withString(normalized)],
    ).get();
    if (existing.isNotEmpty) return null;

    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO reminders (
  source_key,
  text,
  source_text,
  created_at,
  due_at
) VALUES (?, ?, ?, ?, ?);
''',
      [
        normalized,
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
      '''
UPDATE reminders
SET completed = 1, completed_at = ?
WHERE id = ?;
''',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
    _remindersChanged.add(null);
  }

  Stream<PendingCatchphrasePrompt?> watchPendingPrompt() {
    return _watch(_hitsChanged.stream, getPendingPrompt);
  }

  Future<PendingCatchphrasePrompt?> getPendingPrompt() async {
    final rows = await customSelect('''
SELECT
  h.id AS hit_id,
  h.catchphrase_id,
  h.phrase AS hit_phrase,
  h.spoken_at,
  h.latitude,
  h.longitude,
  h.mood,
  h.context,
  h.acknowledged,
  c.id,
  c.phrase,
  c.polarity,
  c.color_value,
  c.audio_path,
  c.notes,
  c.created_at
FROM catchphrase_hits h
JOIN catchphrases c ON c.id = h.catchphrase_id
WHERE h.acknowledged = 0
ORDER BY h.spoken_at DESC
LIMIT 1;
''').get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return PendingCatchphrasePrompt(
      hit: CatchphraseHit(
        id: row.read<int>('hit_id'),
        catchphraseId: row.read<int>('catchphrase_id'),
        phrase: row.read<String>('hit_phrase'),
        spokenAt: _dateFromMillis(row.read<int>('spoken_at')),
        latitude: row.readNullable<double>('latitude'),
        longitude: row.readNullable<double>('longitude'),
        mood: _moodFromName(row.readNullable<String>('mood')),
        context: row.read<String>('context'),
        acknowledged: row.read<int>('acknowledged') == 1,
      ),
      catchphrase: _catchphraseFromRow(row),
    );
  }

  Future<CatchphraseHit> logCatchphraseHit({
    required Catchphrase catchphrase,
    required String context,
    double? latitude,
    double? longitude,
  }) async {
    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO catchphrase_hits (
  catchphrase_id,
  phrase,
  spoken_at,
  latitude,
  longitude,
  context
) VALUES (?, ?, ?, ?, ?, ?);
''',
      [
        catchphrase.id,
        catchphrase.phrase,
        now.millisecondsSinceEpoch,
        latitude,
        longitude,
        context,
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
      acknowledged: false,
    );
  }

  Future<void> setHitMood(int hitId, CueMood mood) async {
    await customStatement(
      '''
UPDATE catchphrase_hits
SET mood = ?, acknowledged = 1
WHERE id = ?;
''',
      [mood.name, hitId],
    );
    _hitsChanged.add(null);
  }

  Future<RecordingSession> startSession({
    required String source,
    String? audioPath,
  }) async {
    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO recording_sessions (started_at, audio_path, source)
VALUES (?, ?, ?);
''',
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
      '''
UPDATE recording_sessions
SET ended_at = ?
WHERE id = ? AND ended_at IS NULL;
''',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
    _sessionsChanged.add(null);
  }

  Future<int> _lastInsertId() async {
    final row = await customSelect(
      'SELECT last_insert_rowid() AS id;',
    ).getSingle();
    return row.read<int>('id');
  }

  Stream<T> _watch<T>(Stream<void> changed, Future<T> Function() load) async* {
    yield await load();
    await for (final _ in changed) {
      yield await load();
    }
  }

  Catchphrase _catchphraseFromRow(QueryRow row) {
    return Catchphrase(
      id: row.read<int>('id'),
      phrase: row.read<String>('phrase'),
      polarity: HabitPolarity.fromSymbol(row.read<String>('polarity')),
      color: Color(row.read<int>('color_value')),
      audioPath: row.readNullable<String>('audio_path'),
      notes: row.readNullable<String>('notes'),
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
        .where((keyword) => keyword.trim().isNotEmpty)
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
      mood: _moodFromName(row.readNullable<String>('mood')),
      context: row.read<String>('context'),
      acknowledged: row.read<int>('acknowledged') == 1,
    );
  }

  CueMood? _moodFromName(String? name) {
    if (name == null) return null;
    for (final mood in CueMood.values) {
      if (mood.name == name) return mood;
    }
    return null;
  }

  void _validateCatchphrase(String phrase) {
    final wordCount = phrase
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    if (wordCount < 1) {
      throw ArgumentError('Add a text label for this audio catchphrase.');
    }
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

QueryExecutor _openConnection() {
  return driftDatabase(name: 'cue.sqlite');
}

String _dayKey(DateTime day) {
  final date = _dateOnly(day);
  final month = date.month.toString().padLeft(2, '0');
  final dom = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$dom';
}

DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

DateTime _dateFromKey(String key) {
  final parts = key.split('-').map(int.parse).toList(growable: false);
  return DateTime(parts[0], parts[1], parts[2]);
}

DateTime _dateFromMillis(int millis) {
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

DateTime? _nullableDateFromMillis(int? millis) {
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

String _reminderKey(String text) {
  return text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}
