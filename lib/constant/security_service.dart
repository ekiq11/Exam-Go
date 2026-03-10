// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';

/// Cross-platform security wrapper — Android & iOS, semua vendor.
///
/// Android: Lock Task (kiosk) + Immersive mode
/// iOS    : immersiveSticky (sembunyikan status/home bar)
///          Lock Task tidak tersedia — gunakan Guided Access secara manual
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const _channel = MethodChannel('com.examgo/locktask');
  static const _kTimeoutMs = 2000;

  bool _lockActive = false;
  bool _nativeLockActive = false;

  bool get isLockActive => _lockActive;

  static bool get _isIOS => !kIsWeb && Platform.isIOS;
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // ─── Enable ───────────────────────────────────────────────────

  Future<void> enable() async {
    if (kIsWeb) return;
    try {
      await _lockOrientation();
      if (_isAndroid) {
        await _applyImmersiveMode();
        await _tryNativeLock();
      } else if (_isIOS) {
        await _applyIOSFullScreen();
      }
      _lockActive = true;
      print(
        '✅ SecurityService: enabled (${_isIOS ? "iOS" : "Android"}, native=$_nativeLockActive)',
      );
    } catch (e) {
      _lockActive = true;
      print('⚠️ SecurityService.enable partially active: $e');
    }
  }

  // ─── Disable ──────────────────────────────────────────────────

  Future<void> disable({bool force = false}) async {
    if (kIsWeb) {
      _lockActive = false;
      return;
    }
    _lockActive = false;
    try {
      if (_isAndroid) {
        // FIX: "PigeonProxyApiRegistrar: Failed to remove Dart strong reference"
        // Error ini terjadi saat WebView masih punya pending native callback
        // ketika di-dispose. Beri waktu native layer selesai sebelum unlock.
        // Delay 200ms cukup untuk flush pending PigeonProxyApi operations.
        await Future.delayed(const Duration(milliseconds: 200));
        if (_nativeLockActive || force) await _tryNativeUnlock();
        await _restoreAndroidUI();
      } else if (_isIOS) {
        await _restoreIOSUI();
      }
      await _restoreOrientation();
      print('✅ SecurityService: disabled');
    } catch (e) {
      print('⚠️ SecurityService.disable error: $e');
      await _forceRestoreUI();
    }
  }

  // ─── Reapply (setiap 3 detik saat ujian) ──────────────────────

  Future<void> reapply() async {
    if (!_lockActive || kIsWeb) return;
    try {
      if (_isAndroid) {
        await _applyImmersiveMode();
      } else if (_isIOS) {
        await _applyIOSFullScreen();
      }
    } catch (_) {}
  }

  // ─── Emergency Reset ──────────────────────────────────────────

  Future<void> emergencyReset() async {
    _lockActive = false;
    _nativeLockActive = false;
    await _forceRestoreUI();
    print('🚨 SecurityService: emergencyReset');
  }

  // ─── iOS ──────────────────────────────────────────────────────

  Future<void> _applyIOSFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  Future<void> _restoreIOSUI() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    await Future.delayed(const Duration(milliseconds: 150));
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  // ─── Android ──────────────────────────────────────────────────

  Future<void> _applyImmersiveMode() async {
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

  Future<void> _restoreAndroidUI() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    await Future.delayed(const Duration(milliseconds: 150));
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 100));
  }

  // ─── Shared ───────────────────────────────────────────────────

  Future<void> _lockOrientation() =>
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  Future<void> _restoreOrientation() => SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  Future<void> _forceRestoreUI() async {
    for (final mode in [SystemUiMode.manual, SystemUiMode.edgeToEdge]) {
      try {
        await SystemChrome.setEnabledSystemUIMode(
          mode,
          overlays: SystemUiOverlay.values,
        );
      } catch (_) {}
    }
    try {
      await SystemChrome.setPreferredOrientations([]);
    } catch (_) {}
    if (_isAndroid) {
      try {
        await _channel
            .invokeMethod('stopLockTask')
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }

  Future<void> _tryNativeLock() async {
    try {
      final r = await _channel
          .invokeMethod('startLockTask')
          .timeout(Duration(milliseconds: _kTimeoutMs));
      _nativeLockActive = r == true || r == null;
    } catch (e) {
      _nativeLockActive = false;
      print('ℹ️ Native lock not available (normal on most devices): $e');
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
