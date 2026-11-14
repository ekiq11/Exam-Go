import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'popup_ad_service.dart';
import 'student_tryout_history_service.dart';

/// Hasil validasi dan aktivasi kode lisensi
class ActivationResult {
  final bool isSuccess;
  final String message;
  final String? targetExamId;

  const ActivationResult({
    required this.isSuccess,
    required this.message,
    this.targetExamId,
  });

  factory ActivationResult.success([String message = 'Aktivasi lisensi berhasil!', String? targetExamId]) =>
      ActivationResult(isSuccess: true, message: message, targetExamId: targetExamId);

  factory ActivationResult.failure(String message) =>
      ActivationResult(isSuccess: false, message: _sanitizeErrorMessage(message));

  static String _sanitizeErrorMessage(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('firebase') ||
        lower.contains('firestore') ||
        lower.contains('http') ||
        lower.contains('exception') ||
        lower.contains('denied') ||
        lower.contains('unauthorized') ||
        lower.contains('status code') ||
        lower.contains('error:') ||
        lower.contains('stack trace') ||
        lower.contains('socketexception') ||
        lower.contains('handshake') ||
        lower.contains('timeout')) {
      return 'Kode lisensi tidak valid, tidak terdaftar, atau koneksi terputus. Silakan periksa kembali kode lisensi Anda atau hubungi Admin ExamGO.';
    }
    return msg;
  }
}

/// Service manajemen lisensi & kuota freemium ExamGO
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const int maxFreeAttempts = 5;
  static const int maxFreeTeacherUploads = 3;

  // Local Storage Keys
  static const String _kStudentPremiumKey = 'license_student_is_premium';
  static const String _kStudentAttemptsKey = 'license_student_exam_count';
  static const String _kTeacherPremiumKey = 'license_teacher_is_premium';
  static const String _kTeacherUploadsKey = 'license_teacher_upload_count';
  static const String _kTeacherLicenseTokenKey = 'teacher_license_token';

  FirebaseFirestore? _firestore;

  FirebaseFirestore? get _db {
    if (_firestore != null) return _firestore;
    try {
      _firestore = FirebaseFirestore.instance;
      return _firestore;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void setMockFirestore(FirebaseFirestore? mock) {
    _firestore = mock;
  }

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _cachedDeviceId;

  /// Mendapatkan Device ID unik perangkat (hardware-based)
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    try {
      if (kIsWeb) {
        _cachedDeviceId = 'web_device';
      } else if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        _cachedDeviceId = info.id.isNotEmpty ? info.id : 'android_unknown';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        _cachedDeviceId = info.identifierForVendor ?? 'ios_unknown';
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        _cachedDeviceId = info.deviceId.isNotEmpty ? info.deviceId : 'windows_unknown';
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        _cachedDeviceId = info.systemGUID ?? 'macos_unknown';
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        _cachedDeviceId = info.machineId ?? 'linux_unknown';
      } else {
        _cachedDeviceId = 'generic_device';
      }
    } catch (_) {
      _cachedDeviceId = 'fallback_device';
    }
    return _cachedDeviceId!;
  }

  /// Mengecek apakah perangkat saat ini bertipe Laptop/Desktop atau Mobile (Android/iOS)
  bool isLaptopOrDesktopDevice() {
    if (kIsWeb) return true;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return true;
    } catch (_) {}
    return false;
  }

  // ─── SISI SISWA (Freemium 5x & Lifetime) ─────────────────────────

  /// Cek apakah siswa berstatus Premium Lifetime
  Future<bool> isStudentPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final localPremium = prefs.getBool(_kStudentPremiumKey) ?? false;
    if (localPremium) return true;

    final db = _db;
    if (db == null) return false;

    // Verifikasi sekunder dengan server Firestore (mencegah manipulasi)
    try {
      final deviceId = await getDeviceId();
      final doc = await db.collection('devices').doc(deviceId).get();
      if (doc.exists && (doc.data()?['is_student_premium'] == true)) {
        await prefs.setBool(_kStudentPremiumKey, true);
        final lastToken = doc.data()?['last_token_activated']?.toString();
        if (lastToken != null && lastToken.isNotEmpty) {
          await prefs.setString('last_token_activated', lastToken);
        }
        // Pulihkan otomatis riwayat & jawaban soal siswa jika di lokal kosong
        StudentTryoutHistoryService.instance.restoreHistoryFromCloud(licenseToken: lastToken);
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Sisa kuota ujian gratis siswa (selalu unlimited untuk pengerjaan ujian dasar)
  Future<int> getRemainingStudentAttempts() async {
    return 9999;
  }

  /// Cek apakah siswa diizinkan memulai ujian baru (selalu diizinkan untuk ujian gratis)
  Future<bool> canStudentTakeExam() async {
    return true;
  }

  /// Catat penggunaan ujian (dipanggil saat siswa mulai ujian, untuk analitik/statistik)
  Future<void> recordExamAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_kStudentAttemptsKey) ?? 0;
    final next = current + 1;
    await prefs.setInt(_kStudentAttemptsKey, next);

    final db = _db;
    if (db != null) {
      try {
        final deviceId = await getDeviceId();
        await db.collection('devices').doc(deviceId).set({
          'exam_count': FieldValue.increment(1),
          'last_attempt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  // ─── SISI GURU (Teacher Premium Creator) ──────────────────────────

  /// Cek apakah guru berstatus Premium Creator
  Future<bool> isTeacherPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final localPremium = prefs.getBool(_kTeacherPremiumKey) ?? false;
    if (localPremium) return true;

    final db = _db;
    if (db != null) {
      // Verifikasi sekunder dengan server Firestore
      try {
        final deviceId = await getDeviceId();
        final doc = await db.collection('devices').doc(deviceId).get();
        if (doc.exists && (doc.data()?['is_teacher_premium'] == true)) {
          await prefs.setBool(_kTeacherPremiumKey, true);
          final lastToken = doc.data()?['last_token_activated'] as String?;
          if (lastToken != null && lastToken.isNotEmpty) {
            await prefs.setString(_kTeacherLicenseTokenKey, lastToken.trim().toUpperCase());
          }
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Mengambil token lisensi guru yang sedang aktif di perangkat ini
  Future<String?> getTeacherLicenseToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(_kTeacherLicenseTokenKey);
    if (token != null && token.isNotEmpty) return token;

    final db = _db;
    if (db != null) {
      try {
        final deviceId = await getDeviceId();
        final doc = await db.collection('devices').doc(deviceId).get();
        final devToken = doc.data()?['last_token_activated'] as String?;
        if (devToken != null && devToken.isNotEmpty) {
          token = devToken.trim().toUpperCase();
          await prefs.setString(_kTeacherLicenseTokenKey, token);
          return token;
        }

        final snap = await db
            .collection('license_tokens')
            .where('mobile_device_id', isEqualTo: deviceId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          token = snap.docs.first.id.trim().toUpperCase();
          await prefs.setString(_kTeacherLicenseTokenKey, token);
          return token;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Sisa kuota coba gratis buat & upload soal untuk guru (maksimal 3x)
  Future<int> getRemainingTeacherUploads() async {
    if (await isTeacherPremium()) return 9999; // Unlimited
    final prefs = await SharedPreferences.getInstance();
    int localCount = prefs.getInt(_kTeacherUploadsKey) ?? 0;

    // Perhitungkan juga riwayat lokal jika ada
    final historyList = prefs.getStringList('teacher_exam_history') ?? [];
    if (historyList.length > localCount) {
      localCount = historyList.length;
      await prefs.setInt(_kTeacherUploadsKey, localCount);
    }

    final db = _db;
    if (db != null) {
      try {
        final deviceId = await getDeviceId();
        final doc = await db.collection('devices').doc(deviceId).get();
        if (doc.exists) {
          final serverCount = (doc.data()?['teacher_upload_count'] as num?)?.toInt() ?? 0;
          if (serverCount > localCount) {
            localCount = serverCount;
            await prefs.setInt(_kTeacherUploadsKey, localCount);
          } else if (localCount > serverCount) {
            // Sinkronkan ke cloud agar Firestore selalu menyimpan count terbesar
            await db.collection('devices').doc(deviceId).set({
              'teacher_upload_count': localCount,
              'last_teacher_upload': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } else if (localCount > 0) {
          await db.collection('devices').doc(deviceId).set({
            'teacher_upload_count': localCount,
            'last_teacher_upload': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }

    return (maxFreeTeacherUploads - localCount).clamp(0, maxFreeTeacherUploads);
  }

  /// Cek apakah guru diizinkan mengakses fitur Buat & Upload Soal (Premium atau sisa coba > 0)
  Future<bool> canTeacherUploadExam() async {
    if (await isTeacherPremium()) return true;
    final remaining = await getRemainingTeacherUploads();
    return remaining > 0;
  }

  /// Catat penggunaan 1 kuota coba upload soal guru (dipanggil saat menerbitkan paket soal)
  Future<void> recordTeacherUploadAttempt() async {
    if (await isTeacherPremium()) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_kTeacherUploadsKey) ?? 0;
    final next = current + 1;
    await prefs.setInt(_kTeacherUploadsKey, next);

    final db = _db;
    if (db != null) {
      try {
        final deviceId = await getDeviceId();
        await db.collection('devices').doc(deviceId).set({
          'teacher_upload_count': FieldValue.increment(1),
          'last_teacher_upload': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  // ─── SISI EVENT TRYOUT (Lynk.id Tiket Event) ─────────────────────

  /// Siswa yang memegang token event berhak mengikuti ujian event tanpa terpotong kuota freemium 5x
  Future<bool> canStudentTakeEventExam(String eventOrPackageId) async => true;

  /// Cek token event aktif yang tersimpan di perangkat ini
  Future<String?> getActiveEventToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_event_token');
  }

  /// Cek ID paket event aktif yang tersimpan
  Future<String?> getActiveEventId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_event_id');
  }

  /// Simpan event aktif ke penyimpanan lokal
  Future<void> saveActiveEvent({required String token, required String eventId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_event_token', token);
    await prefs.setString('active_event_id', eventId);
  }

  // ─── AKTIVASI KODE TOKEN (Lynk.id) ────────────────────────────────

  /// Validasi dan aktivasi kode token dari email pembeli Lynk.id
  /// [expectedType]: 'TEACHER_PREMIUM' atau 'STUDENT_LIFETIME'
  Future<ActivationResult> activateToken({
    required String rawToken,
    required String expectedType,
    String? userEmail,
    String? userName,
    String? userWhatsapp,
  }) async {
    var token = rawToken.trim().toUpperCase().replaceAll(' ', '');
    if (token.isEmpty) {
      return ActivationResult.failure('Silakan masukkan kode lisensi.');
    }

    final db = _db;
    if (db == null) {
      return ActivationResult.failure('Koneksi database tidak tersedia.');
    }

    try {
      var docRef = db.collection('license_tokens').doc(token);
      var doc = await docRef.get();

      // Fallback 0: Cek format bersih tanpa strip (untuk Master Voucher sekolah seperti MAN1MATARAM)
      if (!doc.exists) {
        final clean = token.replaceAll('-', '');
        final altRef = db.collection('license_tokens').doc(clean);
        final altDoc = await altRef.get();
        if (altDoc.exists) {
          docRef = altRef;
          doc = altDoc;
          token = clean;
        }
      }

      // Fallback 1: Jika user hanya memasukkan kode tanpa prefix (misal: XXXX-YYYY)
      if (!doc.exists) {
        final prefix = expectedType == 'TEACHER_PREMIUM' ? 'GURU' : 'SISWA';
        if (!token.startsWith('$prefix-')) {
          final altRef = db.collection('license_tokens').doc('$prefix-$token');
          final altDoc = await altRef.get();
          if (altDoc.exists) {
            docRef = altRef;
            doc = altDoc;
            token = '$prefix-$token';
          }
        }
      }

      // Fallback 2: Normalisasi jika tanda hubung hilang atau salah posisi
      if (!doc.exists) {
        final clean = token.replaceAll('-', '');
        String? candidate;
        if (clean.startsWith('SISWA') && clean.length == 13) {
          candidate = 'SISWA-${clean.substring(5, 9)}-${clean.substring(9, 13)}';
        } else if (clean.startsWith('GURU') && clean.length == 12) {
          candidate = 'GURU-${clean.substring(4, 8)}-${clean.substring(8, 12)}';
        } else if (clean.length == 8) {
          final prefix = expectedType == 'TEACHER_PREMIUM' ? 'GURU' : 'SISWA';
          candidate = '$prefix-${clean.substring(0, 4)}-${clean.substring(4, 8)}';
        }

        if (candidate != null && candidate != token) {
          final altRef = db.collection('license_tokens').doc(candidate);
          final altDoc = await altRef.get();
          if (altDoc.exists) {
            docRef = altRef;
            doc = altDoc;
            token = candidate;
          }
        }
      }

      if (!doc.exists) {
        return ActivationResult.failure(
          'Kode lisensi tidak valid atau tidak terdaftar. Periksa kembali kode dari email Anda.',
        );
      }

      final data = doc.data()!;
      final tokenType = data['type']?.toString().toUpperCase() ?? '';
      final isUsed = data['is_used'] == true;
      final usedByDevice = data['device_id']?.toString();

      final currentDeviceId = await getDeviceId();

      // ── LOGIKA KHUSUS: TOKEN EVENT / TRYOUT BERBAYAR (Lynk.id) ──
      final isEventToken = tokenType == 'EVENT' || token.startsWith('EVENT-');
      if (isEventToken) {
        final targetExam = data['target_exam_id']?.toString() ??
            data['target_package_id']?.toString() ??
            data['school']?.toString();

        if (isUsed && usedByDevice != currentDeviceId) {
          return ActivationResult.failure(
            'Kode tiket event ini sudah pernah digunakan pada perangkat lain. Setiap kode hanya berlaku untuk 1 perangkat.',
          );
        }

        if (!isUsed) {
          final now = FieldValue.serverTimestamp();
          await docRef.update({
            'is_used': true,
            'device_id': currentDeviceId,
            'user_name': userName ?? 'Peserta Event',
            'used_by_email': userEmail ?? 'event_buyer',
            'user_whatsapp': userWhatsapp ?? '-',
            'activated_at': now,
          });

          // Catat ke premium_activations untuk monitoring admin
          await db.collection('premium_activations').doc(token).set({
            'token': token,
            'type': 'EVENT',
            'user_name': userName ?? 'Peserta Event',
            'user_email': userEmail ?? '-',
            'user_whatsapp': userWhatsapp ?? '-',
            'device_id': currentDeviceId,
            'target_exam_id': targetExam ?? '-',
            'activated_at': now,
          }, SetOptions(merge: true));
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_event_token', token);
        if (targetExam != null && targetExam.isNotEmpty) {
          await prefs.setString('active_event_id', targetExam);
        }
        if (userName != null && userName.isNotEmpty) {
          await prefs.setString('student_name', userName);
        }
        if (userEmail != null && userEmail.isNotEmpty) {
          await prefs.setString('student_email', userEmail);
        }
        if (userWhatsapp != null && userWhatsapp.isNotEmpty) {
          await prefs.setString('student_whatsapp', userWhatsapp);
        }

        return ActivationResult.success(
          'Tiket Event berhasil diaktifkan! Mengarahkan ke Dashboard Event...',
          targetExam,
        );
      }

      // Cek apakah kode cocok dengan tipe pengguna
      if (tokenType != expectedType.toUpperCase()) {
        final peruntukan = expectedType == 'TEACHER_PREMIUM' ? 'Guru' : 'Siswa';
        return ActivationResult.failure('Kode ini bukan lisensi untuk $peruntukan.');
      }

      final deviceField = expectedType == 'TEACHER_PREMIUM'
          ? 'is_teacher_premium'
          : 'is_student_premium';

      // ── LOGIKA KHUSUS: MASTER VOUCHER SEKOLAH (1 KODE UNTUK RIBUAN SISWA) ──
      final isGroupVoucher = data['is_group_voucher'] == true ||
          (data['max_activations'] != null && (data['max_activations'] as num) > 1);

      if (isGroupVoucher) {
        final schoolName = data['school']?.toString() ?? 'Sekolah Mitra';
        final maxQuota = (data['max_activations'] as num?)?.toInt() ?? 1000;
        final currentActivations = (data['current_activations'] as num?)?.toInt() ?? 0;

        // 1. Cek apakah HP ini sudah pernah mengaktifkan voucher ini sebelumnya
        final devDoc = await db.collection('devices').doc(currentDeviceId).get();
        final devData = devDoc.data();
        final isAlreadyActiveOnDevice = devData != null &&
            devData[deviceField] == true &&
            devData['last_token_activated'] == token;

        if (isAlreadyActiveOnDevice) {
          await _applyActivationLocally(expectedType);
          return ActivationResult.success(
            'Perangkat ini sudah aktif menggunakan lisensi $schoolName.',
            data['target_exam_id']?.toString(),
          );
        }

        // 2. Cek kuota aktivasi sekolah
        if (currentActivations >= maxQuota) {
          return ActivationResult.failure(
            'Kuota aktivasi lisensi untuk $schoolName ($maxQuota perangkat) sudah penuh.',
          );
        }

        // 3. Catat perangkat ke subkoleksi activated_devices dan tambah counter secara atomic
        final now = FieldValue.serverTimestamp();
        await docRef.collection('activated_devices').doc(currentDeviceId).set({
          'device_id': currentDeviceId,
          'activated_at': now,
          'user_email': userEmail ?? 'siswa_$schoolName',
        });

        await docRef.update({
          'current_activations': FieldValue.increment(1),
          'last_activated_at': now,
        });

        // 4. Update status perangkat di Firestore & SharedPreferences lokal
        await db.collection('devices').doc(currentDeviceId).set({
          deviceField: true,
          'school': schoolName,
          'last_token_activated': token,
          'activated_at': now,
        }, SetOptions(merge: true));

        await _applyActivationLocally(expectedType);

        final targetExam = data['target_exam_id']?.toString() ??
            data['target_package_id']?.toString();
        final roleLabel = expectedType == 'TEACHER_PREMIUM' ? 'Guru Premium' : 'Siswa Lifetime';
        return ActivationResult.success(
          'Selamat! Akun $roleLabel $schoolName aktif permanen.',
          targetExam,
        );
      }

      // ── ATURAN MULTI-PERANGKAT: 1 TOKEN = 1 HP (Android/iOS) + 1 LAPTOP ──
      final isLaptop = isLaptopOrDesktopDevice();
      final mobileDeviceId = data['mobile_device_id']?.toString() ??
          (!isLaptop && data['device_id'] != null ? data['device_id']?.toString() : null);
      final laptopDeviceId = data['laptop_device_id']?.toString() ??
          (isLaptop && data['device_id'] != null ? data['device_id']?.toString() : null);

      if (isLaptop) {
        // Cek jika laptop ini sudah pernah aktif sebelumnya
        if (laptopDeviceId == currentDeviceId || data['device_id'] == currentDeviceId) {
          await _applyActivationLocally(expectedType);
          return ActivationResult.success('Lisensi pada Laptop ini telah aktif kembali.');
        }

        // Cek jika slot laptop sudah dipakai oleh laptop lain
        if (laptopDeviceId != null && laptopDeviceId.isNotEmpty && laptopDeviceId != currentDeviceId) {
          return ActivationResult.failure(
            'Kode lisensi ini sudah aktif pada 1 Laptop lain. Aturan: 1 Token berlaku untuk 1 HP (Android/iOS) + 1 Laptop.',
          );
        }

        // Daftarkan laptop ini
        final now = FieldValue.serverTimestamp();
        await docRef.update({
          'is_used': true,
          'laptop_device_id': currentDeviceId,
          'user_name': userName ?? data['user_name'] ?? 'User Premium',
          'used_by_email': userEmail ?? data['used_by_email'] ?? 'buyer_email',
          'user_whatsapp': userWhatsapp ?? data['user_whatsapp'] ?? '-',
          'laptop_activated_at': now,
          if (data['activated_at'] == null) 'activated_at': now,
        });

        await db.collection('devices').doc(currentDeviceId).set({
          deviceField: true,
          'device_type': 'laptop',
          'last_token_activated': token,
          'user_name': userName,
          'user_email': userEmail,
          'user_whatsapp': userWhatsapp,
          'activated_at': now,
        }, SetOptions(merge: true));

        final prefs = await SharedPreferences.getInstance();
        if (userName != null && userName.isNotEmpty) await prefs.setString('student_name', userName);
        if (userEmail != null && userEmail.isNotEmpty) await prefs.setString('student_email', userEmail);
        if (userWhatsapp != null && userWhatsapp.isNotEmpty) await prefs.setString('student_whatsapp', userWhatsapp);

        await _applyActivationLocally(expectedType);
        final targetExam = data['target_exam_id']?.toString() ?? data['target_package_id']?.toString();

        await db.collection('premium_activations').doc(token).set({
          'token': token,
          'type': tokenType,
          'user_name': userName ?? data['user_name'] ?? 'User Premium',
          'user_email': userEmail ?? data['used_by_email'] ?? '-',
          'user_whatsapp': userWhatsapp ?? data['user_whatsapp'] ?? '-',
          'device_id': currentDeviceId,
          'device_type': 'laptop',
          'target_exam_id': targetExam,
          'school': data['school'] ?? 'UMUM',
          'activated_at': now,
        }, SetOptions(merge: true));

        return ActivationResult.success(
          'Lisensi berhasil diaktifkan pada Laptop! (Token ini juga dapat dipakai di 1 HP Android/iOS).',
          targetExam,
        );
      } else {
        // Perangkat Mobile (Android / iOS)
        if (mobileDeviceId == currentDeviceId || data['device_id'] == currentDeviceId) {
          await _applyActivationLocally(expectedType);
          return ActivationResult.success('Lisensi pada HP ini telah aktif kembali.');
        }

        if (mobileDeviceId != null && mobileDeviceId.isNotEmpty && mobileDeviceId != currentDeviceId) {
          return ActivationResult.failure(
            'Kode lisensi ini sudah aktif pada 1 HP lain. Aturan: 1 Token berlaku untuk 1 HP (Android/iOS) + 1 Laptop.',
          );
        }

        // Daftarkan HP ini
        final now = FieldValue.serverTimestamp();
        await docRef.update({
          'is_used': true,
          'mobile_device_id': currentDeviceId,
          'device_id': currentDeviceId, // kompatibilitas ke belakang
          'user_name': userName ?? data['user_name'] ?? 'User Premium',
          'used_by_email': userEmail ?? data['used_by_email'] ?? 'buyer_email',
          'user_whatsapp': userWhatsapp ?? data['user_whatsapp'] ?? '-',
          'mobile_activated_at': now,
          if (data['activated_at'] == null) 'activated_at': now,
        });

        await db.collection('devices').doc(currentDeviceId).set({
          deviceField: true,
          'device_type': 'mobile',
          'last_token_activated': token,
          'user_name': userName,
          'user_email': userEmail,
          'user_whatsapp': userWhatsapp,
          'activated_at': now,
        }, SetOptions(merge: true));

        final prefs = await SharedPreferences.getInstance();
        if (userName != null && userName.isNotEmpty) await prefs.setString('student_name', userName);
        if (userEmail != null && userEmail.isNotEmpty) await prefs.setString('student_email', userEmail);
        if (userWhatsapp != null && userWhatsapp.isNotEmpty) await prefs.setString('student_whatsapp', userWhatsapp);

        await _applyActivationLocally(expectedType);
        final targetExam = data['target_exam_id']?.toString() ?? data['target_package_id']?.toString();

        await db.collection('premium_activations').doc(token).set({
          'token': token,
          'type': tokenType,
          'user_name': userName ?? data['user_name'] ?? 'User Premium',
          'user_email': userEmail ?? data['used_by_email'] ?? '-',
          'user_whatsapp': userWhatsapp ?? data['user_whatsapp'] ?? '-',
          'device_id': currentDeviceId,
          'device_type': 'mobile',
          'target_exam_id': targetExam,
          'school': data['school'] ?? 'UMUM',
          'activated_at': now,
        }, SetOptions(merge: true));

        return ActivationResult.success(
          'Lisensi berhasil diaktifkan pada HP! (Token ini juga dapat dipakai di 1 Laptop/PC).',
          targetExam,
        );
      }
    } catch (e) {
      // 2. Fallback otomatis ke GAS Server Backend jika direct Firestore gagal (misal Security Rules / Network)
      try {
        final gasResult = await _activateViaGas(
          token: token,
          userType: expectedType,
          userEmail: userEmail,
          userName: userName,
          userWhatsapp: userWhatsapp,
        );
        if (gasResult != null) return gasResult;
      } catch (_) {}

      return ActivationResult.failure(
        'Kode lisensi tidak valid, tidak terdaftar, atau koneksi terputus. Silakan periksa kembali kode Anda atau hubungi Admin ExamGO.',
      );
    }
  }

  /// Aktivasi lisensi via Google Apps Script (Service Account bypass security rules)
  Future<ActivationResult?> _activateViaGas({
    required String token,
    required String userType,
    String? userEmail,
    String? userName,
    String? userWhatsapp,
  }) async {
    final gasUrl = AppConfig.gasUrl;
    final apiKey = AppConfig.gasApiKey;
    if (gasUrl.isEmpty || apiKey.isEmpty) return null;

    final deviceId = await getDeviceId();
    final isLaptop = isLaptopOrDesktopDevice();
    final body = jsonEncode({
      'apiKey': apiKey,
      'action': 'verifyLicense',
      'token': token,
      'userType': userType,
      'deviceId': deviceId,
      'isLaptop': isLaptop,
      'deviceType': isLaptop ? 'laptop' : 'mobile',
      'userEmail': userEmail ?? 'buyer_email',
      'userName': userName ?? 'User',
      'userWhatsapp': userWhatsapp ?? '-',
    });

    try {
      final resp = await http.post(
        Uri.parse(gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          await _applyActivationLocally(userType);
          final msg = json['message']?.toString() ?? 'Aktivasi berhasil!';
          final targetExam = json['targetExamId']?.toString();
          return ActivationResult.success(msg, targetExam);
        } else if (json['error'] != null) {
          final errMsg = json['message']?.toString() ?? json['error'].toString();
          return ActivationResult.failure(errMsg);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _applyActivationLocally(String type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == 'TEACHER_PREMIUM') {
      await prefs.setBool(_kTeacherPremiumKey, true);
    } else {
      await prefs.setBool(_kStudentPremiumKey, true);
      // Pulihkan otomatis seluruh riwayat & jawaban soal siswa dari Cloud
      StudentTryoutHistoryService.instance.restoreHistoryFromCloud();
    }
  }

  // ─── BUKA LINK LYNK.ID ───────────────────────────────────────────

  /// Buka halaman pembelian Lynk.id di browser
  /// Otomatis memprioritaskan tautan dinamis dari Firestore / WebGAS jika sudah diatur
  Future<bool> openLynkIdPage({required String userType}) async {
    if (Platform.isIOS) {
      // Kepatuhan Apple Guideline 3.1.1: Dilarang mengarahkan pengguna iOS ke pembayaran eksternal
      return false;
    }

    String urlString = userType == 'TEACHER_PREMIUM'
        ? AppConfig.lynkIdTeacherUrl
        : AppConfig.lynkIdStudentUrl;

    try {
      final config = await PopupAdService.instance.getAdsConfig();
      if (userType == 'TEACHER_PREMIUM' &&
          config.teacher.ctaUrl.isNotEmpty &&
          config.teacher.ctaUrl != 'https://lynk.id') {
        urlString = config.teacher.ctaUrl;
      } else if (userType != 'TEACHER_PREMIUM' &&
          config.student.ctaUrl.isNotEmpty &&
          config.student.ctaUrl != 'https://lynk.id') {
        urlString = config.student.ctaUrl;
      }
    } catch (_) {}

    final uri = Uri.parse(urlString);
    try {
      final can = await canLaunchUrl(uri);
      if (can) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  /// Menghapus seluruh data lokal akun, lisensi, dan riwayat pada perangkat (Apple Guideline 5.1.1)
  /// serta mereset status perangkat di Cloud Firestore kembali menjadi FREE murni.
  Future<void> clearAllUserAccountData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStudentPremiumKey, false);
    await prefs.setBool(_kTeacherPremiumKey, false);
    await prefs.remove(_kStudentPremiumKey);
    await prefs.remove(_kTeacherPremiumKey);
    await prefs.remove(_kStudentAttemptsKey);
    await prefs.remove(_kTeacherUploadsKey);
    await prefs.remove(_kTeacherLicenseTokenKey);
    await prefs.remove('last_token_activated');
    await prefs.remove('active_event_token');
    await prefs.remove('active_event_id');
    await prefs.remove('student_tryout_history');
    await prefs.remove('student_tryout_history_list');
    await prefs.remove('student_name');
    await prefs.remove('student_email');
    await prefs.remove('student_whatsapp');
    await prefs.remove('teacher_exam_history');
    await prefs.remove('teacher_pin_hash');
    await prefs.remove('biometric_auth_enabled');
    await prefs.remove('examgo_onboarding_completed');
    await prefs.remove('scan_history_v3');
    try {
      final devId = await getDeviceId();
      final cleanId = devId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      await prefs.remove('scan_history_v3_$cleanId');
    } catch (_) {}

    await StudentTryoutHistoryService.instance.clearHistory();

    final db = _db;
    if (db != null) {
      try {
        final deviceId = await getDeviceId();
        // 1. Reset status perangkat di Cloud Firestore ke FREE
        await db.collection('devices').doc(deviceId).set({
          'is_student_premium': false,
          'is_teacher_premium': false,
          'last_token_activated': null,
          'deleted_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 2. Putuskan tautan lisensi perangkat ini agar tidak terikat lagi
        final studentTokens = await db
            .collection('license_tokens')
            .where('device_id', isEqualTo: deviceId)
            .get();
        for (final doc in studentTokens.docs) {
          await doc.reference.update({
            'device_id': null,
            'is_activated': false,
          });
        }

        final teacherTokens = await db
            .collection('license_tokens')
            .where('mobile_device_id', isEqualTo: deviceId)
            .get();
        for (final doc in teacherTokens.docs) {
          await doc.reference.update({
            'mobile_device_id': null,
            'is_activated': false,
          });
        }
      } catch (_) {}
    }
  }
}
