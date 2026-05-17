import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingStartResult {
  const RecordingStartResult({required this.path});

  final String path;
}

class RecordingService {
  RecordingService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Stream<double> amplitudeStream() {
    // Poll at 60 ms for smoother waveform on iOS.
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 60)).map((
      amplitude,
    ) {
      // Use the peak value for instant waveform response.
      final db = math.max(amplitude.current, amplitude.max);
      // iOS AVAudioRecorder reports silence as ~-160 dBFS.
      // Map -70 dBFS (near-silence threshold) → 0, 0 dBFS (full scale) → 1.
      if (!db.isFinite || db <= -70) return 0;
      final linear = ((db + 70) / 65).clamp(0, 1);
      // Gentle power curve (0.35) so quiet speech still shows movement.
      return math.pow(linear, 0.35).toDouble();
    });
  }

  Future<RecordingStartResult> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required to record.');
    }

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    await session.setActive(true);

    final directory = await getApplicationDocumentsDirectory();
    final fileName =
        'cue-${DateTime.now().toIso8601String().replaceAll(':', '-')}.m4a';
    final path = p.join(directory.path, fileName);

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    return RecordingStartResult(path: path);
  }

  Future<String?> stop() async {
    final path = await _recorder.stop();
    final session = await AudioSession.instance;
    try {
      await session.setActive(false);
    } on Exception {
      // Session deactivation is best-effort.
    }
    return path;
  }

  Future<void> pause() => _recorder.pause();

  Future<void> resume() => _recorder.resume();

  Future<bool> isRecording() => _recorder.isRecording();

  Future<bool> isPaused() => _recorder.isPaused();

  Future<void> dispose() => _recorder.dispose();
}
