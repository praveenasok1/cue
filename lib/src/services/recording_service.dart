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
    // A 120 ms level cadence keeps the meter responsive without burning power.
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).map((
      amplitude,
    ) {
      final current = amplitude.current;
      final peak = amplitude.max;
      // Prefer current dBFS; fall back to peak only if current is unavailable.
      final db = current.isFinite && current > -120 ? current : peak;
      // iOS AVAudioRecorder reports silence as ~-160 dBFS.
      // Map -80 dBFS (near-silence threshold) → 0, 0 dBFS (full scale) → 1.
      if (!db.isFinite || db <= -80) return 0;
      final linear = ((db + 80) / 80).clamp(0, 1);
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
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
    await session.setActive(true);

    final directory = await getApplicationDocumentsDirectory();
    final fileName =
        'cue-${DateTime.now().toIso8601String().replaceAll(':', '-')}.m4a';
    final path = p.join(directory.path, fileName);
    final device = await _preferredInputDevice();

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
        device: device,
        autoGain: true,
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

  Future<InputDevice?> _preferredInputDevice() async {
    final devices = await _recorder.listInputDevices().catchError((_) {
      return <InputDevice>[];
    });
    for (final device in devices) {
      final label = device.label.toLowerCase();
      final looksLikeEarphoneMic =
          label.contains('airpods') ||
          label.contains('bluetooth') ||
          label.contains('headset') ||
          label.contains('headphone') ||
          label.contains('usb') ||
          label.contains('ear');
      final looksBuiltIn =
          label.contains('iphone') ||
          label.contains('built-in') ||
          label.contains('built in');
      if (looksLikeEarphoneMic && !looksBuiltIn) {
        return device;
      }
    }
    return null;
  }
}
