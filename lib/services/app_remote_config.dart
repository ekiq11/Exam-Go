// lib/services/app_remote_config.dart
// ignore_for_file: avoid_print
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Wrapper singleton untuk Firebase Remote Config.
/// Nilai defaultnya sinkron dengan AppConfig agar app tetap berjalan
/// walaupun tidak ada koneksi internet.
class AppRemoteConfig {
  AppRemoteConfig._();
  static final AppRemoteConfig instance = AppRemoteConfig._();

  final _rc = FirebaseRemoteConfig.instance;
  bool _initialized = false;

  // ─── Keys ─────────────────────────────────────────────────────
  static const _kQrExpiry       = 'qr_expiry_minutes';
  static const _kExitRequired   = 'exit_press_required';
  static const _kMaxViolations  = 'max_violations';
  static const _kMaxHistory     = 'max_scan_history';

  // ─── Defaults (sama dengan AppConfig) ─────────────────────────
  static const _defaults = {
    _kQrExpiry:      120,
    _kExitRequired:  3,
    _kMaxViolations: 3,
    _kMaxHistory:    10,
  };

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        // Fetch interval 12 jam agar tidak kena quota limit
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 12),
      ));
      await _rc.setDefaults(_defaults.map((k, v) => MapEntry(k, v)));
      await _rc.fetchAndActivate();
      _initialized = true;
      print('✅ RemoteConfig: fetched & activated');
    } catch (e) {
      print('⚠️ RemoteConfig: failed ($e), using defaults');
      _initialized = true; // tetap set agar tidak retry terus
    }
  }

  // ─── Getters ──────────────────────────────────────────────────

  /// Berapa menit QR Code valid setelah dibuat
  int get qrExpiryMinutes => _rc.getInt(_kQrExpiry);

  /// Berapa kali tombol "Keluar" harus ditekan untuk konfirmasi
  int get exitPressRequired => _rc.getInt(_kExitRequired);

  /// Maksimal pelanggaran sebelum ujian dibatalkan otomatis
  int get maxViolations => _rc.getInt(_kMaxViolations);

  /// Maksimal riwayat scan yang disimpan
  int get maxScanHistory => _rc.getInt(_kMaxHistory);
}
