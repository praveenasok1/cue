import 'dart:async';

import 'package:flutter/services.dart';

class AudioRouteState {
  const AudioRouteState({
    required this.earphonesConnected,
    required this.earphoneMicActive,
    required this.earphoneMicAvailable,
    this.routeName = 'Unknown',
    this.inputName = 'Phone microphone',
  });

  final bool earphonesConnected;
  final bool earphoneMicActive;
  final bool earphoneMicAvailable;
  final String routeName;
  final String inputName;

  bool get canStartWithEarphoneMic =>
      earphonesConnected && earphoneMicAvailable;

  bool get hasActiveEarphoneMic => earphonesConnected && earphoneMicActive;
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
      return _fallbackState();
    } on MissingPluginException {
      return _fallbackState();
    }
  }

  Future<AudioRouteState> prepareEarphoneMic() async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, Object?>(
        'prepareEarphoneMic',
      );
      return _stateFromMap(result);
    } on PlatformException {
      return initialState();
    } on MissingPluginException {
      return initialState();
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
        // iOS can create the FlutterViewController just after Dart starts.
        // Keep retrying until the native channel has attached.
      }

      await Future<void>.delayed(const Duration(seconds: 2));
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
      earphoneMicActive: map?['earphoneMicActive'] == true,
      earphoneMicAvailable:
          map?['earphoneMicAvailable'] == true ||
          map?['earphoneMicActive'] == true,
      routeName: (map?['routeName'] as String?) ?? 'Unknown',
      inputName: (map?['inputName'] as String?) ?? 'Phone microphone',
    );
  }

  bool _sameState(AudioRouteState a, AudioRouteState b) {
    return a.earphonesConnected == b.earphonesConnected &&
        a.earphoneMicActive == b.earphoneMicActive &&
        a.earphoneMicAvailable == b.earphoneMicAvailable &&
        a.routeName == b.routeName &&
        a.inputName == b.inputName;
  }

  AudioRouteState _fallbackState() {
    return const AudioRouteState(
      earphonesConnected: false,
      earphoneMicActive: false,
      earphoneMicAvailable: false,
    );
  }
}
