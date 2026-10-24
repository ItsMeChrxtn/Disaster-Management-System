import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import 'api.dart';
import 'session.dart';
import 'ui.dart';

const _channelId = 'alerts';
const _channelName = 'Emergency alerts';
const _channelDescription = 'Disaster Map emergency advisories and PDRRMO coordination messages';
const _backgroundTask = 'dm-notification-check';
const _seenKey = 'dm_seen_notification_ids';
const _primedKey = 'dm_notifications_primed';

/// Runs in a background isolate (Android WorkManager) while the app is closed.
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await _initPlugin(plugin);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('dm_token');
      if (token == null || token.isEmpty) return true;
      final base = prefs.getString('dm_api_url') ?? AppConfig.defaultApiUrl;
      final response = await http.get(Uri.parse('$base/notifications/history'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'}).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return true;
      final body = jsonDecode(response.body);
      final rows = ((body is Map ? body['data'] : null) as List? ?? const []).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      await _notifyNew(plugin, prefs, rows);
    } catch (_) {
      // A failed background check simply waits for the next run.
    }
    return true;
  });
}

Future<void> _initPlugin(FlutterLocalNotificationsPlugin plugin) async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(settings: const InitializationSettings(android: android));
  await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
    const AndroidNotificationChannel(_channelId, _channelName, description: _channelDescription, importance: Importance.high),
  );
}

bool _isUnread(Map<String, dynamic> row) => !(row['is_read'] == true || row['is_read'] == 1 || row['is_read'] == '1');

/// Shows a tray notification for every unread item not seen before and returns the newest one.
/// The very first check after sign-in only records what already exists, so old alerts do not flood the tray.
Future<Map<String, dynamic>?> _notifyNew(FlutterLocalNotificationsPlugin plugin, SharedPreferences prefs, List<Map<String, dynamic>> rows) async {
  final seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
  final primed = prefs.getBool(_primedKey) ?? false;
  final fresh = rows.where((row) => _isUnread(row) && !seen.contains(row['id'].toString())).toList();
  seen.addAll(rows.map((row) => row['id'].toString()));
  final trimmed = seen.toList();
  await prefs.setStringList(_seenKey, trimmed.length > 400 ? trimmed.sublist(trimmed.length - 400) : trimmed);
  await prefs.setBool(_primedKey, true);
  if (!primed || fresh.isEmpty) return null;
  for (final row in fresh.take(4)) {
    await _showNotification(plugin, row);
  }
  if (fresh.length > 4) {
    await _showNotification(plugin, {'id': 'summary', 'title': '${fresh.length - 4} more notifications', 'message': 'Open Disaster Map to see every alert and message.'});
  }
  return fresh.first;
}

Future<void> _showNotification(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> row) async {
  final level = (row['alert_level'] ?? '').toString();
  final kind = (row['kind'] ?? 'alert').toString();
  final message = (row['message'] ?? '').toString();
  final color = level == 'critical'
      ? const Color(0xFFDC2626)
      : kind == 'coordination'
      ? const Color(0xFF1D4ED8)
      : const Color(0xFFF59E0B);
  await plugin.show(
    id: row['id'].toString().hashCode & 0x7fffffff,
    title: (row['title'] ?? 'Disaster Map').toString(),
    body: message,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        color: color,
        styleInformation: BigTextStyleInformation(message),
      ),
    ),
  );
}

/// Notification bell state shared by every screen, plus device tray notifications:
/// a 30-second poll while the app is open and an Android WorkManager check
/// (about every 15 minutes, the Android minimum) while it is in the background or closed.
class AlertNotifier extends ChangeNotifier {
  AlertNotifier._();

  static final AlertNotifier instance = AlertNotifier._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Timer? _timer;
  bool _ready = false;

  List<Map<String, dynamic>> history = [];
  int unreadCount = 0;

  /// Latest alert surfaced as an in-app banner (consumed once by the shell).
  Map<String, dynamic>? latestUnseen;

  Future<void> init() async {
    if (_ready) return;
    await _initPlugin(_plugin);
    try {
      await Workmanager().initialize(notificationCallbackDispatcher);
    } catch (_) {
      // Background checks are unavailable on this platform; foreground polling still works.
    }
    _ready = true;
  }

  Future<void> requestPermission() async {
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  void start() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(AppConfig.alertPoll, (_) => refresh());
    Workmanager()
        .registerPeriodicTask(
          _backgroundTask,
          _backgroundTask,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        )
        .catchError((_) {});
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    history = [];
    unreadCount = 0;
    notifyListeners();
    try {
      await Workmanager().cancelByUniqueName(_backgroundTask);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seenKey);
    await prefs.remove(_primedKey);
  }

  Future<void> refresh() async {
    final session = Session.instance;
    if (!session.isAuthenticated) return;
    try {
      history = rowsOf(await Api.instance.get('/notifications/history'));
      unreadCount = history.where(_isUnread).length;
      final prefs = await SharedPreferences.getInstance();
      final newest = await _notifyNew(_plugin, prefs, history);
      if (newest != null) latestUnseen = newest;
      notifyListeners();
    } catch (_) {
      // Polling failures are silent, as on the web.
    }
  }

  Future<void> markRead(Object id) async {
    await Api.instance.post('/notifications/$id/read', {});
    await refresh();
  }

  Future<void> markAllRead() async {
    final unread = history.where(_isUnread);
    await Future.wait(unread.map((a) => Api.instance.post('/notifications/${a['id']}/read', {})));
    await refresh();
  }
}

bool isRead(Map<String, dynamic> alert) => alert['is_read'] == true || alert['is_read'] == 1 || alert['is_read'] == '1';
