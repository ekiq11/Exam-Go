/// ExamGO App Configuration
/// Centralized constants & secrets
class AppConfig {
  AppConfig._();

  static const String appName = 'ExamGO';

  // Sync dengan pubspec.yaml: version: 7.0.2+41
  static const String appVersion = '7.0.2';
  static const int appBuildNumber = 41;
  static const int qrFormatVersion = 1;

  /// Secret key for HMAC-SHA256 QR signing.
  /// [FIX K-1] Diinject via --dart-define=QR_SECRET_KEY=NILAI saat build production.
  /// Contoh: flutter build apk --dart-define=QR_SECRET_KEY=nilai_rahasia_prod
  /// Jika tidak ada --dart-define, fallback ke dev key (jangan deploy ke production).
  static const String qrSecretKey = String.fromEnvironment(
    'QR_SECRET_KEY',
    defaultValue: 'ExamGO_S3cr3t_K3y_2024_#K3m3n4g_P3nd1d1k4n_N4s10n4l',
  );
  /// [FIX S-1] QR payload expires setelah 7 hari (10080 menit).
  /// Cukup untuk sesi ujian terpanjang sekaligus mencegah penyalahgunaan QR bocor.
  /// Set 0 untuk menonaktifkan expiry (tidak disarankan untuk production).
  static const int qrExpiryMinutes = 10080;

  /// [FIX R-3] Turunkan dari 5 ke 3 — lebih ergonomis.
  /// 5× dalam 3 detik hampir tidak mungkin dilakukan satu tangan.
  static const int exitPressRequired = 3;

  /// Seconds window to complete exit press sequence
  static const int exitPressWindowSeconds = 3;

  /// Max scan history entries stored locally
  static const int maxScanHistory = 10;

  /// Prefix to identify ExamGO-signed QR codes
  static const String qrPrefix = 'EXAMGO';

  // ── GAS (Google Apps Script) Backend ──────────────────────────
  // URL GAS bukan rahasia — keamanan dijaga oleh API_KEY di GAS Script Properties.
  // Inject via: flutter build apk --dart-define=GAS_URL=...
  // Default sudah diset ke URL produksi ExamGO.
  static const String gasUrl = String.fromEnvironment(
    'GAS_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbyz4bm0GIgLkyGDLBE0u9yPsZnNB6OvObMszvyY-g6UxwlsByBnpnEchoHKrahoay2ZUA/exec',
  );

  // API key rahasia yang sama dengan Script Properties 'API_KEY' di GAS.
  // WAJIB diinject via: flutter build apk --dart-define=GAS_API_KEY=nilai_rahasia
  // Tanpa ini fitur notifikasi guru dinonaktifkan.
  static const String gasApiKey = String.fromEnvironment(
    'GAS_API_KEY',
    defaultValue: 'examgo_guru_2026',
  );
}
