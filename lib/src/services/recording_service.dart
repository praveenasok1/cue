import 'dart:async';

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
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 90)).map((
      amplitude,
    ) {
      final normalized = ((amplitude.current + 60) / 60).clamp(0, 1);
      return normalized.toDouble();
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
    await session.setActive(false);
    return path;
  }

  Future<void> dispose() => _recorder.dispose();
}
