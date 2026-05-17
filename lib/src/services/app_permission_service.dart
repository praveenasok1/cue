import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  bool _requested = false;

  Future<void> requestStartupPermissions() async {
    if (_requested) return;
    _requested = true;

    final permissions = <Permission>[
      Permission.microphone,
      Permission.speech,
      Permission.locationWhenInUse,
      Permission.notification,
      if (!kIsWeb) Permission.bluetooth,
    ];

    for (final permission in permissions) {
      try {
        final status = await permission.status;
        if (status.isDenied || status.isRestricted || status.isLimited) {
          await permission.request();
        }
      } on Exception {
        // Permission availability differs by platform/version.
      }
    }
  }
}
