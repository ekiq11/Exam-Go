import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
      ActivationResult(isSuccess: false, message: message);
}

/// Service manajemen lisensi & kuota freemium ExamGO
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const int maxFreeAttempts = 5;

  // Local Storage Keys
  static const String _kStudentPremiumKey = 'license_student_is_premium';
  static const String _kStudentAttemptsKey = 'license_student_exam_count';
  static const String _kTeacherPremiumKey = 'license_teacher_is_premium';

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
      } else {
        _cachedDeviceId = 'generic_device';
      }
    } catch (_) {
      _cachedDeviceId = 'fallback_device';
    }
    return _cachedDeviceId!;
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
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Sisa kuota ujian gratis siswa (0 s.d. 5)
  Future<int> getRemainingStudentAttempts() async {
    if (await isStudentPremium()) return 9999; // Unlimited

    final prefs = await SharedPreferences.getInstance();
    int localCount = prefs.getInt(_kStudentAttemptsKey) ?? 0;

    final db = _db;
    if (db != null) {
      // Sinkronisasi dengan Firestore (jika user uninstall/clear data, kuota tetap tercatat)
      try {
        final deviceId = await getDeviceId();
        final doc = await db.collection('devices').doc(deviceId).get();
        if (doc.exists) {
          final serverCount = (doc.data()?['exam_count'] as num?)?.toInt() ?? 0;
          if (serverCount > localCount) {
            localCount = serverCount;
            await prefs.setInt(_kStudentAttemptsKey, localCount);
          }
        }
      } catch (_) {}
    }

    final remaining = maxFreeAttempts - localCount;
    return remaining.clamp(0, maxFreeAttempts);
  }

  /// Cek apakah siswa diizinkan memulai ujian baru
  Future<bool> canStudentTakeExam() async {
    if (await isStudentPremium()) return true;
    final remaining = await getRemainingStudentAttempts();
    return remaining > 0;
  }

  /// Catat penggunaan 1 kuota ujian (dipanggil saat siswa mulai ujian)
  Future<void> recordExamAttempt() async {
    if (await isStudentPremium()) return;

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
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  // ─── AKTIVASI KODE TOKEN (Lynk.id) ────────────────────────────────

  /// Validasi dan aktivasi kode token dari email pembeli Lynk.id
  /// [expectedType]: 'TEACHER_PREMIUM' atau 'STUDENT_LIFETIME'
  Future<ActivationResult> activateToken({
    required String rawToken,
    required String expectedType,
    String? userEmail,
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

      // Jika sudah pernah dipakai pada perangkat yang sama → Reactivate
      if (isUsed && usedByDevice == currentDeviceId) {
        await _applyActivationLocally(expectedType);
        return ActivationResult.success('Lisensi pada perangkat ini telah aktif kembali.');
      }

      // Jika sudah pernah dipakai di perangkat lain
      if (isUsed) {
        return ActivationResult.failure(
          'Kode lisensi ini sudah pernah digunakan pada perangkat lain. Setiap kode hanya berlaku untuk 1 perangkat.',
        );
      }

      // Aktivasi token baru: Kunci ke perangkat ini
      final now = FieldValue.serverTimestamp();
      await docRef.update({
        'is_used': true,
        'device_id': currentDeviceId,
        'used_by_email': userEmail ?? 'buyer_email',
        'activated_at': now,
      });

      // Update data device di Firestore
      await db.collection('devices').doc(currentDeviceId).set({
        deviceField: true,
        'last_token_activated': token,
        'activated_at': now,
      }, SetOptions(merge: true));

      // Simpan status lokal
      await _applyActivationLocally(expectedType);

      final targetExam = data['target_exam_id']?.toString() ??
          data['target_package_id']?.toString();
      final label = expectedType == 'TEACHER_PREMIUM'
          ? 'Lisensi Guru Premium Aktif!'
          : 'Akses Siswa Selamanya Aktif!';
      return ActivationResult.success(label, targetExam);
    } catch (e) {
      // 2. Fallback otomatis ke GAS Server Backend jika direct Firestore gagal (misal Security Rules / Network)
      try {
        final gasResult = await _activateViaGas(
          token: token,
          userType: expectedType,
          userEmail: userEmail,
        );
        if (gasResult != null) return gasResult;
      } catch (_) {}

      return ActivationResult.failure('Terjadi kesalahan saat memverifikasi lisensi: $e');
    }
  }

  /// Aktivasi lisensi via Google Apps Script (Service Account bypass security rules)
  Future<ActivationResult?> _activateViaGas({
    required String token,
    required String userType,
    String? userEmail,
  }) async {
    final gasUrl = AppConfig.gasUrl;
    final apiKey = AppConfig.gasApiKey;
    if (gasUrl.isEmpty || apiKey.isEmpty) return null;

    final deviceId = await getDeviceId();
    final body = jsonEncode({
      'apiKey': apiKey,
      'action': 'verifyLicense',
      'token': token,
      'userType': userType,
      'deviceId': deviceId,
      'userEmail': userEmail ?? 'buyer_email',
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
    }
  }

  // ─── BUKA LINK LYNK.ID ───────────────────────────────────────────

  /// Buka halaman pembelian Lynk.id di browser
  Future<bool> openLynkIdPage({required String userType}) async {
    final urlString = userType == 'TEACHER_PREMIUM'
        ? AppConfig.lynkIdTeacherUrl
        : AppConfig.lynkIdStudentUrl;

    final uri = Uri.parse(urlString);
    try {
      final can = await canLaunchUrl(uri);
      if (can) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  // ─── GENERATOR BATCH TOKEN (Untuk Pemilik Aplikasi) ───────────────

  /// Membuat daftar kode acak dan menyimpannya ke Firestore koleksi `license_tokens`
  /// Digunakan oleh pemilik aplikasi untuk mengunggah serial number ke Lynk.id
  Future<List<String>> generateTokensBatch({
    required String type, // 'TEACHER_PREMIUM' atau 'STUDENT_LIFETIME'
    required int count,
  }) async {
    final List<String> generated = [];
    final prefix = type == 'TEACHER_PREMIUM' ? 'GURU' : 'SISWA';
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    final db = _db;
    if (db == null) throw Exception('Koneksi database Firestore tidak tersedia.');

    WriteBatch batch = db.batch();
    int batchCount = 0;

    for (int i = 0; i < count; i++) {
      String segment1 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
      String segment2 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
      String code = '$prefix-$segment1-$segment2';

      generated.add(code);

      final docRef = db.collection('license_tokens').doc(code);
      batch.set(docRef, {
        'token': code,
        'type': type,
        'is_used': false,
        'device_id': null,
        'used_by_email': null,
        'created_at': FieldValue.serverTimestamp(),
      });

      batchCount++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    return generated;
  }
}
