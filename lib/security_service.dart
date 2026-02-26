// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';

/// Cross-platform security wrapper.
///
/// Android : immersiveSticky + optional native lock-task (Device Admin).
/// iOS     : immersive + orientation lock. Guided Access must be enabled by
///           the supervisor via iOS Settings → Accessibility.
/// Web     : graceful no-op.
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const _channel = MethodChannel('com.examgo/locktask');

  bool _lockActive = false;
  bool _disposed = false;

  bool get isLockActive => _lockActive;

  /// Enable security / kiosk mode.
  Future<void> enable() async {
    if (_disposed || kIsWeb) return;
    try {
      await _applyImmersiveMode();
      await _lockOrientation();
      await _tryNativeLock();
      _lockActive = true;
      print('✅ SecurityService: enabled');
    } catch (e) {
      print('⚠️ SecurityService.enable: $e');
    }
  }

  /// Disable and restore system UI.
  Future<void> disable() async {
    if (_disposed || kIsWeb) return;
    try {
      await _tryNativeUnlock();
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
      await SystemChrome.setPreferredOrientations([]);
      _lockActive = false;
      print('✅ SecurityService: disabled');
    } catch (e) {
      print('⚠️ SecurityService.disable: $e');
    }
  }

  /// Re-applies immersive mode — call on [AppLifecycleState.resumed].
  Future<void> reapply() async {
    if (_disposed || !_lockActive || kIsWeb) return;
    try {
      await _applyImmersiveMode();
    } catch (_) {}
  }

  void dispose() => _disposed = true;

  // ── internals ────────────────────────────────────────────────

  Future<void> _applyImmersiveMode() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }

  Future<void> _lockOrientation() =>
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  Future<void> _tryNativeLock() async {
    try {
      await _channel
          .invokeMethod('startLockTask')
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Graceful — not available on iOS or without Device Admin
    }
  }

  Future<void> _tryNativeUnlock() async {
    try {
      await _channel
          .invokeMethod('stopLockTask')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
