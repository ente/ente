enum EnteApp { auth, locker, photos }

class AppThemeConfig {
  static EnteApp? _currentApp;

  static void initialize(EnteApp app) {
    _currentApp = app;
  }

  static EnteApp get currentApp => _currentApp ?? EnteApp.auth;
}
