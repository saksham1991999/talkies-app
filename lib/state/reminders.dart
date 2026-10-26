import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// Local reminders for movie nights. The caller writes the texts (the UI passes
/// localized strings); nothing here is translated.
abstract class Reminders {
  /// Asks for notification permission if needed. False when the user said no.
  Future<bool> ensurePermission();

  /// Shows a notification at [when], an absolute instant. A time in the past is ignored.
  Future<void> schedule({required int id, required String title, required String body, required DateTime when});

  Future<void> cancel(int id);
}

/// Id of the reminder for [slot] (0 or 1, see `reminderLeads`) of a night: 30 bits
/// of an FNV-1a hash of the night id, then the slot. The plugin takes 32-bit ids.
int reminderId(String nightId, int slot) {
  var h = 0x811c9dc5;
  for (final u in nightId.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xffffffff;
  }
  return ((h & 0x3fffffff) << 1) | (slot & 1);
}

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'nights',
    'Movie nights',
    channelDescription: 'Reminders before a movie night',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  ),
  iOS: DarwinNotificationDetails(),
);

/// [Reminders] over flutter_local_notifications. The plugin starts at the first
/// call, never at app start. Alarms are inexact, so Android needs no exact-alarm
/// permission and a reminder may come a few minutes late.
class PluginReminders implements Reminders {
  PluginReminders([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  Future<bool> _init() => _ready ??= _setUp();

  Future<bool> _setUp() async {
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is asked in ensurePermission, at the first toggle.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      if (ok == true) return true;
    } catch (_) {
      // Falls through: the next call tries again.
    }
    _ready = null;
    return false;
  }

  @override
  Future<bool> ensurePermission() async {
    if (!await _init()) return false;
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule({required int id, required String title, required String body, required DateTime when}) async {
    if (!when.isAfter(DateTime.now()) || !await _init()) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      // An absolute instant: the device zone does not matter.
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!await _init()) return;
    await _plugin.cancel(id: id);
  }
}

/// Records what would be scheduled. For tests, and for widget tests that override [remindersProvider].
class FakeReminders implements Reminders {
  FakeReminders({this.granted = true});

  /// The answer of [ensurePermission].
  bool granted;
  int permissionAsks = 0;

  /// Pending reminders by id.
  final Map<int, ({String title, String body, DateTime when})> scheduled = {};

  @override
  Future<bool> ensurePermission() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<void> schedule({required int id, required String title, required String body, required DateTime when}) async {
    scheduled[id] = (title: title, body: body, when: when);
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }
}

/// Overridden in tests with [FakeReminders]. Reading it does not touch the plugin.
final remindersProvider = Provider<Reminders>((ref) => PluginReminders());
