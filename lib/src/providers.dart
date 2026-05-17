import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/cue_database.dart';
import 'data/models.dart';
import 'services/audio_route_service.dart';
import 'services/catchphrase_audio_service.dart';
import 'services/daily_insight_service.dart';
import 'services/foreground_recording_service.dart';
import 'services/location_service.dart';
import 'services/microsoft_todo_service.dart';
import 'services/reminder_notification_service.dart';
import 'services/recording_service.dart';
import 'services/transcription_service.dart';

// ──────────────────────────────────────────────── singleton services ─────────

final databaseProvider = Provider<CueDatabase>((ref) {
  final db = CueDatabase();
  ref.onDispose(db.close);
  return db;
});

final audioRouteServiceProvider = Provider<AudioRouteService>(
  (_) => AudioRouteService(),
);

final audioRouteProvider = StreamProvider<AudioRouteState>((ref) {
  return ref.watch(audioRouteServiceProvider).routeChanges();
});

final recordingServiceProvider = Provider<RecordingService>((ref) {
  final s = RecordingService();
  ref.onDispose(s.dispose);
  return s;
});

final catchphraseAudioServiceProvider = Provider<CatchphraseAudioService>((
  ref,
) {
  final s = CatchphraseAudioService();
  ref.onDispose(s.dispose);
  return s;
});

final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  final s = TranscriptionService();
  ref.onDispose(s.dispose);
  return s;
});

final foregroundRecordingServiceProvider = Provider<ForegroundRecordingService>(
  (_) => ForegroundRecordingService(),
);

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);

final dailyInsightServiceProvider = Provider<DailyInsightService>(
  (_) => DailyInsightService(),
);

final reminderNotificationServiceProvider =
    Provider<ReminderNotificationService>((_) => ReminderNotificationService());

final microsoftToDoServiceProvider = Provider<MicrosoftToDoService>(
  (_) => MicrosoftToDoService(),
);

// ──────────────────────────────────────────────── theme ──────────────────────

final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'cue.themeMode';
  final _prefs = SharedPreferencesAsync();

  @override
  ThemeMode build() {
    unawaited(_load());
    return ThemeMode.light;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_key, mode.name);
  }

  Future<void> _load() async {
    final v = await _prefs.getString(_key);
    state = v == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light;
  }
}

// ──────────────────────────────────────────────── DB streams ─────────────────

final catchphrasesProvider = StreamProvider<List<Catchphrase>>((ref) {
  return ref.watch(databaseProvider).watchCatchphrases();
});

final todayTranscriptProvider = StreamProvider<DailyTranscript>((ref) {
  return ref.watch(databaseProvider).watchTodayTranscript();
});

final todayCatchphraseStatsProvider = StreamProvider<List<CatchphraseStat>>((
  ref,
) {
  return ref.watch(databaseProvider).watchTodayCatchphraseStats();
});

final todaySummaryProvider = StreamProvider<DailySummary?>((ref) {
  return ref.watch(databaseProvider).watchTodaySummary();
});

final openRemindersProvider = StreamProvider<List<CueReminder>>((ref) {
  return ref.watch(databaseProvider).watchOpenReminders();
});

// ──────────────────────────────────────────────── catchphrase CRUD ───────────

final catchphraseControllerProvider =
    NotifierProvider<CatchphraseController, void>(CatchphraseController.new);

class CatchphraseController extends Notifier<void> {
  @override
  void build() {}

  Future<void> add({
    required String phrase,
    required Color color,
    required String audioPath,
    CatchphraseTag tag = CatchphraseTag.countOnly,
  }) {
    return ref
        .read(databaseProvider)
        .addCatchphrase(
          phrase: phrase,
          color: color,
          audioPath: audioPath,
          tag: tag,
        );
  }

  Future<void> updateTag(int id, CatchphraseTag tag) {
    return ref.read(databaseProvider).updateCatchphraseTag(id, tag);
  }

  Future<void> delete(int id) {
    return ref.read(databaseProvider).deleteCatchphrase(id);
  }
}

// ──────────────────────────────────────────────── transcript ──────────────────

final transcriptControllerProvider =
    NotifierProvider<TranscriptController, void>(TranscriptController.new);

class TranscriptController extends Notifier<void> {
  @override
  void build() {}

  Future<void> saveToday(String text) async {
    await ref
        .read(databaseProvider)
        .replaceDailyTranscript(DateTime.now(), text);
    unawaited(
      ref
          .read(insightControllerProvider.notifier)
          .refreshToday()
          .catchError((_) {}),
    );
  }
}

// ──────────────────────────────────────────────── daily insight ───────────────

final insightControllerProvider = NotifierProvider<InsightController, void>(
  InsightController.new,
);

class InsightController extends Notifier<void> {
  @override
  void build() {}

  Future<void> refreshToday() async {
    try {
      final transcript = await ref
          .read(databaseProvider)
          .getDailyTranscript(DateTime.now());
      await refreshFromTranscript(transcript.text);
    } on Exception {
      // Summary is best-effort.
    }
  }

  Future<void> refreshFromTranscript(String text) async {
    try {
      final db = ref.read(databaseProvider);
      final service = ref.read(dailyInsightServiceProvider);
      final transcript = await db.getDailyTranscript(DateTime.now());
      final notificationSvc = ref.read(reminderNotificationServiceProvider);
      final msTodo = ref.read(microsoftToDoServiceProvider);

      for (final candidate in service.extractReminderCandidates(text)) {
        final reminder = await db.addReminderIfAbsent(
          text: candidate.text,
          sourceText: candidate.sourceText,
          dueAt: candidate.dueAt,
        );
        if (reminder != null) {
          try {
            await notificationSvc.showReminder(reminder);
          } on Exception {
            /* ignore */
          }
          // Push to Microsoft To-Do if configured.
          try {
            final todoId = await msTodo.addTask(
              title: reminder.text,
              dueAt: reminder.dueAt,
            );
            if (todoId != null) {
              await db.setReminderMicrosoftToDoId(reminder.id, todoId);
            }
          } on Exception {
            /* ignore */
          }
        }
      }

      final hits = await db.getHitsForDay(DateTime.now());
      final reminders = await db.getRemindersForDay(DateTime.now());
      await db.upsertDailySummary(
        service.buildSummary(
          transcript: transcript,
          hits: hits,
          reminders: reminders,
        ),
      );
    } on Exception {
      /* best-effort */
    }
  }

  Future<void> completeReminder(int id) async {
    await ref.read(databaseProvider).completeReminder(id);
    unawaited(refreshToday().catchError((_) {}));
  }
}

// ──────────────────────────────────────────────── recording ───────────────────

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingStatus>(
      RecordingController.new,
    );

class RecordingController extends Notifier<RecordingStatus> {
  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<double>? _speechLevelSubscription;
  StreamSubscription<TranscriptionChunk>? _transcriptionSubscription;
  StreamSubscription<String>? _transcriptionErrorSubscription;
  Timer? _levelDecayTimer;
  DateTime _lastAmplitudeUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isStarting = false;

  @override
  RecordingStatus build() {
    ref.listen<AsyncValue<AudioRouteState>>(audioRouteProvider, (_, next) {
      next.whenData((route) => unawaited(_handleEarphoneState(route)));
    }, fireImmediately: true);

    ref.onDispose(() {
      _amplitudeSubscription?.cancel();
      _speechLevelSubscription?.cancel();
      _transcriptionSubscription?.cancel();
      _transcriptionErrorSubscription?.cancel();
      _levelDecayTimer?.cancel();
    });

    return const RecordingStatus(isRecording: false, earphonesConnected: false);
  }

  Future<void> _handleEarphoneState(AudioRouteState route) async {
    state = state.copyWith(
      earphonesConnected: route.earphonesConnected,
      statusMessage: route.earphonesConnected
          ? 'Earphones: ${route.routeName}'
          : 'Waiting for earphones',
    );
    if (route.earphonesConnected && !state.isRecording && !_isStarting) {
      await _startRecording(route.routeName);
    } else if (!route.earphonesConnected &&
        state.isRecording &&
        !state.isManualSession) {
      await stopRecording(reason: 'Earphones removed');
    }
  }

  Future<void> startManualRecording() =>
      _startRecording('Manual session', manual: true);

  Future<void> _startRecording(String source, {bool manual = false}) async {
    if (_isStarting || state.isRecording) return;
    _isStarting = true;
    RecordingSession? session;
    try {
      await ref.read(foregroundRecordingServiceProvider).start();
      final recording = await ref.read(recordingServiceProvider).start();
      session = await ref
          .read(databaseProvider)
          .startSession(source: source, audioPath: recording.path);

      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = ref
          .read(recordingServiceProvider)
          .amplitudeStream()
          .listen(_setLiveAmplitude);

      _speechLevelSubscription?.cancel();
      _speechLevelSubscription = ref
          .read(transcriptionServiceProvider)
          .soundLevels
          .listen(_setLiveAmplitude);

      _transcriptionSubscription?.cancel();
      _transcriptionSubscription = ref
          .read(transcriptionServiceProvider)
          .chunks
          .listen((chunk) {
            if (chunk.isFinal) {
              state = state.copyWith(liveTranscript: '');
              unawaited(
                _persistChunk(chunk.text, session?.id ?? 0).catchError((
                  Object e,
                ) {
                  state = state.copyWith(statusMessage: e.toString());
                }),
              );
            } else {
              state = state.copyWith(liveTranscript: chunk.text);
              // Scan partial results for catchphrases without waiting.
              unawaited(
                _detectCatchphrases(
                  chunk.text,
                  session?.id ?? 0,
                ).catchError((_) {}),
              );
            }
          });

      _transcriptionErrorSubscription?.cancel();
      _transcriptionErrorSubscription = ref
          .read(transcriptionServiceProvider)
          .errors
          .listen(
            (error) => state = state.copyWith(statusMessage: 'STT: $error'),
          );

      await ref.read(transcriptionServiceProvider).start();

      state = state.copyWith(
        isRecording: true,
        session: session,
        isPaused: false,
        isManualSession: manual,
        catchphraseDetectionActive: true,
        catchphraseReportCount: 0,
        clearLastCatchphraseLabel: true,
        statusMessage: manual
            ? 'Recording manual session'
            : 'Recording earphone session',
      );
      _startLevelDecay();
    } catch (error) {
      await _cancelSubscriptions();
      await ref.read(transcriptionServiceProvider).stop().catchError((_) {});
      await ref.read(recordingServiceProvider).stop().catchError((_) => null);
      if (session != null) {
        await ref.read(databaseProvider).endSession(session.id);
      }
      await ref.read(foregroundRecordingServiceProvider).stop();
      state = state.copyWith(
        isRecording: false,
        isPaused: false,
        isManualSession: false,
        catchphraseDetectionActive: false,
        statusMessage: error.toString(),
      );
    } finally {
      _isStarting = false;
    }
  }

  Future<void> pauseRecording() async {
    if (!state.isRecording || state.isPaused) return;
    await ref.read(recordingServiceProvider).pause();
    await ref.read(transcriptionServiceProvider).pause();
    state = state.copyWith(
      isPaused: true,
      amplitude: 0,
      liveTranscript: '',
      catchphraseDetectionActive: false,
      statusMessage: 'Recording paused',
    );
  }

  Future<void> resumeRecording() async {
    if (!state.isRecording || !state.isPaused) return;
    await ref.read(recordingServiceProvider).resume();
    await ref.read(transcriptionServiceProvider).resume();
    state = state.copyWith(
      isPaused: false,
      catchphraseDetectionActive: true,
      statusMessage: state.isManualSession
          ? 'Recording manual session'
          : 'Recording earphone session',
    );
  }

  Future<void> stopRecording({String reason = 'Stopped'}) async {
    final activeSession = state.session;
    await _cancelSubscriptions();
    _levelDecayTimer?.cancel();
    _levelDecayTimer = null;

    await ref.read(transcriptionServiceProvider).stop();
    await ref.read(recordingServiceProvider).stop();
    await ref.read(foregroundRecordingServiceProvider).stop();
    if (activeSession != null) {
      await ref.read(databaseProvider).endSession(activeSession.id);
    }

    state = state.copyWith(
      isRecording: false,
      isPaused: false,
      isManualSession: false,
      catchphraseDetectionActive: false,
      clearSession: true,
      amplitude: 0,
      liveTranscript: '',
      clearLastCatchphraseLabel: true,
      statusMessage: reason,
    );

    // Trigger end-of-session summary.
    unawaited(
      ref
          .read(insightControllerProvider.notifier)
          .refreshToday()
          .catchError((_) {}),
    );
  }

  // ── Amplitude / waveform ───────────────────────────────────────────────────

  void _setLiveAmplitude(double raw) {
    if (!state.isRecording || state.isPaused) return;
    final incoming = raw.clamp(0.0, 1.0);
    final current = state.amplitude;
    // Instant attack, slow release.
    final next = incoming >= current
        ? incoming
        : (current * 0.82 + incoming * 0.18).clamp(0, 1).toDouble();
    if ((next - current).abs() > 0.004) {
      _lastAmplitudeUpdate = DateTime.now();
      state = state.copyWith(amplitude: next);
    }
  }

  void _startLevelDecay() {
    _levelDecayTimer?.cancel();
    _levelDecayTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!state.isRecording || state.isPaused || state.amplitude <= 0.01) {
        return;
      }
      final stale =
          DateTime.now().difference(_lastAmplitudeUpdate).inMilliseconds > 180;
      if (stale) {
        state = state.copyWith(amplitude: (state.amplitude * 0.90).clamp(0, 1));
      }
    });
  }

  // ── Transcript persistence ────────────────────────────────────────────────

  Future<void> _persistChunk(String text, int sessionId) async {
    final db = ref.read(databaseProvider);
    await db.appendTranscript(DateTime.now(), text);
    await _detectCatchphrases(text, sessionId);
    try {
      await ref
          .read(insightControllerProvider.notifier)
          .refreshFromTranscript(text);
    } on Exception {
      /* best-effort */
    }
  }

  // ── Catchphrase detection – no cooldown, every occurrence logged ───────────

  Future<void> _detectCatchphrases(String text, int sessionId) async {
    if (!state.isRecording || state.isPaused) return;
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    final db = ref.read(databaseProvider);
    final catchphrases = await db.getCatchphrases();
    if (catchphrases.isEmpty) return;

    // GPS: fetch once for all hits in this detection pass.
    CueLocation? location;
    try {
      location = await ref.read(locationServiceProvider).currentLocation();
    } on Exception {
      // Location is non-critical – log without it.
    }

    if (!state.isRecording || state.isPaused) return;

    var reported = 0;
    String? lastLabel;

    for (final catchphrase in catchphrases) {
      final expr = RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(catchphrase.phrase)}'
        r'(?=$|[^A-Za-z0-9_])',
        caseSensitive: false,
      );
      if (!expr.hasMatch(normalized)) continue;

      await db.logCatchphraseHit(
        catchphrase: catchphrase,
        context: normalized,
        sessionId: sessionId,
        latitude: location?.latitude,
        longitude: location?.longitude,
      );
      reported++;
      lastLabel = catchphrase.phrase;

      // Tag-specific side-effects.
      if (catchphrase.tag == CatchphraseTag.reminder) {
        try {
          await ref
              .read(insightControllerProvider.notifier)
              .refreshFromTranscript(normalized);
        } on Exception {
          /* ignore */
        }
      }
    }

    if (reported > 0) {
      state = state.copyWith(
        catchphraseDetectionActive: true,
        catchphraseReportCount: state.catchphraseReportCount + reported,
        lastCatchphraseLabel: lastLabel,
        statusMessage: 'Catchphrase: $lastLabel',
      );
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _amplitudeSubscription?.cancel();
    await _speechLevelSubscription?.cancel();
    await _transcriptionSubscription?.cancel();
    await _transcriptionErrorSubscription?.cancel();
    _amplitudeSubscription = null;
    _speechLevelSubscription = null;
    _transcriptionSubscription = null;
    _transcriptionErrorSubscription = null;
  }
}
