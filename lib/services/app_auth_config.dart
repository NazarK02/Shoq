class AppAuthConfig {
  AppAuthConfig._();

  /// Windows Desktop OAuth client ID for Google Sign-In.
  ///
  /// This default uses the project's known Google OAuth web client ID so
  /// Windows Google login can work without passing dart-defines on `flutter run`.
  /// If Google login still fails, replace this with your Desktop OAuth client ID.
  static const String windowsGoogleClientId =
      '377919689277-tpgo1k9rqmkss9sbj8ou2n49j35k243k.apps.googleusercontent.com';

  /// Optional. Usually empty for Desktop OAuth clients.
  static const String windowsGoogleClientSecret = '';

  /// Use one fixed loopback redirect URI for every Windows machine.
  ///
  /// This avoids per-run/per-machine redirect differences.
  /// If you use a Web OAuth client ID, add this exact URI in
  /// Google Cloud Console -> OAuth client -> Authorized redirect URIs.
  static const String windowsGoogleRedirectHost = '127.0.0.1';
  static const int windowsGoogleRedirectPort = 53682;
  static const String windowsGoogleRedirectPath = '/oauth2callback';
}
