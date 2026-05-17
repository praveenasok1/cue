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
    yield await initialState();
    yield* _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            return _stateFromMap(event.cast<String, Object?>());
          }
          return const AudioRouteState(earphonesConnected: false);
        })
        .handleError((Object _) {
          return const AudioRouteState(earphonesConnected: false);
        });
  }

  AudioRouteState _stateFromMap(Map<String, Object?>? map) {
    return AudioRouteState(
      earphonesConnected: map?['earphonesConnected'] == true,
      routeName: (map?['routeName'] as String?) ?? 'Unknown',
    );
  }
}
