import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';

import '../support/fake_backend.dart';

class _Status extends BackendNotifier {
  _Status(this.status);
  final Backend status;
  @override
  Backend build() => status;
}

class _Who extends SessionNotifier {
  _Who(this.session);
  final Session? session;
  @override
  Session? build() => session;
}

class _Methods extends ServerAuth {
  _Methods(this.methods);
  final List<String> methods;
  @override
  List<String> build() => methods;
}

const _url = 'https://talkies.test';

void main() {
  test('every gate for every combination of build, status, account, platform and server', () {
    final listed = [
      <String>[],
      ['email'],
      ['email', 'google'],
      ['email', 'apple'],
      ['email', 'google', 'apple'],
    ];
    var rows = 0;
    for (final configured in [false, true]) {
      for (final status in [Backend.unknown, Backend.up, Backend.down]) {
        for (final signedIn in [false, true]) {
          for (final ios in [false, true]) {
            for (final auth in listed) {
              for (final googleIds in [false, true]) {
                for (final appleOn in [false, true]) {
                  final c = ProviderContainer(
                    overrides: [
                      apiUrlProvider.overrideWithValue(configured ? _url : ''),
                      if (configured) backendProvider.overrideWith(() => _Status(status)),
                      sessionProvider.overrideWith(() => _Who(signedIn ? const Session('u1') : null)),
                      serverAuthProvider.overrideWith(() => _Methods(auth)),
                      isIosProvider.overrideWithValue(ios),
                      googleConfiguredProvider.overrideWithValue(googleIds),
                      appleConfiguredProvider.overrideWithValue(appleOn),
                    ],
                  );
                  addTearDown(c.dispose);
                  final up = configured && status == Backend.up;
                  final offer = up && !signedIn; // the sign-in screen can be shown at all
                  final apple = offer && ios && appleOn && auth.contains('apple');
                  final google = offer && auth.contains('google') && googleIds && (!ios || apple);
                  final why =
                      'configured=$configured status=$status signedIn=$signedIn ios=$ios auth=$auth google=$googleIds apple=$appleOn';

                  expect(c.read(backendProvider), configured ? status : Backend.none, reason: why);
                  expect(c.read(signedInProvider), signedIn, reason: why);
                  expect(c.read(onlineProvider), up && signedIn, reason: why);
                  expect(c.read(signInVisibleProvider), offer, reason: why);
                  expect(c.read(emailVisibleProvider), offer && auth.contains('email'), reason: why);
                  expect(c.read(appleVisibleProvider), apple, reason: why);
                  expect(c.read(googleVisibleProvider), google, reason: why);
                  rows++;
                }
              }
            }
          }
        }
      }
    }
    expect(rows, 2 * 3 * 2 * 2 * 5 * 2 * 2);
  });

  test('on iOS, Google never shows without Apple (App Store rule 4.8)', () {
    final c = ProviderContainer(
      overrides: [
        apiUrlProvider.overrideWithValue(_url),
        backendProvider.overrideWith(() => _Status(Backend.up)),
        sessionProvider.overrideWith(() => _Who(null)),
        serverAuthProvider.overrideWith(() => _Methods(['email', 'google', 'apple'])),
        googleConfiguredProvider.overrideWithValue(true),
        isIosProvider.overrideWithValue(true),
        appleConfiguredProvider.overrideWithValue(false), // the Xcode capability is not added yet
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(appleVisibleProvider), isFalse);
    expect(c.read(googleVisibleProvider), isFalse);
    expect(c.read(emailVisibleProvider), isTrue);
  });

  test('a build with no server never reads the documents folder, a session, or the network', () {
    final server = FakeBackend();
    // No docsDirProvider override: a read of session.json would throw.
    final c = ProviderContainer(
      overrides: [apiUrlProvider.overrideWithValue(''), httpClientProvider.overrideWithValue(server.client)],
    );
    addTearDown(c.dispose);
    expect(c.read(backendProvider), Backend.none);
    expect(c.read(sessionProvider), isNull);
    expect(c.read(signedInProvider), isFalse);
    expect(c.read(onlineProvider), isFalse);
    expect(c.read(signInVisibleProvider), isFalse);
    expect(c.read(googleVisibleProvider), isFalse);
    expect(c.read(appleVisibleProvider), isFalse);
    expect(server.total, 0);
  });

  test('the status flips only through the probe, markDown and markUp', () {
    final c = ProviderContainer(overrides: [apiUrlProvider.overrideWithValue(_url)]);
    addTearDown(c.dispose);
    final b = c.read(backendProvider.notifier);
    expect(c.read(backendProvider), Backend.unknown);
    b.markDown();
    expect(c.read(backendProvider), Backend.down);
    b.markUp();
    expect(c.read(backendProvider), Backend.up);

    final none = ProviderContainer(overrides: [apiUrlProvider.overrideWithValue('')]);
    addTearDown(none.dispose);
    none.read(backendProvider.notifier)
      ..markDown()
      ..markUp();
    expect(none.read(backendProvider), Backend.none);
  });
}
