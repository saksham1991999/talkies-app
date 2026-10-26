import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/state/reminders.dart';

// PluginReminders against a mocked platform channel: what it sends to Android.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var initAnswer = true;
  var permissionAnswer = true;

  setUp(() {
    calls.clear();
    initAnswer = true;
    permissionAnswer = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => initAnswer,
        'requestNotificationsPermission' => permissionAnswer,
        _ => null,
      };
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  List<String> methods() => [for (final c in calls) c.method];

  test('nothing happens until the first use', () {
    PluginReminders();
    expect(calls, isEmpty);
  });

  test('schedule: starts the plugin once, then one inexact alarm at an absolute instant', () async {
    final r = PluginReminders();
    final when = DateTime.now().toUtc().add(const Duration(days: 2));
    await r.schedule(id: 42, title: 'Dune tonight', body: 'In 2 hours', when: when);
    await r.schedule(id: 43, title: 'Dune tonight', body: 'Tomorrow', when: when.add(const Duration(hours: 1)));
    expect(methods(), ['initialize', 'zonedSchedule', 'zonedSchedule']);
    final a = calls[1].arguments as Map;
    expect((a['id'], a['title'], a['body']), (42, 'Dune tonight', 'In 2 hours'));
    expect(a['timeZoneName'], 'Etc/UTC', reason: 'an instant, not a wall clock of this phone');
    expect((a['platformSpecifics'] as Map)['scheduleMode'], 'inexactAllowWhileIdle');
    expect(a['scheduledDateTime'], when.toIso8601String().split('.').first.replaceAll('Z', ''));
    expect(a.containsKey('matchDateTimeComponents'), isFalse, reason: 'one time, not a repeat');
  });

  test('a time in the past is ignored without even starting the plugin', () async {
    final r = PluginReminders();
    await r.schedule(id: 1, title: 't', body: 'b', when: DateTime.now().subtract(const Duration(seconds: 1)));
    expect(calls, isEmpty);
  });

  test('permission: asked on Android, and the answer is passed on', () async {
    final r = PluginReminders();
    expect(await r.ensurePermission(), isTrue);
    expect(methods(), ['initialize', 'requestNotificationsPermission']);
    permissionAnswer = false;
    expect(await r.ensurePermission(), isFalse);
  });

  test('cancel by id', () async {
    final r = PluginReminders();
    await r.cancel(7);
    expect(methods(), ['initialize', 'cancel']);
    expect((calls.last.arguments as Map)['id'], 7);
  });

  test('a plugin that fails to start does nothing, and the next call tries again', () async {
    final r = PluginReminders();
    initAnswer = false;
    expect(await r.ensurePermission(), isFalse);
    await r.schedule(id: 1, title: 't', body: 'b', when: DateTime.now().add(const Duration(days: 1)));
    expect(methods(), ['initialize', 'initialize'], reason: 'no schedule without a started plugin');
    initAnswer = true;
    await r.schedule(id: 1, title: 't', body: 'b', when: DateTime.now().add(const Duration(days: 1)));
    expect(methods(), ['initialize', 'initialize', 'initialize', 'zonedSchedule']);
  });
}
