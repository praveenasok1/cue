import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class TranscriptionChunk {
  const TranscriptionChunk({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

class TranscriptionService {
  TranscriptionService({SpeechToText? speechToText})
    : _speechToText = speechToText ?? SpeechToText();

  final SpeechToText _speechToText;
  final _chunks = StreamController<TranscriptionChunk>.broadcast();
  final _soundLevels = StreamController<double>.broadcast();
  bool _shouldListen = false;
  bool _initialized = false;

  Stream<TranscriptionChunk> get chunks => _chunks.stream;
  Stream<double> get soundLevels => _soundLevels.stream;

  Future<void> start() async {
    _shouldListen = true;
    if (!_initialized) {
      final available = await _speechToText.initialize(
        onError: (error) {
          _chunks.add(
            TranscriptionChunk(
              text: 'Speech recognition error: ${error.errorMsg}',
              isFinal: true,
            ),
          );
        },
        onStatus: _handleStatus,
      );
      if (!available) {
        throw StateError('Speech recognition is not available on this device.');
      }
      _initialized = true;
    }

    await _startListening();
  }

  Future<void> _startListening() async {
    if (!_shouldListen || _speechToText.isListening) return;

    await _speechToText.listen(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      onResult: _handleResult,
      onSoundLevelChange: _handleSoundLevel,
    );
  }

  Future<void> stop() async {
    _shouldListen = false;
    await _speechToText.stop();
  }

  Future<void> pause() => stop();

  Future<void> resume() => start();

  Future<void> dispose() async {
    _shouldListen = false;
    await _speechToText.cancel();
    await _soundLevels.close();
    await _chunks.close();
  }

  void _handleStatus(String status) {
    if (!_shouldListen) return;
    if (status == 'done' || status == 'notListening') {
      Future<void>.delayed(const Duration(milliseconds: 350), _startListening);
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    _chunks.add(TranscriptionChunk(text: text, isFinal: result.finalResult));
  }

  void _handleSoundLevel(double level) {
    if (!level.isFinite) return;
    final normalized = switch (level) {
      >= 0 && <= 1 => level,
      < 0 => (level + 60) / 60,
      _ => level / 20,
    };
    _soundLevels.add(normalized.clamp(0, 1).toDouble());
  }
}
