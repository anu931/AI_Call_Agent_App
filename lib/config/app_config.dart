// lib/config/app_config.dart

class AppConfig {
  // ✅ Update ONLY this line when ngrok restarts
static const String _ngrokUrl = 'https://margit-semisentimental-latonya.ngrok-free.dev';

  // Both names point to same URL — keeps all screens compatible
  static const String baseUrl     = _ngrokUrl;
  static const String backendBase = _ngrokUrl;  // ✅ fixes home_screen.dart error

  // Ngrok requires this header to skip browser warning page
  static const Map<String, String> ngrokHeaders = {
    'ngrok-skip-browser-warning': 'true',
    'Content-Type': 'application/json',
  };

  // Timeouts
  static const Duration uploadTimeout   = Duration(minutes: 5);
  static const Duration analysisTimeout = Duration(minutes: 3);
  static const Duration pollInterval    = Duration(seconds: 5);
  static const int      maxPollAttempts = 36; // 36 × 5s = 3 min
}