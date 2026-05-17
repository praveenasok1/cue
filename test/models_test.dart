import 'package:cue/src/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catchphrase polarity maps from persisted symbols', () {
    expect(HabitPolarity.fromSymbol('+'), HabitPolarity.desired);
    expect(HabitPolarity.fromSymbol('-'), HabitPolarity.undesired);
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
