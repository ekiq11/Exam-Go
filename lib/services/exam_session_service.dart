// lib/services/exam_session_service.dart
// Menyimpan sesi ujian ke SharedPreferences agar bisa di-recover
// jika app crash atau dimatikan paksa saat ujian berlangsung.
import 'package:shared_preferences/shared_preferences.dart';

class ExamSessionService {
  ExamSessionService._();
  static final ExamSessionService instance = ExamSessionService._();

  static const _kUrl         = 'session_url';
  static const _kTitle       = 'session_title';
  static const _kStartedAt  = 'session_started_at';
  static const _kViolations = 'session_violations';
  static const _kActive     = 'session_active';
  // FIX AUDIT-1: Simpan context monitoring agar crash recovery
  // bisa restore Firestore stream dan FCM notification.
  static const _kExamId      = 'session_exam_id';
  static const _kStudentName = 'session_student_name';
  static const _kStudentNis  = 'session_student_nis';

  /// Simpan sesi baru saat ujian dimulai
  Future<void> save({
    required String url,
    required String title,
    String examId = '',
    String studentName = '',
    String studentNis = '',
    int violations = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kActive, true);
    await prefs.setString(_kUrl, url);
    await prefs.setString(_kTitle, title);
    await prefs.setString(_kStartedAt, DateTime.now().toIso8601String());
    await prefs.setInt(_kViolations, violations);
    await prefs.setString(_kExamId, examId);
    await prefs.setString(_kStudentName, studentName);
    await prefs.setString(_kStudentNis, studentNis);
  }

  /// Update jumlah pelanggaran saat berjalan
  Future<void> updateViolations(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kViolations, count);
  }

  /// Hapus sesi saat ujian selesai / keluar normal
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActive);
    await prefs.remove(_kUrl);
    await prefs.remove(_kTitle);
    await prefs.remove(_kStartedAt);
    await prefs.remove(_kViolations);
    await prefs.remove(_kExamId);
    await prefs.remove(_kStudentName);
    await prefs.remove(_kStudentNis);
  }

  /// Cek apakah ada sesi yang belum selesai (crash recovery)
  Future<ExamSession?> getActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool(_kActive) ?? false;
    if (!isActive) return null;

    final url   = prefs.getString(_kUrl);
    final title = prefs.getString(_kTitle);
    if (url == null || url.isEmpty) return null;

    final startedAtStr = prefs.getString(_kStartedAt);
    final startedAt    = startedAtStr != null
        ? DateTime.tryParse(startedAtStr)
        : null;

    return ExamSession(
      url: url,
      title: title ?? '',
      startedAt: startedAt ?? DateTime.now(),
      violations: prefs.getInt(_kViolations) ?? 0,
      examId: prefs.getString(_kExamId) ?? '',
      studentName: prefs.getString(_kStudentName) ?? '',
      studentNis: prefs.getString(_kStudentNis) ?? '',
    );
  }
}

class ExamSession {
  final String url;
  final String title;
  final DateTime startedAt;
  final int violations;
  // FIX AUDIT-1: Tambah fields monitoring context
  final String examId;
  final String studentName;
  final String studentNis;

  const ExamSession({
    required this.url,
    required this.title,
    required this.startedAt,
    required this.violations,
    this.examId = '',
    this.studentName = '',
    this.studentNis = '',
  });

  /// Durasi sesi dalam detik
  int get elapsedSeconds =>
      DateTime.now().difference(startedAt).inSeconds;
}
