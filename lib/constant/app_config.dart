/// ExamGO App Configuration
/// Centralized constants & secrets
class AppConfig {
  AppConfig._();

  static const String appName = 'ExamGO';
  static const String appVersion = '2.0.0';
  static const int qrFormatVersion = 1;

  /// Secret key for HMAC-SHA256 QR signing.
  /// In production, consider injecting this via --dart-define or a secure build config.
  static const String qrSecretKey =
      'ExamGO_S3cr3t_K3y_2024_#K3m3n4g_P3nd1d1k4n_N4s10n4l';

  /// QR payload expires after this many minutes (0 = no expiry)
  static const int qrExpiryMinutes = 0;

  /// How many times user must press "Exit" to confirm exit
  static const int exitPressRequired = 5;

  /// Seconds window to complete exit press sequence
  static const int exitPressWindowSeconds = 3;

  /// Max scan history entries stored locally
  static const int maxScanHistory = 5;

  /// Prefix to identify ExamGO-signed QR codes
  static const String qrPrefix = 'EXAMGO';
}
