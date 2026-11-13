import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'qr_payload.dart';
import 'license_service.dart';

class MonitoringService {
  static final MonitoringService instance = MonitoringService._();
  MonitoringService._({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @visibleForTesting
  static MonitoringService createForTest(FirebaseFirestore db) => MonitoringService._(db: db);

  // ─── Dari Sisi Siswa (Update Status) ───────────────────────────────────

  /// Dipanggil oleh siswa saat baru join, saat ujian berjalan, atau saat melanggar.
  Future<void> updateStudentStatus({
    required String examId, // Diambil dari payload.nonce di QR Code
    required String nis,
    required String name,
    required String status, // 'ONLINE', 'OFFLINE', 'BLOCKED', 'FINISHED'
    required int violations,
  }) async {
    try {
      if (examId.isEmpty || nis.isEmpty) return;

      int batteryLevel = 0;
      try {
        batteryLevel = await Battery().batteryLevel;
      } catch (_) {}
      
      final String deviceId = await getDeviceId();

      final sessionRef = _db.collection('exam_sessions').doc(examId);
      final docRef = sessionRef
          .collection('students')
          .doc(nis);

      await docRef.set({
        'name': name,
        'nis': nis,
        'status': status,
        'violations': violations,
        'battery_level': batteryLevel,
        'device_id': deviceId,
        'last_ping': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Catat sesi memiliki siswa aktif hanya sekali per siswa agar student_count tidak membengkak saat reconnect
      if (status == 'ONLINE' || status == 'ACTIVE') {
        final prefs = await SharedPreferences.getInstance();
        final joinedKey = 'joined_${examId}_$nis';
        if (prefs.getBool(joinedKey) != true) {
          await prefs.setBool(joinedKey, true);
          sessionRef.set({
            'student_count': FieldValue.increment(1),
            'last_student_join': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).catchError((_) {});
        }
      }
    } catch (e) {
      // Abaikan error jaringan saat ujian agar tidak mengganggu siswa
    }
  }

  /// Dipanggil oleh guru untuk mengubah status siswa (misal: buka blokir).
  /// Hanya mengupdate field tertentu agar tidak menimpa data device siswa
  /// (seperti battery_level dan last_ping).
  Future<void> setStudentStatusByTeacher({
    required String examId,
    required String nis,
    required String status,
    required int violations,
  }) async {
    try {
      if (examId.isEmpty || nis.isEmpty) return;

      final docRef = _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis);

      // Hanya update field yang relevan untuk aksi guru
      await docRef.set({
        'status': status,
        'violations': violations,
      }, SetOptions(merge: true));
    } catch (e) {
      // Abaikan error
    }
  }

  /// Menyimpan log aktivitas pelanggaran ke Firestore
  Future<void> logActivity({
    required String examId,
    required String nis,
    required String activityType,
    required String description,
  }) async {
    try {
      await _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .collection('logs')
          .add({
        'activity_type': activityType,
        'description': description,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Abaikan error
    }
  }

  // ─── Dari Sisi Guru (Baca Data) ────────────────────────────────────────

  /// Mengambil daftar siswa yang sedang terhubung ke sesi ujian tertentu
  Stream<QuerySnapshot> streamExamStudents(String examId) {
    if (examId.isEmpty) {
      return const Stream.empty();
    }
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .orderBy('last_ping', descending: true)
        .snapshots();
  }

  /// Mengambil daftar siswa (One-off/Manual) untuk menghemat kuota Read
  Future<QuerySnapshot> getExamStudents(String examId) {
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .orderBy('last_ping', descending: true)
        .get(const GetOptions(source: Source.serverAndCache));
  }

  /// Stream log aktivitas pelanggaran untuk satu siswa (real-time ke guru)
  Stream<QuerySnapshot> streamStudentActivityLog(String examId, String nis) {
    if (examId.isEmpty || nis.isEmpty) {
      return const Stream.empty();
    }
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .doc(nis)
        .collection('logs')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Mengambil log aktivitas (One-off/Manual)
  Future<QuerySnapshot> getStudentActivityLog(String examId, String nis) {
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .doc(nis)
        .collection('logs')
        .orderBy('timestamp', descending: true)
        .get(const GetOptions(source: Source.serverAndCache));
  }

  /// Stream status satu siswa tertentu (digunakan oleh siswa untuk mendengarkan perubahan status dari guru)
  Stream<DocumentSnapshot> streamStudentStatus(String examId, String nis) {
    if (examId.isEmpty || nis.isEmpty) {
      return const Stream.empty();
    }
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .doc(nis)
        .snapshots();
  }

  /// Mendapatkan Device ID Unik HP
  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.id; // Unique hardware ID
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.identifierForVendor ?? 'unknown_ios';
      }
    } catch (_) {}
    return 'unknown_device';
  }

  /// Get status satu siswa secara one-off (cek lokal dulu sebagai fallback kuota Firestore)
  Future<Map<String, dynamic>?> getStudentData(String examId, String nis) async {
    if (examId.isEmpty || nis.isEmpty) return null;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final localBlocked = prefs.getBool('blocked_${examId}_$nis') ?? false;
      
      final doc = await _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .get();
          
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        // Jika di server ACTIVE, hapus blokir lokal
        if (status == 'ACTIVE' && localBlocked) {
          await prefs.remove('blocked_${examId}_$nis');
        }
        // Jika di server BLOCKED, pastikan lokal juga tersimpan
        if (status == 'BLOCKED' && !localBlocked) {
          await prefs.setBool('blocked_${examId}_$nis', true);
        }
        return data;
      } else if (localBlocked) {
        // Fallback jika dokumen tidak ada atau error quota tapi lokal terblokir
        return {'status': 'BLOCKED'};
      }
    } catch (_) {
      // Jika Firestore error (misal Quota Exceeded), gunakan status lokal
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('blocked_${examId}_$nis') == true) return {'status': 'BLOCKED'};
    }
    return null;
  }
  
  /// Tandai blokir secara lokal (dijamin berfungsi meski tanpa internet/quota)
  Future<void> setLocalBlock(String examId, String nis) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('blocked_${examId}_$nis', true);
    } catch (_) {}
  }

  /// Guru / Pengawas membuka blokir siswa yang melanggar ujian
  Future<void> unblockStudent({
    required String examId,
    required String nis,
  }) async {
    try {
      if (examId.isEmpty || nis.isEmpty) return;

      final docRef = _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis);

      await docRef.set({
        'status': 'ONLINE',
        'violations': 0,
        'is_blocked': false,
        'unblocked_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await logActivity(
        examId: examId,
        nis: nis,
        activityType: 'INFO',
        description: 'Pengawas membuka blokir ujian siswa dan mereset status pelanggaran.',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('blocked_${examId}_$nis');
    } catch (_) {}
  }

  /// Guru / Pengawas mengizinkan siswa tertentu untuk mengerjakan ulang ujian
  Future<void> allowStudentRetake({
    required String examId,
    required String nis,
  }) async {
    try {
      await _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .set({
            'status': 'ONLINE',
            'allow_retake': true,
            'retake_granted_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      await logActivity(
        examId: examId,
        nis: nis,
        activityType: 'INFO',
        description: 'Pengawas memberikan izin kepada siswa untuk mengerjakan ulang ujian.',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('blocked_${examId}_$nis');
      await prefs.setBool('retake_allowed_${examId}_$nis', true);
    } catch (_) {}
  }

  /// Membuat sesi ujian baru dengan TTL 10 hari (expires_at) dan student_count = 0
  Future<void> createExamSession({
    required String examId,
    required String title,
    required String url,
    String? teacherToken,
  }) async {
    try {
      final expiresAt = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 10)),
      );
      final token = teacherToken ?? await LicenseService.instance.getTeacherLicenseToken();
      await _db.collection('exam_sessions').doc(examId).set({
        'title': title,
        'url': url,
        'created_at': FieldValue.serverTimestamp(),
        'student_count': 0,
        if (token != null && token.isNotEmpty) 'teacher_token': token,
        // Field ini dibaca oleh Firestore TTL policy untuk auto-delete setelah 10 hari
        'expires_at': expiresAt,
      }, SetOptions(merge: true));
    } catch (e) {
      // Abaikan error
    }
  }

  /// Sinkronisasi otomatis riwayat sesi ujian & token guru dari Cloud Firestore
  /// Mengambil semua ujian yang pernah diterbitkan oleh guru ini (baik lewat WebGAS maupun aplikasi mobile)
  Future<List<String>> syncTeacherExamHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final localList = prefs.getStringList('teacher_exam_history') ?? [];

    final Map<String, String> examMap = {};
    for (final item in localList) {
      final parts = item.split('|');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        examMap[parts[0]] = item;
      }
    }

    try {
      final teacherToken = await LicenseService.instance.getTeacherLicenseToken();
      if (teacherToken != null && teacherToken.isNotEmpty) {
        // 1. Ambil dari koleksi exam_sessions
        final sessionSnap = await _db
            .collection('exam_sessions')
            .where('teacher_token', isEqualTo: teacherToken)
            .get();

        for (final doc in sessionSnap.docs) {
          final data = doc.data();
          final examId = doc.id;
          final title = (data['title'] as String?) ?? 'Ujian CBT';
          final url = (data['url'] as String?) ?? 'EXAMGO_TRYOUT://$examId';
          final qrPayload = (data['qr_payload'] as String?) ??
              QRPayloadService.generate(url, title: title);
          int ts = 0;
          final createdAt = data['created_at'];
          if (createdAt is Timestamp) {
            ts = createdAt.millisecondsSinceEpoch;
          } else if (createdAt is String) {
            ts = DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ?? 0;
          }
          if (ts == 0) ts = DateTime.now().millisecondsSinceEpoch;

          if (!examMap.containsKey(examId)) {
            examMap[examId] = '$examId|$title|$ts|$url|$qrPayload';
          }
        }

        // 2. Ambil dari koleksi paket_tryout
        final pkgSnap = await _db
            .collection('paket_tryout')
            .where('teacher_token', isEqualTo: teacherToken)
            .get();

        for (final doc in pkgSnap.docs) {
          final data = doc.data();
          final examId = doc.id;
          final title = (data['nama_paket'] as String?) ?? 'Ujian CBT';
          final url = 'EXAMGO_TRYOUT://$examId';
          final qrPayload = QRPayloadService.generate(url, title: title);
          int ts = 0;
          final createdAt = data['created_at'];
          if (createdAt is Timestamp) {
            ts = createdAt.millisecondsSinceEpoch;
          } else if (createdAt is String) {
            ts = DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ?? 0;
          }
          if (ts == 0) ts = DateTime.now().millisecondsSinceEpoch;

          if (!examMap.containsKey(examId)) {
            examMap[examId] = '$examId|$title|$ts|$url|$qrPayload';
          }
        }
      }
    } catch (_) {}

    // Urutkan berdasarkan timestamp descending (terbaru di atas)
    final mergedList = examMap.values.toList()
      ..sort((a, b) {
        final ptsA = a.split('|');
        final ptsB = b.split('|');
        final tsA = ptsA.length > 2 ? int.tryParse(ptsA[2]) ?? 0 : 0;
        final tsB = ptsB.length > 2 ? int.tryParse(ptsB[2]) ?? 0 : 0;
        return tsB.compareTo(tsA);
      });

    if (mergedList.length != localList.length) {
      await prefs.setStringList('teacher_exam_history', mergedList);
    }
    return mergedList;
  }

  /// Memeriksa dan otomatis menghapus sesi ujian jika umur >= 10 hari dan siswanya 0
  Future<bool> cleanupIfAbandoned(String examId, DateTime createdAt) async {
    try {
      final diff = DateTime.now().difference(createdAt);
      if (diff.inDays < 10) return false;

      final doc = await _db.collection('exam_sessions').doc(examId).get();
      if (!doc.exists) return true; // Sudah terhapus

      final data = doc.data();
      final studentCount = (data?['student_count'] as num?)?.toInt() ?? 0;
      if (studentCount == 0) {
        await deleteExamSession(examId);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Hapus seluruh sesi ujian dari Firestore (beserta subcollection students).
  /// FIX BUG-05: Gunakan WriteBatch dengan chunking 500 dokumen (batas Firestore)
  /// untuk menggantikan sequential O(n²) delete yang bisa timeout pada sesi besar.
  Future<void> deleteExamSession(String examId) async {
    try {
      final sessionRef = _db.collection('exam_sessions').doc(examId);

      // Helper: batch delete max 500 docs per batch (batas Firestore WriteBatch)
      Future<void> batchDelete(List<DocumentSnapshot> docs) async {
        if (docs.isEmpty) return;
        for (var i = 0; i < docs.length; i += 500) {
          final chunk = docs.sublist(
            i,
            (i + 500) < docs.length ? (i + 500) : docs.length,
          );
          final batch = _db.batch();
          for (final doc in chunk) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      }

      // 1. Hapus logs tiap student menggunakan batch
      final studentsSnap = await sessionRef.collection('students').get();
      for (final studentDoc in studentsSnap.docs) {
        final logsSnap = await studentDoc.reference.collection('logs').get();
        await batchDelete(logsSnap.docs);
      }

      // 2. Hapus semua student documents sekaligus menggunakan batch
      await batchDelete(studentsSnap.docs);

      // 3. Hapus dokumen sesi utama
      await sessionRef.delete();
    } catch (_) {}
  }
}
