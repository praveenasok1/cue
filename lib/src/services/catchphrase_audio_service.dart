import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class CatchphraseAudioService {
  CatchphraseAudioService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<String> startSampleRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required.');
    }

    final directory = await getApplicationDocumentsDirectory();
    final fileName =
        'cue-catchphrase-${DateTime.now().toIso8601String().replaceAll(':', '-')}.m4a';
    final path = p.join(directory.path, fileName);
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    return path;
  }

  Future<String?> stopSampleRecording() {
    return _recorder.stop();
  }

  Future<void> dispose() => _recorder.dispose();
}
