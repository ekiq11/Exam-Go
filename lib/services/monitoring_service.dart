import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';

class MonitoringService {
  static final MonitoringService instance = MonitoringService._();
  MonitoringService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  /// Hapus seluruh sesi ujian dari Firestore (beserta subcollection students)
  /// Catatan: Firestore tidak auto-delete subcollection, jadi kita hapus students dulu.
  Future<void> deleteExamSession(String examId) async {
    try {
      // 1. Ambil semua students
      final studentsSnap = await _db
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .get();

      // 2. Hapus logs tiap student lalu student-nya
      for (final studentDoc in studentsSnap.docs) {
        final logsSnap = await studentDoc.reference.collection('logs').get();
        for (final logDoc in logsSnap.docs) {
          await logDoc.reference.delete();
        }
        await studentDoc.reference.delete();
      }

      // 3. Hapus dokumen sesi utama
      await _db.collection('exam_sessions').doc(examId).delete();
    } catch (_) {}
  }
}
