// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';

/// Cross-platform security wrapper — compatible with all Android vendors.
///
/// Perbaikan untuk:
/// - Samsung OneUI (A-series, S-series)
/// - Xiaomi MIUI / HyperOS
/// - Oppo ColorOS / Realme UI
/// - Vivo FuntouchOS
/// - Android Go (low-end)
/// - x86 / x86_64 emulator & tablet
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const _channel = MethodChannel('com.examgo/locktask');
  static const _kTimeoutMs = 2000; // Lebih pendek agar tidak hang

  bool _lockActive = false;
  bool _nativeLockActive = false; // Pisah tracking native vs flutter lock

  bool get isLockActive => _lockActive;

  // ─── Enable ──────────────────────────────────────────────────

  Future<void> enable() async {
    if (kIsWeb) return;
    try {
      // Urutan: orientation → immersive → native (best-effort)
      await _lockOrientation();
      await _applyImmersiveMode();
      await _tryNativeLock(); // Tidak blocking jika gagal
      _lockActive = true;
      print('✅ SecurityService: enabled (nativeLock=$_nativeLockActive)');
    } catch (e) {
      // Tetap set _lockActive supaya UI security tetap jalan
      _lockActive = true;
      print('⚠️ SecurityService.enable error (partially active): $e');
    }
  }

  // ─── Disable ─────────────────────────────────────────────────

  /// [force] = true → paksa unlock meski state tidak sinkron (pakai di exit dialog)
  Future<void> disable({bool force = false}) async {
    if (kIsWeb) {
      _lockActive = false;
      return;
    }

    // Set flag lebih awal supaya PopScope tidak block navigation
    _lockActive = false;

    try {
      // 1. Lepas native lock dulu
      if (_nativeLockActive || force) {
        await _tryNativeUnlock();
      }

      // 2. Restore sistem UI — pakai multiple fallback
      await _restoreSystemUI();

      // 3. Kembalikan orientasi
      await _restoreOrientation();

      print('✅ SecurityService: disabled');
    } catch (e) {
      print('⚠️ SecurityService.disable error: $e');
      // Paksa restore walaupun error
      await _forceRestoreUI();
    }
  }

  // ─── Reapply ─────────────────────────────────────────────────

  Future<void> reapply() async {
    if (!_lockActive || kIsWeb) return;
    try {
      await _applyImmersiveMode();
    } catch (_) {}
  }

  // ─── Emergency Reset ─────────────────────────────────────────
  /// Panggil ini jika aplikasi stuck — tidak peduli state apapun.

  Future<void> emergencyReset() async {
    _lockActive = false;
    _nativeLockActive = false;
    await _forceRestoreUI();
    print('🚨 SecurityService: emergencyReset called');
  }

  // ─── Privates ────────────────────────────────────────────────

  Future<void> _applyImmersiveMode() async {
    // immersiveSticky paling kompatibel untuk exam mode
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  Future<void> _lockOrientation() =>
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  Future<void> _restoreOrientation() => SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  Future<void> _restoreSystemUI() async {
    // Step 1: edgeToEdge dengan semua overlay
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

    // Step 2: tunggu frame render
    await Future.delayed(const Duration(milliseconds: 150));

    // Step 3: Set ulang overlay style ke light (normal)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    // Step 4: Delay lagi untuk vendor-specific rendering
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Last resort — pakai manual channel jika method biasa gagal
  Future<void> _forceRestoreUI() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } catch (_) {}
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    } catch (_) {}
    try {
      await SystemChrome.setPreferredOrientations([]);
    } catch (_) {}
    // Vendor-specific unlock
    try {
      await _channel
          .invokeMethod('stopLockTask')
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {}
  }

  Future<void> _tryNativeLock() async {
    try {
      final result = await _channel
          .invokeMethod('startLockTask')
          .timeout(Duration(milliseconds: _kTimeoutMs));
      _nativeLockActive = result == true || result == null;
    } catch (e) {
      _nativeLockActive = false;
      // Bukan error fatal — Samsung/Xiaomi sering tidak support tanpa Device Admin
      print('ℹ️ Native lock not available (expected on most devices): $e');
    }
  }

  Future<void> _tryNativeUnlock() async {
    try {
      await _channel
          .invokeMethod('stopLockTask')
          .timeout(Duration(milliseconds: _kTimeoutMs));
      _nativeLockActive = false;
    } catch (e) {
      _nativeLockActive = false;
      print('ℹ️ Native unlock skipped: $e');
    }
  }
}
