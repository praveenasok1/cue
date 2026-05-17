import 'dart:async';

import 'package:flutter/services.dart';

class AudioRouteState {
  const AudioRouteState({
    required this.earphonesConnected,
    this.routeName = 'Unknown',
  });

  final bool earphonesConnected;
  final String routeName;
}

class AudioRouteService {
  AudioRouteService({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel = methodChannel ?? const MethodChannel('cue/audio_route'),
      _eventChannel =
          eventChannel ?? const EventChannel('cue/audio_route_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Future<AudioRouteState> initialState() async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'currentRoute',
      );
      return _stateFromMap(result);
    } on PlatformException {
      return const AudioRouteState(earphonesConnected: false);
    } on MissingPluginException {
      return const AudioRouteState(earphonesConnected: false);
    }
  }

  Stream<AudioRouteState> routeChanges() async* {
    var latest = await initialState();
    yield latest;

    while (true) {
      try {
        await for (final event in _eventChannel.receiveBroadcastStream()) {
          if (event is! Map) continue;
          final next = _stateFromMap(event.cast<String, Object?>());
          if (!_sameState(next, latest)) {
            latest = next;
            yield latest;
          }
        }
      } on PlatformException {
        // Channel can transiently fail after interruptions; re-subscribe.
      } on MissingPluginException {
        final fallback = await initialState();
        if (!_sameState(fallback, latest)) {
          latest = fallback;
          yield latest;
        }
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 450));
      final refreshed = await initialState();
      if (!_sameState(refreshed, latest)) {
        latest = refreshed;
        yield latest;
      }
    }
  }

  AudioRouteState _stateFromMap(Map<String, Object?>? map) {
    return AudioRouteState(
      earphonesConnected: map?['earphonesConnected'] == true,
      routeName: (map?['routeName'] as String?) ?? 'Unknown',
    );
  }

  bool _sameState(AudioRouteState a, AudioRouteState b) {
    return a.earphonesConnected == b.earphonesConnected &&
        a.routeName == b.routeName;
  }
}
