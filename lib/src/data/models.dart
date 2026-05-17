import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Catchphrase tag – controls how each phrase is treated at detection time.
// ---------------------------------------------------------------------------
enum CatchphraseTag {
  countOnly('Count only', Icons.tag_rounded, 'Log count; no other action.'),
  transcribeSeparately(
    'Transcribe separately',
    Icons.description_rounded,
    'Save speech around this phrase as a separate note.',
  ),
  reminder('Reminder', Icons.notifications_rounded, 'Add a reminder.'),
  delegate('Delegate', Icons.person_rounded, 'Flag for follow-up delegation.');

  const CatchphraseTag(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

// ---------------------------------------------------------------------------
// Catchphrase
// ---------------------------------------------------------------------------
class Catchphrase {
  const Catchphrase({
    required this.id,
    required this.phrase,
    required this.color,
    required this.createdAt,
    this.audioPath,
    this.tag = CatchphraseTag.countOnly,
  });

  final int id;
  final String phrase;
  final Color color;
  final String? audioPath;
  final CatchphraseTag tag;
  final DateTime createdAt;
}

// ---------------------------------------------------------------------------
// Catchphrase hit – every occurrence is a separate entry; no mood/ack
// ---------------------------------------------------------------------------
class CatchphraseHit {
  const CatchphraseHit({
    required this.id,
    required this.catchphraseId,
    required this.phrase,
    required this.spokenAt,
    required this.context,
    required this.sessionId,
    this.latitude,
    this.longitude,
  });

  final int id;
  final int catchphraseId;
  final String phrase;
  final DateTime spokenAt;
  final double? latitude;
  final double? longitude;
  final String context;
  final int sessionId;
}

// Aggregated view: catchphrase label + total hit count
class CatchphraseStat {
  const CatchphraseStat({required this.catchphrase, required this.hits});

  final Catchphrase catchphrase;
  final List<CatchphraseHit> hits;

  int get count => hits.length;
}

// ---------------------------------------------------------------------------
// Daily transcript
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Daily summary
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Reminders (auto-generated + optional Microsoft To-Do sync)
// ---------------------------------------------------------------------------
class CueReminder {
  const CueReminder({
    required this.id,
    required this.text,
    required this.sourceText,
    required this.createdAt,
    required this.completed,
    this.dueAt,
    this.completedAt,
    this.microsoftToDoId,
  });

  final int id;
  final String text;
  final String sourceText;
  final DateTime createdAt;
  final DateTime? dueAt;
  final bool completed;
  final DateTime? completedAt;
  final String? microsoftToDoId;
}

// ---------------------------------------------------------------------------
// Recording session
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// RecordingStatus (Riverpod state)
// ---------------------------------------------------------------------------
class RecordingStatus {
  const RecordingStatus({
    required this.isRecording,
    required this.earphonesConnected,
    this.earphoneMicActive = false,
    this.earphoneMicAvailable = false,
    this.inputName = 'Phone microphone',
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
  final bool earphoneMicActive;
  final bool earphoneMicAvailable;
  final String inputName;
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
    bool? earphoneMicActive,
    bool? earphoneMicAvailable,
    String? inputName,
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
      earphoneMicActive: earphoneMicActive ?? this.earphoneMicActive,
      earphoneMicAvailable: earphoneMicAvailable ?? this.earphoneMicAvailable,
      inputName: inputName ?? this.inputName,
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
