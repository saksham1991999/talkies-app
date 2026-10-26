/// Build-time switches for the optional Talkies server.
///
/// An empty [kApiUrl] means the app never contacts a Talkies server: no probe,
/// no sign-in, no sync. Set it per build:
/// `flutter build apk --dart-define=TALKIES_API_URL=https://api.example.com`
const kApiUrl = String.fromEnvironment('TALKIES_API_URL');

/// Google Sign-In client ids. Google shows on the sign-in screen only when the
/// server lists it and [kGoogleServerClientId] is set (iOS also needs [kGoogleClientId]).
const kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const kGoogleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Sign in with Apple needs the capability added by hand in Xcode. Until then
/// the button stays hidden: build with `--dart-define=APPLE_SIGN_IN=true` after.
const kAppleSignIn = bool.fromEnvironment('APPLE_SIGN_IN');

/// The API major version this build speaks. `/healthz` must report the same.
const kApiVersion = 1;
