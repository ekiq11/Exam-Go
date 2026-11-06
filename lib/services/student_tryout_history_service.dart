import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam_question_model.dart';
import 'national_exam_evaluator.dart';

/// Model riwayat pengerjaan tryout siswa
class StudentTryoutHistoryItem {
  final String token;
  final String namaPaket;
  final String kategori;
  final DateTime submittedAt;
  final int finalScore;
  final int maxScore;
  final int totalBenar;
  final int totalSalah;
  final int totalKosong;
  final int totalSoal;
  final bool isPassed;
  final String statusKelulusan;
  final String predikat;
  final bool allowRetake;
  final Map<String, String> jawaban;
  final List<ExamQuestion> questions;

  const StudentTryoutHistoryItem({
    required this.token,
    required this.namaPaket,
    required this.kategori,
    required this.submittedAt,
    required this.finalScore,
    required this.maxScore,
    required this.totalBenar,
    required this.totalSalah,
    required this.totalKosong,
    required this.totalSoal,
    required this.isPassed,
    required this.statusKelulusan,
    required this.predikat,
    required this.allowRetake,
    required this.jawaban,
    required this.questions,
  });

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'nama_paket': namaPaket,
      'kategori': kategori,
      'submitted_at': submittedAt.toIso8601String(),
      'final_score': finalScore,
      'max_score': maxScore,
      'total_benar': totalBenar,
      'total_salah': totalSalah,
      'total_kosong': totalKosong,
      'total_soal': totalSoal,
      'is_passed': isPassed,
      'status_kelulusan': statusKelulusan,
      'predikat': predikat,
      'allow_retake': allowRetake,
      'jawaban': jawaban,
      'questions': questions.map((q) => q.toFirestore()).toList(),
    };
  }

  factory StudentTryoutHistoryItem.fromJson(Map<String, dynamic> json) {
    final qList = <ExamQuestion>[];
    if (json['questions'] is List) {
      for (final q in json['questions'] as List) {
        if (q is Map<String, dynamic>) {
          qList.add(ExamQuestion.fromFirestore(q, q['soal_id']?.toString() ?? ''));
        }
      }
    }

    final rawAns = json['jawaban'];
    final ansMap = <String, String>{};
    if (rawAns is Map) {
      rawAns.forEach((k, v) {
        ansMap[k.toString()] = v?.toString() ?? '';
      });
    }

    return StudentTryoutHistoryItem(
      token: json['token']?.toString() ?? '',
      namaPaket: json['nama_paket']?.toString() ?? 'Tryout',
      kategori: json['kategori']?.toString() ?? 'UMUM',
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      finalScore: (json['final_score'] as num?)?.toInt() ?? 0,
      maxScore: (json['max_score'] as num?)?.toInt() ?? 100,
      totalBenar: (json['total_benar'] as num?)?.toInt() ?? 0,
      totalSalah: (json['total_salah'] as num?)?.toInt() ?? 0,
      totalKosong: (json['total_kosong'] as num?)?.toInt() ?? 0,
      totalSoal: (json['total_soal'] as num?)?.toInt() ?? qList.length,
      isPassed: json['is_passed'] == true,
      statusKelulusan: json['status_kelulusan']?.toString() ?? 'SELESAI',
      predikat: json['predikat']?.toString() ?? '-',
      allowRetake: json['allow_retake'] != false,
      jawaban: ansMap,
      questions: qList,
    );
  }
}

/// Service penyimpanan & pembacaan riwayat tryout siswa lokal
class StudentTryoutHistoryService {
  StudentTryoutHistoryService._();
  static final StudentTryoutHistoryService instance = StudentTryoutHistoryService._();

  static const String _kStorageKey = 'student_tryout_history_list';

  Future<List<StudentTryoutHistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStorageKey) ?? [];
      return list
          .map((e) => StudentTryoutHistoryItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAttempt({
    required String token,
    required String namaPaket,
    required String kategori,
    required ExamEvaluationResult result,
    required Map<String, String> answers,
    required List<ExamQuestion> questions,
    bool allowRetake = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getHistory();

      final newItem = StudentTryoutHistoryItem(
        token: token,
        namaPaket: namaPaket,
        kategori: kategori,
        submittedAt: DateTime.now(),
        finalScore: result.finalScore,
        maxScore: result.maxScore,
        totalBenar: result.totalBenar,
        totalSalah: result.totalSalah,
        totalKosong: result.totalKosong,
        totalSoal: result.totalSoal,
        isPassed: result.isPassed,
        statusKelulusan: result.statusKelulusan,
        predikat: result.predikat,
        allowRetake: allowRetake,
        jawaban: answers,
        questions: questions,
      );

      // Simpan di paling atas (terbaru), hindari duplikasi ganda berlebih
      current.removeWhere((item) => item.token == token && !allowRetake);
      current.insert(0, newItem);

      // Batasi maksimal 30 history tersimpan untuk hemat penyimpanan lokal
      if (current.length > 30) {
        current.removeLast();
      }

      final encoded = current.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_kStorageKey, encoded);
    } catch (_) {}
  }

  Future<StudentTryoutHistoryItem?> getLatestAttempt(String token) async {
    final list = await getHistory();
    try {
      return list.firstWhere((e) => e.token == token);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasAttempted(String token) async {
    final list = await getHistory();
    return list.any((e) => e.token == token);
  }
}

