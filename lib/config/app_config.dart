/// AppConfig — single source of truth for all runtime constants.
/// Change [backendBase] here to update every screen and service at once.
class AppConfig {
  AppConfig._();

  /// Base URL of the FastAPI backend.
  /// Override via --dart-define=BACKEND_URL=http://... for CI / different envs.
  static const backendBase = String.fromEnvironment(
    'BACKEND_URL',
     defaultValue: 'https://aicallagentapp-production.up.railway.app', );

  static const methodChannel = 'com.example.crm_app/call_logs';
}