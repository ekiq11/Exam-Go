// lib/analytics_service.dart
// ignore_for_file: avoid_print

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Centralized Firebase Analytics wrapper untuk ExamGO.
/// Semua event tracking dipusatkan di sini agar mudah dikelola.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // ─── Identity ─────────────────────────────────────────────────

  /// Set identitas peserta ke Firebase Analytics & Crashlytics.
  ///
  /// Cara guru melihat data ini:
  ///   - Firebase Console → Analytics → User Properties → student_name / student_nis
  ///   - Firebase Console → Crashlytics → jika ada crash, terlihat NIS peserta
  Future<void> setStudentIdentity({
    required String name,
    required String nis,
  }) async {
    try {
      // Set sebagai Analytics user properties
      await _analytics.setUserProperty(name: 'student_name', value: name);
      await _analytics.setUserProperty(name: 'student_nis',  value: nis);
      // Set sebagai Crashlytics user identifier
      // Format: "NIS - Nama" agar mudah dibaca saat debugging crash
      await FirebaseCrashlytics.instance.setUserIdentifier('$nis - $name');
    } catch (e) {
      print('Analytics setUserIdentity error: $e');
    }
  }

  // ─── App Events ───────────────────────────────────────────────

  /// Dipanggil saat splash screen selesai dan home terbuka
  Future<void> logAppOpen() async {
    try {
      await _analytics.logAppOpen();
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  // ─── QR Scanner Events ────────────────────────────────────────

  /// Saat QR berhasil di-scan
  Future<void> logQRScanned({
    required String method, // 'camera' | 'gallery'
    required bool isEncrypted,
    String? examTitle,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'qr_scanned',
        parameters: {
          'method': method,
          'is_encrypted': isEncrypted ? 'true' : 'false',
          if (examTitle != null && examTitle.isNotEmpty)
            'exam_title': examTitle.substring(
              0,
              examTitle.length > 100 ? 100 : examTitle.length,
            ),
        },
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  /// Saat QR tidak valid / tidak dikenali
  Future<void> logQRInvalid({required String reason}) async {
    try {
      await _analytics.logEvent(
        name: 'qr_invalid',
        parameters: {'reason': reason},
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  // ─── Exam Session Events ──────────────────────────────────────

  /// Saat ujian benar-benar dimulai (user klik "Mulai Ujian")
  Future<void> logExamStarted({
    required String examTitle,
    required String examUrl,
  }) async {
    try {
      final host = Uri.tryParse(examUrl)?.host ?? 'unknown';
      await _analytics.logEvent(
        name: 'exam_started',
        parameters: {
          'exam_title': examTitle.substring(
            0,
            examTitle.length > 100 ? 100 : examTitle.length,
          ),
          'exam_host': host, // Hanya host, bukan full URL (privasi)
        },
      );
      // Set user property untuk segmentasi
      await _analytics.setUserProperty(name: 'last_exam_host', value: host);
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  /// Saat ujian selesai / user berhasil keluar dengan normal
  Future<void> logExamEnded({
    required String examTitle,
    required int durationSeconds,
    required int minimizeCount,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'exam_ended',
        parameters: {
          'exam_title': examTitle.substring(
            0,
            examTitle.length > 100 ? 100 : examTitle.length,
          ),
          'duration_seconds': durationSeconds,
          'minimize_count': minimizeCount,
        },
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  /// Saat user mencoba keluar (tap tombol keluar)
  Future<void> logExitAttempt({
    required int attemptNumber,
    required int minimizeCount,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'exam_exit_attempt',
        parameters: {
          'attempt_number': attemptNumber,
          'minimize_count': minimizeCount,
        },
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  /// Saat user keluar aplikasi / minimize saat ujian berlangsung
  Future<void> logExamViolation({
    required String examTitle,
    required int violationCount,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'exam_violation',
        parameters: {
          'exam_title': examTitle.substring(
            0,
            examTitle.length > 100 ? 100 : examTitle.length,
          ),
          'violation_count': violationCount,
        },
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  /// Saat halaman ujian gagal dimuat (error jaringan / server)
  Future<void> logExamLoadError({
    required String examHost,
    required String errorMessage,
    int? errorCode,
    int? retryCount,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'exam_load_error',
        parameters: {
          'exam_host': examHost,
          // Potong error message — jangan log data sensitif
          'error_short': errorMessage.substring(
            0,
            errorMessage.length > 100 ? 100 : errorMessage.length,
          ),
          // Hanya sertakan field jika tidak null — hindari mengirim null ke Firebase
          // ignore: use_null_aware_elements — Map<String, Object> tidak support ?'key': nullable
          if (errorCode != null) 'error_code': errorCode,
          // ignore: use_null_aware_elements
          if (retryCount != null) 'retry_count': retryCount,
        },
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  // ─── QR Generator Events ──────────────────────────────────────

  /// Saat guru/pengawas membuat QR baru
  Future<void> logQRGenerated({required bool hasTitle}) async {
    try {
      await _analytics.logEvent(
        name: 'qr_generated',
        parameters: {'has_title': hasTitle ? 'true' : 'false'},
      );
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  /// Saat QR di-share / disimpan
  Future<void> logQRShared() async {
    try {
      await _analytics.logEvent(name: 'qr_shared');
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  // ─── Connectivity Events ──────────────────────────────────────

  /// Saat user mencoba scan tapi offline
  Future<void> logOfflineScanAttempt() async {
    try {
      await _analytics.logEvent(name: 'offline_scan_attempt');
    } catch (e) {
      print('Analytics error: $e');
    }
  }

  // ─── Screen Tracking ─────────────────────────────────────────

  Future<void> logScreenView({required String screenName}) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      print('Analytics error: $e');
    }
  }
}
