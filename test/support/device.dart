import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/wire.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/sync.dart';

import 'fake_backend.dart';

/// Secure storage in memory, one per phone. [failing] makes every call throw, like a missing keychain.
class MemoryStorage extends FlutterSecureStorage {
  MemoryStorage({this.failing = false});

  final data = <String, String>{};
  bool failing;
  int reads = 0;

  /// When set, every read waits for it: a keychain that answers late.
  Completer<void>? gate;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    if (failing) throw PlatformException(code: 'keychain');
    final g = gate;
    if (g != null) await g.future;
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failing) throw PlatformException(code: 'keychain');
    value == null ? data.remove(key) : data[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failing) throw PlatformException(code: 'keychain');
    data.remove(key);
  }
}

/// A phone's clock.
class Clock {
  Clock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// A few films, enough for taste and wire tests.
Catalog testCatalog() => Catalog.parse(
  jsonEncode({
    'built': '2026-09-30',
    'items': [
      {
        'id': 'Q1',
        't': 'Sholay',
        'd': '1975-08-15',
        'y': 1975,
        'rt': 204,
        'dir': ['Ramesh Sippy'],
        'cast': ['Amitabh Bachchan', 'Dharmendra'],
        'g': ['action', 'drama'],
        'l': ['hi'],
        'c': ['IN'],
        'pop': 48,
      },
      {
        'id': 'Q2',
        't': 'Dilwale Dulhania Le Jayenge',
        'd': '1995-10-20',
        'y': 1995,
        'dir': ['Aditya Chopra'],
        'cast': ['Shah Rukh Khan', 'Kajol'],
        'g': ['romance'],
        'l': ['hi'],
        'c': ['IN'],
        'pop': 40,
      },
      {
        'id': 'Q3',
        't': 'K.G.F: Chapter 2',
        'd': '2022-04-14',
        'y': 2022,
        'dir': ['Prashanth Neel'],
        'cast': ['Yash'],
        'g': ['action'],
        'l': ['kn'],
        'c': ['IN'],
        'pop': 30,
      },
      {
        'id': 'Q4',
        't': 'Kantara',
        'd': '2022-09-30',
        'y': 2022,
        'dir': ['Rishab Shetty'],
        'cast': ['Rishab Shetty'],
        'g': ['drama'],
        'l': ['kn'],
        'c': ['IN'],
        'pop': 25,
      },
      {
        'id': 'Q5',
        't': 'Panchayat',
        'd': '2020-04-03',
        'y': 2020,
        'l': ['hi'],
        'c': ['IN'],
        'k': 's',
        'pop': 12,
      },
    ],
  }),
  null,
);

/// One phone: its own documents folder, secure storage and clock, a shared [FakeBackend], and a
/// `ProviderContainer` with `autoRefreshProvider` off, so nothing runs unless the test says so.
class Device {
  Device(
    this.server, {
    DateTime? at,
    Directory? dir,
    this.catalog,
    this.auto = false,
    this.overrides = const [],
    http.Client? client,
  }) : clock = Clock(at ?? server.now),
       dir = dir ?? Directory.systemTemp.createTempSync('talkies_dev'),
       storage = MemoryStorage(),
       client = client ?? server.client {
    addTearDown(() {
      if (this.dir.existsSync()) this.dir.deleteSync(recursive: true);
    });
    catalog ??= testCatalog();
    c = _make();
  }

  final FakeBackend server;
  final Clock clock;
  final Directory dir;
  final MemoryStorage storage;

  /// The http client behind [httpClientProvider]; defaults to the server's.
  final http.Client client;
  Catalog? catalog;

  /// True lets the engine's timers run (debounce, backoff, taste). Use it only under fake time.
  final bool auto;

  /// Extra overrides, for the native sign-in functions for example.
  final List<Override> overrides;
  late ProviderContainer c;

  ProviderContainer _make() {
    final pc = ProviderContainer.test(
      overrides: [
        docsDirProvider.overrideWithValue(dir),
        apiUrlProvider.overrideWithValue('https://talkies.test'),
        httpClientProvider.overrideWithValue(client),
        tokenStoreProvider.overrideWithValue(TokenStore(storage)),
        autoRefreshProvider.overrideWithValue(auto),
        nowProvider.overrideWithValue(clock.call),
        todayProvider.overrideWithValue(DateTime(2026, 10, 1)),
        catalogProvider.overrideWith((ref) => catalog!),
        ...overrides,
      ],
    );
    pc.read(syncEngineProvider); // listens to the diary, so edits are stamped when they happen
    return pc;
  }

  DiaryNotifier get diaryN => c.read(diaryProvider.notifier);
  Diary get diary => c.read(diaryProvider);
  SyncEngine get engine => c.read(syncEngineProvider.notifier);
  SyncState get syncState => c.read(syncEngineProvider);
  SyncStore get store => c.read(syncStoreProvider);
  SessionNotifier get session => c.read(sessionProvider.notifier);
  BackendNotifier get backend => c.read(backendProvider.notifier);
  Film film(String id) => catalog!.byId[id]!;

  /// Signs in by email code, like the sign-in screen does.
  Future<void> signIn([String email = 'me@example.test']) async {
    await backend.probe(force: true);
    expect(await session.verifyCode(email, server.code), AuthResult.ok);
  }

  /// Records a viewing at the phone's clock.
  Stub watch(String filmId, {double? rating, DateTime? date, bool private = false, String? memo}) => diaryN.addStub(
    film(filmId),
    StubDraft(rating: rating, date: date, private: private, memo: memo ?? ''),
    now: clock.now,
  );

  /// One sync run, after a probe when the status is not `up`.
  Future<void> sync() async {
    if (c.read(backendProvider) != Backend.up) await backend.probe(force: true);
    await engine.run();
  }

  /// Waits for every pending file write.
  Future<void> flush() async {
    await diaryN.flush();
    await c.read(syncStoreProvider).flush();
    await session.flush();
  }

  /// A new process on the same folder and the same secure storage.
  Future<void> restart() async {
    await flush();
    c.dispose();
    c = _make();
  }

  Stub stub(String id) => diary.stubs.firstWhere((s) => s.id == id);
}
