import '../data/models.dart';

class ReminderCandidate {
  const ReminderCandidate({
    required this.text,
    required this.sourceText,
    this.dueAt,
  });

  final String text;
  final String sourceText;
  final DateTime? dueAt;
}

class DailyInsightService {
  DailySummary buildSummary({
    required DailyTranscript transcript,
    required List<CatchphraseHit> hits,
    required List<CueReminder> reminders,
  }) {
    final words = _words(transcript.text);
    final keywords = _keywords(words);
    final summary = _summaryText(
      transcript.text,
      words.length,
      hits.length,
      reminders.where((reminder) => !reminder.completed).length,
      keywords,
    );

    return DailySummary(
      day: transcript.day,
      summary: summary,
      wordCount: words.length,
      catchphraseCount: hits.length,
      reminderCount: reminders.where((reminder) => !reminder.completed).length,
      keywords: keywords,
      updatedAt: DateTime.now(),
    );
  }

  List<ReminderCandidate> extractReminderCandidates(String text) {
    final candidates = <ReminderCandidate>[];
    final fragments = text
        .split(RegExp(r'[.!?\n]+'))
        .map((fragment) => fragment.trim())
        .where((fragment) => fragment.isNotEmpty);

    for (final fragment in fragments) {
      final reminderText = _extractReminderText(fragment);
      if (reminderText == null) continue;
      candidates.add(
        ReminderCandidate(
          text: _titleCase(reminderText),
          sourceText: fragment,
          dueAt: _inferDueAt(fragment),
        ),
      );
    }
    return candidates;
  }

  String _summaryText(
    String transcript,
    int wordCount,
    int catchphraseCount,
    int reminderCount,
    List<String> keywords,
  ) {
    if (transcript.trim().isEmpty) {
      return 'No transcript captured yet today. Start a session to build your daily summary.';
    }

    final firstThought = transcript
        .split(RegExp(r'[.!?\n]+'))
        .map((fragment) => fragment.trim())
        .firstWhere((fragment) => fragment.isNotEmpty, orElse: () => '');
    final focus = keywords.isEmpty
        ? 'no dominant themes yet'
        : keywords.join(', ');
    return 'Captured $wordCount words today. Main themes: $focus. '
        'Catchphrase reports: $catchphraseCount. Open reminders: $reminderCount. '
        '${firstThought.isEmpty ? '' : 'First notable note: "$firstThought".'}';
  }

  List<String> _words(String text) {
    return RegExp(r"[A-Za-z][A-Za-z']+")
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .toList(growable: false);
  }

  List<String> _keywords(List<String> words) {
    const stopWords = {
      'about',
      'after',
      'again',
      'also',
      'because',
      'before',
      'check',
      'could',
      'from',
      'have',
      'hello',
      'just',
      'like',
      'need',
      'please',
      'that',
      'this',
      'today',
      'want',
      'will',
      'with',
      'work',
      'working',
      'would',
      'you',
      'your',
    };
    final counts = <String, int>{};
    for (final word in words) {
      if (word.length < 4 || stopWords.contains(word)) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((entry) => entry.key).toList(growable: false);
  }

  String? _extractReminderText(String fragment) {
    final patterns = [
      RegExp(r'\bremind me to\s+(.+)$', caseSensitive: false),
      RegExp(r"\bdon'?t forget to\s+(.+)$", caseSensitive: false),
      RegExp(r'\bi need to\s+(.+)$', caseSensitive: false),
      RegExp(r'\bwe need to\s+(.+)$', caseSensitive: false),
      RegExp(r'\bi should\s+(.+)$', caseSensitive: false),
      RegExp(r'\bfollow up (?:on|with)\s+(.+)$', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fragment);
      if (match == null) continue;
      final value = match.group(1)?.trim();
      if (value == null || value.length < 3) continue;
      return value.replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }

  DateTime? _inferDueAt(String fragment) {
    final lower = fragment.toLowerCase();
    final now = DateTime.now();
    if (lower.contains('tomorrow')) {
      return DateTime(now.year, now.month, now.day + 1, 9);
    }
    if (lower.contains('tonight')) {
      return DateTime(now.year, now.month, now.day, 20);
    }
    if (lower.contains('today') || lower.contains('later')) {
      return now.add(const Duration(hours: 2));
    }
    return null;
  }

  String _titleCase(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }
}
