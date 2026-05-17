import 'package:cue/src/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CatchphraseTag has expected tag names', () {
    expect(CatchphraseTag.countOnly.name, 'countOnly');
    expect(CatchphraseTag.reminder.name, 'reminder');
    expect(CatchphraseTag.delegate.name, 'delegate');
    expect(CatchphraseTag.transcribeSeparately.name, 'transcribeSeparately');
  });

  test('recording status can clear active sessions', () {
    final session = RecordingSession(
      id: 1,
      startedAt: DateTime(2026),
      source: 'Bluetooth',
    );
    final status = RecordingStatus(
      isRecording: true,
      earphonesConnected: true,
      session: session,
    );
    final stopped = status.copyWith(isRecording: false, clearSession: true);
    expect(stopped.isRecording, isFalse);
    expect(stopped.session, isNull);
    expect(stopped.earphonesConnected, isTrue);
  });
}
