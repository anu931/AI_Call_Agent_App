/// AppConfig — single source of truth for all runtime constants.
/// Change [backendBase] here to update every screen and service at once.
class AppConfig {
  AppConfig._();

  /// Base URL of the FastAPI backend.
  /// Override via --dart-define=BACKEND_URL=http://... for CI / different envs.
  static const backendBase = String.fromEnvironment(
    'BACKEND_URL',
     defaultValue: 'http://10.40.6.149:8000',  );

  static const methodChannel = 'com.example.crm_app/call_logs';
}