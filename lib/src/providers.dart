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
import 'services/reminder_notification_service.dart';
import 'services/recording_service.dart';
import 'services/transcription_service.dart';

final databaseProvider = Provider<CueDatabase>((ref) {
  final database = CueDatabase();
  ref.onDispose(database.close);
  return database;
});

final audioRouteServiceProvider = Provider<AudioRouteService>((ref) {
  return AudioRouteService();
});

final audioRouteProvider = StreamProvider<AudioRouteState>((ref) {
  return ref.watch(audioRouteServiceProvider).routeChanges();
});

final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = RecordingService();
  ref.onDispose(service.dispose);
  return service;
});

final catchphraseAudioServiceProvider = Provider<CatchphraseAudioService>((
  ref,
) {
  final service = CatchphraseAudioService();
  ref.onDispose(service.dispose);
  return service;
});

final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  final service = TranscriptionService();
  ref.onDispose(service.dispose);
  return service;
});

final foregroundRecordingServiceProvider = Provider<ForegroundRecordingService>(
  (ref) {
    return ForegroundRecordingService();
  },
);

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final dailyInsightServiceProvider = Provider<DailyInsightService>((ref) {
  return DailyInsightService();
});

final reminderNotificationServiceProvider =
    Provider<ReminderNotificationService>((ref) {
      return ReminderNotificationService();
    });

final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _themeModeKey = 'cue.themeMode';
  final _prefs = SharedPreferencesAsync();

  @override
  ThemeMode build() {
    unawaited(_load());
    return ThemeMode.light;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> _load() async {
    final value = await _prefs.getString(_themeModeKey);
    state = value == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light;
  }
}

final catchphrasesProvider = StreamProvider<List<Catchphrase>>((ref) {
  return ref.watch(databaseProvider).watchCatchphrases();
});

final todayTranscriptProvider = StreamProvider<DailyTranscript>((ref) {
  return ref.watch(databaseProvider).watchTodayTranscript();
});

final recentHitsProvider = StreamProvider<List<CatchphraseHit>>((ref) {
  return ref.watch(databaseProvider).watchRecentHits();
});

final todaySummaryProvider = StreamProvider<DailySummary?>((ref) {
  return ref.watch(databaseProvider).watchTodaySummary();
});

final openRemindersProvider = StreamProvider<List<CueReminder>>((ref) {
  return ref.watch(databaseProvider).watchOpenReminders();
});

final pendingCatchphrasePromptProvider =
    StreamProvider<PendingCatchphrasePrompt?>((ref) {
      return ref.watch(databaseProvider).watchPendingPrompt();
    });

final catchphraseControllerProvider =
    NotifierProvider<CatchphraseController, void>(CatchphraseController.new);

class CatchphraseController extends Notifier<void> {
  @override
  void build() {}

  Future<void> add({
    required String phrase,
    required Color color,
    required String audioPath,
  }) {
    return ref
        .read(databaseProvider)
        .addCatchphrase(
          phrase: phrase,
          polarity: HabitPolarity.desired,
          color: color,
          audioPath: audioPath,
        );
  }

  Future<void> delete(int id) {
    return ref.read(databaseProvider).deleteCatchphrase(id);
  }

  Future<void> chooseMood(int hitId, CueMood mood) {
    return ref.read(databaseProvider).setHitMood(hitId, mood);
  }
}

final transcriptControllerProvider =
    NotifierProvider<TranscriptController, void>(TranscriptController.new);

class TranscriptController extends Notifier<void> {
  @override
  void build() {}

  Future<void> saveToday(String text) async {
    await ref
        .read(databaseProvider)
        .replaceDailyTranscript(DateTime.now(), text);
    await ref
        .read(insightControllerProvider.notifier)
        .refreshFromTranscript(text);
  }
}

final insightControllerProvider = NotifierProvider<InsightController, void>(
  InsightController.new,
);

class InsightController extends Notifier<void> {
  @override
  void build() {}

  Future<void> refreshToday() async {
    final transcript = await ref
        .read(databaseProvider)
        .getDailyTranscript(DateTime.now());
    await refreshFromTranscript(transcript.text);
  }

  Future<void> refreshFromTranscript(String transcriptText) async {
    final database = ref.read(databaseProvider);
    final service = ref.read(dailyInsightServiceProvider);
    final transcript = await database.getDailyTranscript(DateTime.now());

    for (final candidate in service.extractReminderCandidates(transcriptText)) {
      final reminder = await database.addReminderIfAbsent(
        text: candidate.text,
        sourceText: candidate.sourceText,
        dueAt: candidate.dueAt,
      );
      if (reminder != null) {
        await ref
            .read(reminderNotificationServiceProvider)
            .showReminder(reminder);
      }
    }

    final hits = await database.getHitsForDay(DateTime.now());
    final reminders = await database.getRemindersForDay(DateTime.now());
    await database.upsertDailySummary(
      service.buildSummary(
        transcript: transcript,
        hits: hits,
        reminders: reminders,
      ),
    );
  }

  Future<void> completeReminder(int id) async {
    await ref.read(databaseProvider).completeReminder(id);
    await refreshToday();
  }
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingStatus>(
      RecordingController.new,
    );

class RecordingController extends Notifier<RecordingStatus> {
  static const _catchphraseCooldown = Duration(seconds: 45);

  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<double>? _speechLevelSubscription;
  StreamSubscription<TranscriptionChunk>? _transcriptionSubscription;
  StreamSubscription<String>? _transcriptionErrorSubscription;
  Timer? _levelDecayTimer;
  final Map<int, DateTime> _lastCatchphraseReports = {};
  bool _isStarting = false;

  @override
  RecordingStatus build() {
    ref.listen<AsyncValue<AudioRouteState>>(audioRouteProvider, (_, next) {
      next.whenData((route) {
        unawaited(_handleEarphoneState(route));
      });
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
          ? 'Earphones connected: ${route.routeName}'
          : 'Waiting for earphones',
    );

    if (route.earphonesConnected && !state.isRecording && !_isStarting) {
      await _startRecording(route.routeName);
    } else if (!route.earphonesConnected &&
        state.isRecording &&
        !state.isManualSession) {
      await stopRecording(reason: 'Earphones disconnected');
    }
  }

  Future<void> startManualRecording() {
    return _startRecording('Manual session', manual: true);
  }

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
          .listen((amplitude) {
            _setLiveAmplitude(amplitude);
          });

      _speechLevelSubscription?.cancel();
      _speechLevelSubscription = ref
          .read(transcriptionServiceProvider)
          .soundLevels
          .listen((amplitude) {
            // Speech recognition sound levels are a reliable live fallback on
            // iOS while the recorder is writing the session file.
            _setLiveAmplitude(amplitude);
          });

      _transcriptionSubscription?.cancel();
      _transcriptionSubscription = ref
          .read(transcriptionServiceProvider)
          .chunks
          .listen((chunk) {
            if (chunk.isFinal) {
              unawaited(_persistTranscriptChunk(chunk.text));
              state = state.copyWith(liveTranscript: '');
            } else {
              state = state.copyWith(liveTranscript: chunk.text);
              unawaited(_detectCatchphrases(chunk.text));
            }
          });
      _transcriptionErrorSubscription?.cancel();
      _transcriptionErrorSubscription = ref
          .read(transcriptionServiceProvider)
          .errors
          .listen((error) {
            state = state.copyWith(statusMessage: 'Transcription: $error');
          });
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
      await _amplitudeSubscription?.cancel();
      await _speechLevelSubscription?.cancel();
      await _transcriptionSubscription?.cancel();
      await _transcriptionErrorSubscription?.cancel();
      _amplitudeSubscription = null;
      _speechLevelSubscription = null;
      _transcriptionSubscription = null;
      _transcriptionErrorSubscription = null;
      _levelDecayTimer?.cancel();
      _levelDecayTimer = null;
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
    await _amplitudeSubscription?.cancel();
    await _speechLevelSubscription?.cancel();
    await _transcriptionSubscription?.cancel();
    await _transcriptionErrorSubscription?.cancel();
    _amplitudeSubscription = null;
    _speechLevelSubscription = null;
    _transcriptionSubscription = null;
    _transcriptionErrorSubscription = null;
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
    _lastCatchphraseReports.clear();
  }

  void _setLiveAmplitude(double amplitude) {
    if (!state.isRecording || state.isPaused) return;
    final boosted = (amplitude * 1.35).clamp(0, 1).toDouble();
    final next = boosted > state.amplitude
        ? boosted
        : (state.amplitude * 0.72 + boosted * 0.28).clamp(0, 1).toDouble();
    state = state.copyWith(amplitude: next);
  }

  void _startLevelDecay() {
    _levelDecayTimer?.cancel();
    _levelDecayTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!state.isRecording || state.isPaused || state.amplitude <= 0.02) {
        return;
      }
      state = state.copyWith(amplitude: state.amplitude * 0.86);
    });
  }

  Future<void> _persistTranscriptChunk(String text) async {
    final database = ref.read(databaseProvider);
    await database.appendTranscript(DateTime.now(), text);
    await ref
        .read(insightControllerProvider.notifier)
        .refreshFromTranscript(text);
    await _detectCatchphrases(text);
  }

  Future<void> _detectCatchphrases(String text) async {
    if (!state.isRecording || state.isPaused) return;
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;

    final database = ref.read(databaseProvider);
    final catchphrases = await database.getCatchphrases();
    if (catchphrases.isEmpty) return;

    final now = DateTime.now();
    final matches = <Catchphrase>[];
    for (final catchphrase in catchphrases) {
      final expression = RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(catchphrase.phrase)}'
        r'(?=$|[^A-Za-z0-9_])',
        caseSensitive: false,
      );
      final lastReport = _lastCatchphraseReports[catchphrase.id];
      final recentlyReported =
          lastReport != null &&
          now.difference(lastReport) < _catchphraseCooldown;
      if (!recentlyReported && expression.hasMatch(normalizedText)) {
        matches.add(catchphrase);
      }
    }
    if (matches.isEmpty) return;

    final location = await ref.read(locationServiceProvider).currentLocation();
    if (!state.isRecording || state.isPaused) return;
    for (final catchphrase in matches) {
      await database.logCatchphraseHit(
        catchphrase: catchphrase,
        context: normalizedText,
        latitude: location?.latitude,
        longitude: location?.longitude,
      );
      _lastCatchphraseReports[catchphrase.id] = DateTime.now();
      state = state.copyWith(
        catchphraseDetectionActive: true,
        catchphraseReportCount: state.catchphraseReportCount + 1,
        lastCatchphraseLabel: catchphrase.phrase,
        statusMessage: 'Catchphrase reported: ${catchphrase.phrase}',
      );
    }
  }
}
