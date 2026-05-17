import 'dart:async';

import 'package:geolocator/geolocator.dart';

class CueLocation {
  const CueLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class LocationService {
  Future<CueLocation?> currentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return CueLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on TimeoutException {
      return null;
    } on Exception {
      return null;
    }
  }
}
