/// ExamGO App Configuration
/// Centralized constants & secrets
class AppConfig {
  AppConfig._();

  static const String appName = 'ExamGO';

  // [FIX K-2] Sinkronkan dengan pubspec.yaml version: 2.1.0+14
  static const String appVersion = '2.1.0';
  static const int qrFormatVersion = 1;

  /// Secret key for HMAC-SHA256 QR signing.
  /// [FIX K-1] Diinject via --dart-define=QR_SECRET_KEY=NILAI saat build production.
  /// Contoh: flutter build apk --dart-define=QR_SECRET_KEY=nilai_rahasia_prod
  /// Jika tidak ada --dart-define, fallback ke dev key (jangan deploy ke production).
  static const String qrSecretKey = String.fromEnvironment(
    'QR_SECRET_KEY',
    defaultValue: 'ExamGO_S3cr3t_K3y_2024_#K3m3n4g_P3nd1d1k4n_N4s10n4l',
  );

  /// [FIX S-1] QR payload expires setelah 120 menit (2 jam).
  /// Cukup untuk sesi ujian terpanjang sekaligus mencegah penyalahgunaan QR bocor.
  /// Set 0 untuk menonaktifkan expiry (tidak disarankan untuk production).
  static const int qrExpiryMinutes = 120;

  /// [FIX R-3] Turunkan dari 5 ke 3 — lebih ergonomis.
  /// 5× dalam 3 detik hampir tidak mungkin dilakukan satu tangan.
  static const int exitPressRequired = 3;

  /// Seconds window to complete exit press sequence
  static const int exitPressWindowSeconds = 3;

  /// Max scan history entries stored locally
  static const int maxScanHistory = 10;

  /// Prefix to identify ExamGO-signed QR codes
  static const String qrPrefix = 'EXAMGO';
}
