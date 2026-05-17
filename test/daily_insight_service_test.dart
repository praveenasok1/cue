import 'package:cue/src/data/models.dart';
import 'package:cue/src/services/daily_insight_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts reminders from transcript phrases', () {
    final service = DailyInsightService();
    final reminders = service.extractReminderCandidates(
      'We talked about lunch. Remind me to call Sam tomorrow. I need to buy milk.',
    );
    expect(reminders, hasLength(2));
    expect(reminders.first.text, 'Call Sam tomorrow');
    expect(reminders.first.dueAt, isNotNull);
    expect(reminders.last.text, 'Buy milk');
  });

  test('builds daily summary from transcript metrics', () {
    final service = DailyInsightService();
    final summary = service.buildSummary(
      transcript: DailyTranscript(
        day: DateTime(2026, 5, 17),
        text: 'Remember the workout plan. Workout plan needs focus.',
        updatedAt: DateTime(2026, 5, 17, 12),
      ),
      hits: [
        CatchphraseHit(
          id: 1,
          catchphraseId: 1,
          phrase: 'workout plan',
          spokenAt: DateTime(2026, 5, 17, 12),
          context: 'workout plan',
          sessionId: 1,
        ),
      ],
      reminders: [
        CueReminder(
          id: 1,
          text: 'Buy milk',
          sourceText: 'I need to buy milk',
          createdAt: DateTime(2026, 5, 17, 12),
          completed: false,
        ),
      ],
    );

    expect(summary.wordCount, 8);
    expect(summary.catchphraseCount, 1);
    expect(summary.reminderCount, 1);
    expect(summary.summary, contains('Captured 8 words'));
  });

  test('CatchphraseStat groups hits correctly', () {
    final cp = Catchphrase(
      id: 1,
      phrase: 'drink water',
      color: const Color(0xFF0066FF),
      createdAt: DateTime(2026),
    );
    final hits = List.generate(
      3,
      (i) => CatchphraseHit(
        id: i,
        catchphraseId: 1,
        phrase: 'drink water',
        spokenAt: DateTime(2026, 5, 17, i),
        context: 'drink water now',
        sessionId: 1,
      ),
    );
    final stat = CatchphraseStat(catchphrase: cp, hits: hits);
    expect(stat.count, 3);
  });
}
