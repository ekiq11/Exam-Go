// lib/services/app_remote_config.dart
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Wrapper singleton untuk Firebase Remote Config.
/// Nilai defaultnya sinkron dengan AppConfig agar app tetap berjalan
/// walaupun tidak ada koneksi internet.
class AppRemoteConfig {
  AppRemoteConfig._({FirebaseRemoteConfig? rc}) : _rc = rc ?? FirebaseRemoteConfig.instance;
  static AppRemoteConfig instance = AppRemoteConfig._();

  final FirebaseRemoteConfig _rc;
  bool _initialized = false;

  @visibleForTesting
  static AppRemoteConfig createForTest(FirebaseRemoteConfig rc) => AppRemoteConfig._(rc: rc);

  // ─── Keys ─────────────────────────────────────────────────────
  static const _kQrExpiry       = 'qr_expiry_minutes';
  static const _kExitRequired   = 'exit_press_required';
  static const _kMaxViolations  = 'max_violations';
  static const _kMaxHistory     = 'max_scan_history';
  static const _kMinAppBuild    = 'min_app_build';

  // ─── Defaults (sama dengan AppConfig) ─────────────────────────
  static const _defaults = {
    // FIX AUDIT-5: Samakan dengan AppConfig.qrExpiryMinutes (10080 / 7 hari)
    _kQrExpiry:      10080,
    _kExitRequired:  3,
    _kMaxViolations: 3,
    _kMaxHistory:    10,
    _kMinAppBuild:   35, // Default tidak memaksa update jika belum diset di Firebase
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
      debugPrint('[RemoteConfig] fetched & activated');
    } catch (e) {
      debugPrint('[RemoteConfig] failed ($e), using defaults');
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

  /// Minimal build number yang diizinkan untuk membuka ujian
  int get minAppBuild => _rc.getInt(_kMinAppBuild);
}
