import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Microsoft Graph / To-Do integration.
///
/// Setup (see docs/microsoft-todo.md):
///   1. Register an Azure AD app with `Tasks.ReadWrite` scope.
///   2. Store the client ID as `MICROSOFT_CLIENT_ID` in your environment or
///      paste it into Settings inside the app.
///   3. The app uses OAuth 2.0 PKCE device-code flow (no redirect URI needed).
class MicrosoftToDoService {
  static const _clientIdKey = 'cue.ms_todo_client_id';
  static const _accessTokenKey = 'cue.ms_todo_access_token';
  static const _refreshTokenKey = 'cue.ms_todo_refresh_token';
  static const _tokenExpiryKey = 'cue.ms_todo_token_expiry';
  static const _listIdKey = 'cue.ms_todo_list_id';

  static const _graphBase = 'https://graph.microsoft.com/v1.0';
  static const _deviceCodeUrl =
      'https://login.microsoftonline.com/common/oauth2/v2.0/devicecode';
  static const _tokenUrl =
      'https://login.microsoftonline.com/common/oauth2/v2.0/token';
  static const _scope = 'Tasks.ReadWrite offline_access';

  final _prefs = SharedPreferencesAsync();

  /// Whether the user has configured a client ID and is authenticated.
  Future<bool> get isEnabled async {
    final clientId = await _prefs.getString(_clientIdKey);
    final token = await _prefs.getString(_accessTokenKey);
    return clientId != null && token != null;
  }

  Future<String?> get clientId => _prefs.getString(_clientIdKey);

  Future<void> saveClientId(String id) =>
      _prefs.setString(_clientIdKey, id.trim());

  Future<void> signOut() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_tokenExpiryKey);
    await _prefs.remove(_listIdKey);
  }

  // ── Device-code auth flow ──────────────────────────────────────────────────

  /// Initiates device-code flow. Returns a `DeviceCodePending` so the UI can
  /// display the user-code and poll for completion.
  Future<DeviceCodePending> requestDeviceCode() async {
    final id = await clientId;
    if (id == null || id.isEmpty) {
      throw StateError('Set a Microsoft Azure client ID first.');
    }
    final res = await http.post(
      Uri.parse(_deviceCodeUrl),
      body: {'client_id': id, 'scope': _scope},
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw StateError('Device code error: ${body['error_description']}');
    }
    return DeviceCodePending(
      userCode: body['user_code'] as String,
      verificationUri: body['verification_uri'] as String,
      deviceCode: body['device_code'] as String,
      interval: (body['interval'] as int?) ?? 5,
      clientId: id,
    );
  }

  /// Polls until the user completes sign-in or the code expires.
  /// Calls [onWaiting] with the user code for each waiting period.
  Future<bool> pollForToken(
    DeviceCodePending pending, {
    void Function(String userCode)? onWaiting,
  }) async {
    while (true) {
      await Future<void>.delayed(Duration(seconds: pending.interval));
      final res = await http.post(
        Uri.parse(_tokenUrl),
        body: {
          'client_id': pending.clientId,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': pending.deviceCode,
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        await _saveTokens(body);
        return true;
      }
      final error = body['error'] as String? ?? '';
      if (error == 'authorization_pending') {
        onWaiting?.call(pending.userCode);
        continue;
      }
      // expired, denied, or unknown
      return false;
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> body) async {
    final access = body['access_token'] as String;
    final refresh = body['refresh_token'] as String?;
    final expiresIn = (body['expires_in'] as num).toInt();
    await _prefs.setString(_accessTokenKey, access);
    if (refresh != null) await _prefs.setString(_refreshTokenKey, refresh);
    await _prefs.setInt(
      _tokenExpiryKey,
      DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch,
    );
  }

  Future<String?> _validToken() async {
    final expiry = await _prefs.getInt(_tokenExpiryKey);
    if (expiry != null &&
        DateTime.fromMillisecondsSinceEpoch(
          expiry,
        ).isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return _prefs.getString(_accessTokenKey);
    }
    // Try refresh.
    final refresh = await _prefs.getString(_refreshTokenKey);
    final id = await clientId;
    if (refresh == null || id == null) return null;
    try {
      final res = await http.post(
        Uri.parse(_tokenUrl),
        body: {
          'client_id': id,
          'grant_type': 'refresh_token',
          'refresh_token': refresh,
          'scope': _scope,
        },
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        await _saveTokens(body);
        return _prefs.getString(_accessTokenKey);
      }
    } on Exception catch (e) {
      debugPrint('CUE: MS token refresh failed: $e');
    }
    return null;
  }

  // ── To-Do API ─────────────────────────────────────────────────────────────

  Future<String> _ensureTaskListId() async {
    final cached = await _prefs.getString(_listIdKey);
    if (cached != null) return cached;
    final token = await _validToken();
    if (token == null) throw StateError('Not authenticated with Microsoft.');
    // Find or create a list named "CUE Reminders".
    final listsRes = await http.get(
      Uri.parse('$_graphBase/me/todo/lists'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (listsRes.statusCode == 200) {
      final lists = (jsonDecode(listsRes.body)['value'] as List);
      for (final l in lists) {
        if ((l['displayName'] as String).toLowerCase() == 'cue reminders') {
          final id = l['id'] as String;
          await _prefs.setString(_listIdKey, id);
          return id;
        }
      }
    }
    // Create the list.
    final createRes = await http.post(
      Uri.parse('$_graphBase/me/todo/lists'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'displayName': 'CUE Reminders'}),
    );
    final id = (jsonDecode(createRes.body) as Map)['id'] as String;
    await _prefs.setString(_listIdKey, id);
    return id;
  }

  /// Adds a reminder to Microsoft To-Do and returns the created task ID,
  /// or null if not authenticated / any error.
  Future<String?> addTask({required String title, DateTime? dueAt}) async {
    if (!await isEnabled) return null;
    try {
      final token = await _validToken();
      if (token == null) return null;
      final listId = await _ensureTaskListId();
      final body = <String, dynamic>{'title': title};
      if (dueAt != null) {
        body['dueDateTime'] = {
          'dateTime': dueAt.toUtc().toIso8601String(),
          'timeZone': 'UTC',
        };
      }
      final res = await http.post(
        Uri.parse('$_graphBase/me/todo/lists/$listId/tasks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 201) {
        return (jsonDecode(res.body) as Map)['id'] as String;
      }
    } on Exception catch (e) {
      debugPrint('CUE: MS To-Do addTask failed: $e');
    }
    return null;
  }
}

class DeviceCodePending {
  const DeviceCodePending({
    required this.userCode,
    required this.verificationUri,
    required this.deviceCode,
    required this.interval,
    required this.clientId,
  });

  final String userCode;
  final String verificationUri;
  final String deviceCode;
  final int interval;
  final String clientId;
}
