import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:app_usage/app_usage.dart';
import 'dart:async';

class SecurityManager {
  static const platform = MethodChannel('com.examgo/security');
  
  static final SecurityManager _instance = SecurityManager._internal();
  factory SecurityManager() => _instance;
  SecurityManager._internal();

  bool _isSecureModeActive = false;
  bool _isKioskModeActive = false;
  bool _deviceAdminActive = false;
  final AppUsage _appUsage = AppUsage();
  
  /// PENTING: Cek dan aktifkan Device Admin terlebih dahulu sebelum ujian
  Future<bool> checkAndEnableDeviceAdmin() async {
    if (!Platform.isAndroid) return true;

    try {
      final isActive = await checkDeviceAdminPermission();
      if (!isActive) {
        print('⚠️ Device Admin tidak aktif - membuka pengaturan...');
        await openDeviceAdminSettings();
        return false;
      }
      _deviceAdminActive = true;
      print('✅ Device Admin SUDAH aktif');
      return true;
    } catch (e) {
      print('❌ Error checking device admin: $e');
      return false;
    }
  }
  
  /// Aktifkan mode keamanan PENUH dengan Kiosk Mode + SystemChrome
  Future<bool> enableSecureMode() async {
    if (!Platform.isAndroid) return true;

    try {
      // 1. SEMBUNYIKAN BILAH NAVIGASI DENGAN SYSTEMCHROME
      await _hideSystemUI();
      
      // 2. Cek Device Admin
      final hasAdmin = await checkDeviceAdminPermission();
      if (!hasAdmin) {
        print('⚠️ Device Admin belum aktif - SystemChrome aktif, tapi kiosk mode tidak');
        // Tetap lanjutkan dengan SystemChrome saja
      } else {
        // 3. Aktifkan Kiosk Mode Native (DISABLE penuh semua navigasi)
        final kioskSuccess = await enableKioskMode();
        if (!kioskSuccess) {
          print('⚠️ Kiosk mode gagal, tapi SystemChrome tetap aktif');
        }
      }

      // 4. Blokir screenshot
      await preventScreenshot(true);
      
      _isSecureModeActive = true;
      print('✅ SECURE MODE AKTIF - Navigasi sistem HIDDEN/DISABLED');
      return true;
    } catch (e) {
      print('❌ Error enabling secure mode: $e');
      return false;
    }
  }
  
  /// Sembunyikan System UI menggunakan SystemChrome
  Future<void> _hideSystemUI() async {
    try {
      // Mode immersive sticky - bilah navigasi sembunyi otomatis
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [], // Kosongkan = sembunyikan semua
      );
      
      print('✅ SystemChrome - Bilah navigasi & status bar HIDDEN');
      print('   • Status bar: HIDDEN ❌');
      print('   • Navigation bar: HIDDEN ❌');
      print('   • Immersive sticky mode: ACTIVE ✓');
    } catch (e) {
      print('❌ Error hiding system UI: $e');
    }
  }
  
  /// Tampilkan kembali System UI
  Future<void> _showSystemUI() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values, // Tampilkan semua
      );
      
      print('✅ SystemChrome - Bilah navigasi & status bar NORMAL');
    } catch (e) {
      print('❌ Error showing system UI: $e');
    }
  }
  
  /// Nonaktifkan mode keamanan
  Future<void> disableSecureMode() async {
    try {
      // 1. Tampilkan kembali System UI
      await _showSystemUI();
      
      // 2. Nonaktifkan screenshot block
      await preventScreenshot(false);
      
      // 3. Nonaktifkan Kiosk Mode
      await disableKioskMode();
      
      _isSecureModeActive = false;
      _isKioskModeActive = false;
      print('✅ Secure mode DEACTIVATED - UI kembali normal');
    } catch (e) {
      print('❌ Error disabling secure mode: $e');
    }
  }
  
  /// Aktifkan Kiosk Mode Native - DISABLE HOME, BACK, RECENT BUTTONS
  Future<bool> enableKioskMode() async {
    if (!Platform.isAndroid) return true;

    try {
      print('🔒 Mengaktifkan Kiosk Mode Native...');
      final result = await platform.invokeMethod<bool>('enableKioskMode');
      _isKioskModeActive = result ?? false;
      
      if (_isKioskModeActive) {
        print('✅ KIOSK MODE AKTIF (Native) - Tombol navigasi DISABLED');
        print('   • Home button: DISABLED ❌');
        print('   • Back button: DISABLED ❌');
        print('   • Recent apps: DISABLED ❌');
      } else {
        print('⚠️ Kiosk mode gagal - Pastikan Device Admin aktif');
      }
      
      return _isKioskModeActive;
    } catch (e) {
      print('❌ Error enabling kiosk mode: $e');
      return false;
    }
  }
  
  /// Nonaktifkan Kiosk Mode
  Future<void> disableKioskMode() async {
    if (!Platform.isAndroid) return;

    try {
      await platform.invokeMethod('disableKioskMode');
      _isKioskModeActive = false;
      print('✅ Kiosk mode DISABLED - Navigasi normal kembali');
    } catch (e) {
      print('❌ Error disabling kiosk mode: $e');
    }
  }
  
  /// Re-hide System UI jika user swipe dari edge
  Future<void> reapplySystemUIHiding() async {
    if (_isSecureModeActive) {
      await _hideSystemUI();
    }
  }
  
  /// Cek apakah Device Admin sudah aktif
  Future<bool> checkDeviceAdminPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await platform.invokeMethod<bool>('isDeviceAdmin');
      final isActive = result ?? false;
      
      if (isActive) {
        print('✅ Device Admin AKTIF');
      } else {
        print('❌ Device Admin BELUM AKTIF');
      }
      
      return isActive;
    } catch (e) {
      print('❌ Error checking device admin: $e');
      return false;
    }
  }
  
  /// Buka pengaturan Device Admin
  Future<void> openDeviceAdminSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('openDeviceAdminSettings');
      print('📱 Membuka pengaturan Device Admin...');
    } catch (e) {
      print('❌ Failed to open device admin settings: $e');
    }
  }
  
  /// Blokir screenshot
  Future<void> preventScreenshot(bool prevent) async {
    try {
      if (Platform.isAndroid) {
        await platform.invokeMethod('setPreventScreenshot', {'prevent': prevent});
        print('${prevent ? '🔒' : '🔓'} Screenshot ${prevent ? 'BLOCKED' : 'ALLOWED'}');
      }
    } catch (e) {
      print('⚠️ Error preventing screenshot: $e');
    }
  }
  
  /// Cek izin App Usage Stats
  Future<bool> checkAppUsagePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await platform.invokeMethod<bool>('checkAppUsagePermission');
      return result ?? false;
    } catch (e) {
      print('❌ Error checking usage permission: $e');
      return false;
    }
  }

  /// Buka pengaturan App Usage Stats
  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await platform.invokeMethod('openUsageAccessSettings');
      print('📱 Membuka pengaturan App Usage...');
    } catch (e) {
      print('❌ Failed to open usage access settings: $e');
    }
  }
  
  /// Dapatkan list aplikasi yang sedang berjalan
  Future<List<String>> getRunningApps() async {
    if (!Platform.isAndroid) return [];

    try {
      DateTime endDate = DateTime.now();
      DateTime startDate = endDate.subtract(const Duration(seconds: 3));
      
      List<AppUsageInfo> appUsageStats = 
          await _appUsage.getAppUsage(startDate, endDate);
      
      return appUsageStats
          .where((usage) => usage.packageName.isNotEmpty)
          .map((usage) => usage.packageName)
          .toList();
    } catch (e) {
      return [];
    }
  }
  
  /// Cek aplikasi terblokir
  Future<String?> checkBlockedApps() async {
    if (!Platform.isAndroid || !_isSecureModeActive) return null;

    try {
      final blockedApps = _getBlockedAppsList();
      final runningApps = await getRunningApps();
      
      for (var packageName in runningApps) {
        if (blockedApps.containsKey(packageName)) {
          return blockedApps[packageName];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// List aplikasi yang diblokir
  Map<String, String> _getBlockedAppsList() {
    return {
      'com.whatsapp': 'WhatsApp',
      'com.whatsapp.w4b': 'WhatsApp Business',
      'com.facebook.katana': 'Facebook',
      'com.facebook.orca': 'Messenger',
      'com.instagram.android': 'Instagram',
      'com.snapchat.android': 'Snapchat',
      'com.twitter.android': 'Twitter (X)',
      'com.telegram.messenger': 'Telegram',
      'org.telegram.messenger': 'Telegram',
      'com.discord': 'Discord',
      'com.android.chrome': 'Chrome',
      'com.opera.browser': 'Opera',
      'org.mozilla.firefox': 'Firefox',
      'com.google.android.youtube': 'YouTube',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.ss.android.ugc.trill': 'TikTok',
      'com.android.vending': 'Play Store',
      'com.google.android.gm': 'Gmail',
    };
  }
  
  // Getters
  bool get isSecureModeActive => _isSecureModeActive;
  bool get isKioskModeActive => _isKioskModeActive;
  bool get isDeviceAdminActive => _deviceAdminActive;
}