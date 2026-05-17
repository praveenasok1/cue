import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/cue_database.dart';
import 'data/models.dart';
import 'services/audio_route_service.dart';
import 'services/catchphrase_audio_service.dart';
import 'services/foreground_recording_service.dart';
import 'services/location_service.dart';
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

  Future<void> saveToday(String text) {
    return ref
        .read(databaseProvider)
        .replaceDailyTranscript(DateTime.now(), text);
  }
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingStatus>(
      RecordingController.new,
    );

class RecordingController extends Notifier<RecordingStatus> {
  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<double>? _speechLevelSubscription;
  StreamSubscription<TranscriptionChunk>? _transcriptionSubscription;

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

    if (route.earphonesConnected && !state.isRecording) {
      await _startRecording(route.routeName);
    } else if (!route.earphonesConnected && state.isRecording) {
      await stopRecording(reason: 'Earphones disconnected');
    }
  }

  Future<void> _startRecording(String source) async {
    try {
      await ref.read(foregroundRecordingServiceProvider).start();
      final recording = await ref.read(recordingServiceProvider).start();
      final session = await ref
          .read(databaseProvider)
          .startSession(source: source, audioPath: recording.path);

      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = ref
          .read(recordingServiceProvider)
          .amplitudeStream()
          .listen((amplitude) {
            state = state.copyWith(amplitude: amplitude);
          });

      _speechLevelSubscription?.cancel();
      _speechLevelSubscription = ref
          .read(transcriptionServiceProvider)
          .soundLevels
          .listen((amplitude) {
            // Speech recognition sound levels are a reliable live fallback on
            // iOS while the recorder is writing the session file.
            if (amplitude > state.amplitude * 0.75) {
              state = state.copyWith(amplitude: amplitude);
            }
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
            }
          });
      await ref.read(transcriptionServiceProvider).start();

      state = state.copyWith(
        isRecording: true,
        session: session,
        statusMessage: 'Recording earphone session',
      );
    } catch (error) {
      await ref.read(foregroundRecordingServiceProvider).stop();
      state = state.copyWith(
        isRecording: false,
        statusMessage: error.toString(),
      );
    }
  }

  Future<void> stopRecording({String reason = 'Stopped'}) async {
    final activeSession = state.session;
    await _amplitudeSubscription?.cancel();
    await _speechLevelSubscription?.cancel();
    await _transcriptionSubscription?.cancel();
    _amplitudeSubscription = null;
    _speechLevelSubscription = null;
    _transcriptionSubscription = null;

    await ref.read(transcriptionServiceProvider).stop();
    await ref.read(recordingServiceProvider).stop();
    await ref.read(foregroundRecordingServiceProvider).stop();
    if (activeSession != null) {
      await ref.read(databaseProvider).endSession(activeSession.id);
    }

    state = state.copyWith(
      isRecording: false,
      clearSession: true,
      amplitude: 0,
      liveTranscript: '',
      statusMessage: reason,
    );
  }

  Future<void> _persistTranscriptChunk(String text) async {
    final database = ref.read(databaseProvider);
    await database.appendTranscript(DateTime.now(), text);
    await _detectCatchphrases(text);
  }

  Future<void> _detectCatchphrases(String text) async {
    final database = ref.read(databaseProvider);
    final catchphrases = await database.getCatchphrases();
    if (catchphrases.isEmpty) return;

    final location = await ref.read(locationServiceProvider).currentLocation();
    for (final catchphrase in catchphrases) {
      final expression = RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(catchphrase.phrase)}'
        r'(?=$|[^A-Za-z0-9_])',
        caseSensitive: false,
      );
      if (expression.hasMatch(text)) {
        await database.logCatchphraseHit(
          catchphrase: catchphrase,
          context: text,
          latitude: location?.latitude,
          longitude: location?.longitude,
        );
      }
    }
  }
}
