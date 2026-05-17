import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class TranscriptionChunk {
  const TranscriptionChunk({
    required this.text,
    required this.isFinal,
  });

  final String text;
  final bool isFinal;
}

class TranscriptionService {
  TranscriptionService({SpeechToText? speechToText})
      : _speechToText = speechToText ?? SpeechToText();

  final SpeechToText _speechToText;
  final _chunks = StreamController<TranscriptionChunk>.broadcast();

  Stream<TranscriptionChunk> get chunks => _chunks.stream;

  Future<void> start() async {
    final available = await _speechToText.initialize(
      onError: (error) {
        _chunks.add(TranscriptionChunk(
          text: 'Speech recognition error: ${error.errorMsg}',
          isFinal: true,
        ));
      },
    );
    if (!available) {
      throw StateError('Speech recognition is not available on this device.');
    }

    await _speechToText.listen(
      listenMode: ListenMode.dictation,
      partialResults: true,
      cancelOnError: false,
      onResult: _handleResult,
    );
  }

  Future<void> stop() async {
    await _speechToText.stop();
  }

  Future<void> dispose() async {
    await _speechToText.cancel();
    await _chunks.close();
  }

  void _handleResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    _chunks.add(TranscriptionChunk(
      text: text,
      isFinal: result.finalResult,
    ));
  }
}
