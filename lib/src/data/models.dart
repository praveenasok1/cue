import 'package:flutter/material.dart';

enum HabitPolarity {
  desired('+'),
  undesired('-');

  const HabitPolarity(this.symbol);

  final String symbol;

  static HabitPolarity fromSymbol(String symbol) {
    return symbol == '-' ? HabitPolarity.undesired : HabitPolarity.desired;
  }
}

enum CueMood {
  energized('Energized', ':)'),
  calm('Calm', '-_-'),
  proud('Proud', '^_^'),
  neutral('Neutral', ':|'),
  stressed('Stressed', ':/'),
  frustrated('Frustrated', '>:(');

  const CueMood(this.label, this.emoji);

  final String label;
  final String emoji;
}

class Catchphrase {
  const Catchphrase({
    required this.id,
    required this.phrase,
    required this.polarity,
    required this.color,
    required this.createdAt,
    this.audioPath,
    this.notes,
  });

  final int id;
  final String phrase;
  final HabitPolarity polarity;
  final Color color;
  final String? audioPath;
  final String? notes;
  final DateTime createdAt;

  bool get isDesired => polarity == HabitPolarity.desired;
}

class DailyTranscript {
  const DailyTranscript({
    required this.day,
    required this.text,
    required this.updatedAt,
  });

  final DateTime day;
  final String text;
  final DateTime updatedAt;
}

class DailySummary {
  const DailySummary({
    required this.day,
    required this.summary,
    required this.wordCount,
    required this.catchphraseCount,
    required this.reminderCount,
    required this.updatedAt,
    this.keywords = const [],
  });

  final DateTime day;
  final String summary;
  final int wordCount;
  final int catchphraseCount;
  final int reminderCount;
  final List<String> keywords;
  final DateTime updatedAt;
}

class CueReminder {
  const CueReminder({
    required this.id,
    required this.text,
    required this.sourceText,
    required this.createdAt,
    required this.completed,
    this.dueAt,
    this.completedAt,
  });

  final int id;
  final String text;
  final String sourceText;
  final DateTime createdAt;
  final DateTime? dueAt;
  final bool completed;
  final DateTime? completedAt;
}

class RecordingSession {
  const RecordingSession({
    required this.id,
    required this.startedAt,
    required this.source,
    this.endedAt,
    this.audioPath,
  });

  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? audioPath;
  final String source;

  bool get isActive => endedAt == null;
}

class CatchphraseHit {
  const CatchphraseHit({
    required this.id,
    required this.catchphraseId,
    required this.phrase,
    required this.spokenAt,
    required this.context,
    required this.acknowledged,
    this.latitude,
    this.longitude,
    this.mood,
  });

  final int id;
  final int catchphraseId;
  final String phrase;
  final DateTime spokenAt;
  final double? latitude;
  final double? longitude;
  final CueMood? mood;
  final String context;
  final bool acknowledged;
}

class PendingCatchphrasePrompt {
  const PendingCatchphrasePrompt({
    required this.hit,
    required this.catchphrase,
  });

  final CatchphraseHit hit;
  final Catchphrase catchphrase;
}

class RecordingStatus {
  const RecordingStatus({
    required this.isRecording,
    required this.earphonesConnected,
    this.isPaused = false,
    this.isManualSession = false,
    this.session,
    this.amplitude = 0,
    this.liveTranscript = '',
    this.catchphraseDetectionActive = false,
    this.catchphraseReportCount = 0,
    this.lastCatchphraseLabel,
    this.statusMessage = 'Waiting for earphones',
  });

  final bool isRecording;
  final bool earphonesConnected;
  final bool isPaused;
  final bool isManualSession;
  final RecordingSession? session;
  final double amplitude;
  final String liveTranscript;
  final bool catchphraseDetectionActive;
  final int catchphraseReportCount;
  final String? lastCatchphraseLabel;
  final String statusMessage;

  RecordingStatus copyWith({
    bool? isRecording,
    bool? earphonesConnected,
    bool? isPaused,
    bool? isManualSession,
    RecordingSession? session,
    bool clearSession = false,
    double? amplitude,
    String? liveTranscript,
    bool? catchphraseDetectionActive,
    int? catchphraseReportCount,
    String? lastCatchphraseLabel,
    bool clearLastCatchphraseLabel = false,
    String? statusMessage,
  }) {
    return RecordingStatus(
      isRecording: isRecording ?? this.isRecording,
      earphonesConnected: earphonesConnected ?? this.earphonesConnected,
      isPaused: isPaused ?? this.isPaused,
      isManualSession: isManualSession ?? this.isManualSession,
      session: clearSession ? null : session ?? this.session,
      amplitude: amplitude ?? this.amplitude,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      catchphraseDetectionActive:
          catchphraseDetectionActive ?? this.catchphraseDetectionActive,
      catchphraseReportCount:
          catchphraseReportCount ?? this.catchphraseReportCount,
      lastCatchphraseLabel: clearLastCatchphraseLabel
          ? null
          : lastCatchphraseLabel ?? this.lastCatchphraseLabel,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
