import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

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

      final docRef = _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis);

      await docRef.set({
        'name': name,
        'nis': nis,
        'status': status,
        'violations': violations,
        'battery_level': batteryLevel,
        'last_ping': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Abaikan error jaringan saat ujian agar tidak mengganggu siswa
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
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .orderBy('last_ping', descending: true)
        .snapshots();
  }

  /// Stream log aktivitas pelanggaran untuk satu siswa (real-time ke guru)
  Stream<QuerySnapshot> streamStudentActivityLog(String examId, String nis) {
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .doc(nis)
        .collection('logs')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Stream status satu siswa tertentu (digunakan oleh siswa untuk mendengarkan perubahan status dari guru)
  Stream<DocumentSnapshot> streamStudentStatus(String examId, String nis) {
    return _db
        .collection('exam_sessions')
        .doc(examId)
        .collection('students')
        .doc(nis)
        .snapshots();
  }

  /// Membuat sesi ujian baru dengan TTL 7 hari (expires_at)
  Future<void> createExamSession({
    required String examId,
    required String title,
    required String url,
  }) async {
    try {
      final expiresAt = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 7)),
      );
      await _db.collection('exam_sessions').doc(examId).set({
        'title': title,
        'url': url,
        'created_at': FieldValue.serverTimestamp(),
        // Field ini dibaca oleh Firestore TTL policy untuk auto-delete setelah 7 hari
        'expires_at': expiresAt,
      }, SetOptions(merge: true));
    } catch (e) {
      // Abaikan error
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
