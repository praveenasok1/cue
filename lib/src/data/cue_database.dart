import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';

import 'models.dart';

class CueDatabase extends GeneratedDatabase {
  CueDatabase() : super(_openConnection());

  final _catchphrasesChanged = StreamController<void>.broadcast();
  final _transcriptChanged = StreamController<void>.broadcast();
  final _hitsChanged = StreamController<void>.broadcast();
  final _sessionsChanged = StreamController<void>.broadcast();

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
CREATE TABLE catchphrases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phrase TEXT NOT NULL UNIQUE,
  polarity TEXT NOT NULL CHECK (polarity IN ('+', '-')),
  color_value INTEGER NOT NULL,
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
          await customStatement(
            'CREATE INDEX catchphrase_hits_spoken_at '
            'ON catchphrase_hits(spoken_at);',
          );
        },
      );

  Stream<List<Catchphrase>> watchCatchphrases() {
    return _watch(
      _catchphrasesChanged.stream,
      getCatchphrases,
    );
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
    String? notes,
  }) async {
    _validateCatchphrase(phrase);
    final normalized = phrase.trim().toLowerCase();
    final now = DateTime.now();
    await customStatement(
      '''
INSERT INTO catchphrases (phrase, polarity, color_value, notes, created_at)
VALUES (?, ?, ?, ?, ?);
''',
      [
        Variable.withString(normalized),
        Variable.withString(polarity.symbol),
        Variable.withInt(color.toARGB32()),
        notes == null || notes.trim().isEmpty
            ? const Variable(null)
            : Variable.withString(notes.trim()),
        Variable.withInt(now.millisecondsSinceEpoch),
      ],
    );
    final id = await _lastInsertId();
    _catchphrasesChanged.add(null);
    return Catchphrase(
      id: id,
      phrase: normalized,
      polarity: polarity,
      color: color,
      notes: notes?.trim(),
      createdAt: now,
    );
  }

  Future<void> deleteCatchphrase(int id) async {
    await customStatement(
      'DELETE FROM catchphrases WHERE id = ?;',
      [Variable.withInt(id)],
    );
    _catchphrasesChanged.add(null);
    _hitsChanged.add(null);
  }

  Stream<DailyTranscript> watchTodayTranscript() {
    return watchDailyTranscript(DateTime.now());
  }

  Stream<DailyTranscript> watchDailyTranscript(DateTime day) {
    return _watch(
      _transcriptChanged.stream,
      () => getDailyTranscript(day),
    );
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
      [
        Variable.withString(_dayKey(day)),
        Variable.withString(text),
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
      ],
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
    return _watch(
      _hitsChanged.stream,
      () => getRecentHits(limit: limit),
    );
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

  Stream<PendingCatchphrasePrompt?> watchPendingPrompt() {
    return _watch(
      _hitsChanged.stream,
      getPendingPrompt,
    );
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
        Variable.withInt(catchphrase.id),
        Variable.withString(catchphrase.phrase),
        Variable.withInt(now.millisecondsSinceEpoch),
        latitude == null ? const Variable(null) : Variable.withReal(latitude),
        longitude == null ? const Variable(null) : Variable.withReal(longitude),
        Variable.withString(context),
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
      [Variable.withString(mood.name), Variable.withInt(hitId)],
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
      [
        Variable.withInt(now.millisecondsSinceEpoch),
        audioPath == null ? const Variable(null) : Variable.withString(audioPath),
        Variable.withString(source),
      ],
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
      [
        Variable.withInt(DateTime.now().millisecondsSinceEpoch),
        Variable.withInt(id),
      ],
    );
    _sessionsChanged.add(null);
  }

  Future<int> _lastInsertId() async {
    final row = await customSelect(
      'SELECT last_insert_rowid() AS id;',
    ).getSingle();
    return row.read<int>('id');
  }

  Stream<T> _watch<T>(
    Stream<void> changed,
    Future<T> Function() load,
  ) async* {
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
    if (wordCount < 2) {
      throw ArgumentError('Catchphrases must contain at least two words.');
    }
  }

  @override
  Future<void> close() async {
    await _catchphrasesChanged.close();
    await _transcriptChanged.close();
    await _hitsChanged.close();
    await _sessionsChanged.close();
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
