import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam_question_model.dart';
import 'license_service.dart';
import 'national_exam_evaluator.dart';
import 'trusted_time_service.dart';

/// Model riwayat pengerjaan tryout siswa
class StudentTryoutHistoryItem {
  final String token;
  final String namaPaket;
  final String kategori;
  final DateTime submittedAt;
  final DateTime? examEndTime;
  final int? elapsedRealtimeMs;
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
  final Map<String, dynamic>? subtestScores;

  const StudentTryoutHistoryItem({
    required this.token,
    required this.namaPaket,
    required this.kategori,
    required this.submittedAt,
    this.examEndTime,
    this.elapsedRealtimeMs,
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
    this.subtestScores,
  });

  /// Apakah waktu ujian resmi sudah habis sehingga pembahasan & kunci boleh dibuka
  bool get isExamTimeEnded {
    if (examEndTime == null) return true;
    return TrustedTimeService.instance.trustedNowSync.isAfter(examEndTime!);
  }

  /// Sisa waktu sebelum kunci & pembahasan dibuka (dalam menit/detik)
  Duration? get remainingExamDuration {
    if (examEndTime == null) return null;
    final diff = examEndTime!.difference(TrustedTimeService.instance.trustedNowSync);
    return diff.isNegative ? Duration.zero : diff;
  }

  StudentTryoutHistoryItem copyWith({
    String? token,
    String? namaPaket,
    String? kategori,
    DateTime? submittedAt,
    DateTime? examEndTime,
    int? elapsedRealtimeMs,
    int? finalScore,
    int? maxScore,
    int? totalBenar,
    int? totalSalah,
    int? totalKosong,
    int? totalSoal,
    bool? isPassed,
    String? statusKelulusan,
    String? predikat,
    bool? allowRetake,
    Map<String, String>? jawaban,
    List<ExamQuestion>? questions,
    Map<String, dynamic>? subtestScores,
  }) {
    return StudentTryoutHistoryItem(
      token: token ?? this.token,
      namaPaket: namaPaket ?? this.namaPaket,
      kategori: kategori ?? this.kategori,
      submittedAt: submittedAt ?? this.submittedAt,
      examEndTime: examEndTime ?? this.examEndTime,
      elapsedRealtimeMs: elapsedRealtimeMs ?? this.elapsedRealtimeMs,
      finalScore: finalScore ?? this.finalScore,
      maxScore: maxScore ?? this.maxScore,
      totalBenar: totalBenar ?? this.totalBenar,
      totalSalah: totalSalah ?? this.totalSalah,
      totalKosong: totalKosong ?? this.totalKosong,
      totalSoal: totalSoal ?? this.totalSoal,
      isPassed: isPassed ?? this.isPassed,
      statusKelulusan: statusKelulusan ?? this.statusKelulusan,
      predikat: predikat ?? this.predikat,
      allowRetake: allowRetake ?? this.allowRetake,
      jawaban: jawaban ?? this.jawaban,
      questions: questions ?? this.questions,
      subtestScores: subtestScores ?? this.subtestScores,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'nama_paket': namaPaket,
      'kategori': kategori,
      'submitted_at': submittedAt.toIso8601String(),
      if (examEndTime != null) 'exam_end_time': examEndTime!.toIso8601String(),
      if (elapsedRealtimeMs != null) 'elapsed_realtime_ms': elapsedRealtimeMs,
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
      if (subtestScores != null) 'subtest_scores': subtestScores,
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

    Map<String, dynamic>? subScores;
    if (json['subtest_scores'] is Map) {
      subScores = Map<String, dynamic>.from(json['subtest_scores'] as Map);
    }

    return StudentTryoutHistoryItem(
      token: json['token']?.toString() ?? '',
      namaPaket: json['nama_paket']?.toString() ?? 'Tryout',
      kategori: json['kategori']?.toString() ?? 'UMUM',
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      examEndTime: json['exam_end_time'] != null
          ? DateTime.tryParse(json['exam_end_time'].toString())
          : null,
      elapsedRealtimeMs: (json['elapsed_realtime_ms'] as num?)?.toInt(),
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
      subtestScores: subScores,
    );
  }
}

/// Service penyimpanan & pembacaan riwayat tryout siswa lokal
class StudentTryoutHistoryService {
  StudentTryoutHistoryService._();
  static final StudentTryoutHistoryService instance = StudentTryoutHistoryService._();

  static const String _kStorageKey = 'student_tryout_history_list';

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

  bool _isRestoring = false;

  Future<List<StudentTryoutHistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStorageKey) ?? [];
      if (list.isNotEmpty) {
        return list
            .map((e) => StudentTryoutHistoryItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
            .toList();
      }

      // Jika data lokal kosong (misal baru install ulang), coba pulihkan dari cloud jika user premium
      _syncCloudHistoryInBackground();
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Sinkronisasi background otomatis saat data lokal kosong
  void _syncCloudHistoryInBackground() {
    if (_isRestoring) return;
    _isRestoring = true;
    Future.microtask(() async {
      try {
        final isPrem = await LicenseService.instance.isStudentPremium();
        if (isPrem) {
          await restoreHistoryFromCloud();
        }
      } catch (_) {
      } finally {
        _isRestoring = false;
      }
    });
  }

  /// Cadangkan riwayat ujian & jawaban siswa ke cloud Firestore jika pengguna adalah Premium
  Future<bool> backupAttemptToCloud(StudentTryoutHistoryItem item) async {
    final db = _db;
    if (db == null) return false;

    try {
      final isPremium = await LicenseService.instance.isStudentPremium();
      final prefs = await SharedPreferences.getInstance();
      final activeToken = prefs.getString('last_token_activated') ??
          prefs.getString('active_event_token');
      final deviceId = await LicenseService.instance.getDeviceId();

      // Hanya cadangkan ke cloud jika pengguna Premium atau memiliki token lisensi aktif
      if (!isPremium && (activeToken == null || activeToken.isEmpty)) {
        return false;
      }

      final userKey = (activeToken != null && activeToken.isNotEmpty)
          ? activeToken.replaceAll('/', '_')
          : deviceId;

      final docId = '${userKey}_${item.token}';
      final docRef = db.collection('student_tryout_history').doc(docId);

      final payload = {
        'user_key': userKey,
        'license_token': activeToken ?? '',
        'device_id': deviceId,
        'token': item.token,
        'nama_paket': item.namaPaket,
        'kategori': item.kategori,
        'final_score': item.finalScore,
        'max_score': item.maxScore,
        'total_soal': item.totalSoal,
        'submitted_at': item.submittedAt.toIso8601String(),
        'updated_at': FieldValue.serverTimestamp(),
        'history_data': item.toJson(),
      };

      await docRef.set(payload, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pulihkan seluruh riwayat ujian dan butir jawaban yang pernah dikerjakan dari Firestore
  /// Digunakan saat aplikasi baru di-install ulang atau token diaktifkan kembali
  Future<List<StudentTryoutHistoryItem>> restoreHistoryFromCloud({
    String? licenseToken,
  }) async {
    final db = _db;
    if (db == null) return await getHistory();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = licenseToken ??
          prefs.getString('last_token_activated') ??
          prefs.getString('active_event_token');
      final deviceId = await LicenseService.instance.getDeviceId();

      final keysToQuery = <String>{};
      if (token != null && token.isNotEmpty) {
        keysToQuery.add(token.replaceAll('/', '_'));
      }
      keysToQuery.add(deviceId);

      final restoredMap = <String, StudentTryoutHistoryItem>{};

      for (final key in keysToQuery) {
        try {
          final snap = await db
              .collection('student_tryout_history')
              .where('user_key', isEqualTo: key)
              .get()
              .timeout(const Duration(milliseconds: 4000));

          for (final doc in snap.docs) {
            final data = doc.data();
            final rawHistory = data['history_data'];
            if (rawHistory is Map<String, dynamic>) {
              final item = StudentTryoutHistoryItem.fromJson(rawHistory);
              if (!restoredMap.containsKey(item.token) ||
                  item.submittedAt.isAfter(restoredMap[item.token]!.submittedAt)) {
                restoredMap[item.token] = item;
              }
            }
          }
        } catch (_) {}
      }

      if (restoredMap.isEmpty) {
        return await getHistory();
      }

      // Gabungkan dengan data lokal yang sudah ada
      final local = await getHistory();
      for (final item in local) {
        if (!restoredMap.containsKey(item.token) ||
            item.submittedAt.isAfter(restoredMap[item.token]!.submittedAt)) {
          restoredMap[item.token] = item;
        }
      }

      final mergedList = restoredMap.values.toList()
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

      // Simpan pemulihan ke SharedPreferences lokal
      await updateHistoryList(mergedList);
      return mergedList;
    } catch (_) {
      return await getHistory();
    }
  }

  Future<void> saveAttempt({
    required String token,
    required String namaPaket,
    required String kategori,
    required ExamEvaluationResult result,
    required Map<String, String> answers,
    required List<ExamQuestion> questions,
    DateTime? examEndTime,
    bool allowRetake = true,
    Map<String, dynamic>? subtestScores,
    bool syncCloud = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getHistory();

      final effectiveSubtests = subtestScores ??
          result.subtests.map((k, v) => MapEntry(k, v.toMap()));

      int? elapsedMs;
      try {
        elapsedMs = await TrustedTimeService.instance.getElapsedRealtime();
      } catch (_) {}

      final newItem = StudentTryoutHistoryItem(
        token: token,
        namaPaket: namaPaket,
        kategori: kategori,
        submittedAt: DateTime.now(),
        examEndTime: examEndTime,
        elapsedRealtimeMs: elapsedMs,
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
        subtestScores: effectiveSubtests,
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

      // Cadangkan otomatis ke cloud untuk pengguna Premium
      if (syncCloud) {
        await backupAttemptToCloud(newItem);
      } else {
        unawaited(backupAttemptToCloud(newItem));
      }
    } catch (_) {}
  }

  /// Perbarui list history di penyimpanan lokal
  Future<void> updateHistoryList(List<StudentTryoutHistoryItem> updated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = updated.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_kStorageKey, encoded);
    } catch (_) {}
  }

  /// Ambil data subtest_scores riwayat ujian langsung dari Firestore jika di cache lokal belum ada
  Future<Map<String, dynamic>?> fetchSubtestScoresFromFirestore(String token, {String? nis}) async {
    try {
      final db = _db ?? FirebaseFirestore.instance;
      final prefs = await SharedPreferences.getInstance();
      final effectiveNis = (nis != null && nis.isNotEmpty) ? nis : (prefs.getString('student_nis') ?? '');
      // 1. Coba cari dengan doc ID spesifik (${nis}_${token})
      if (effectiveNis.isNotEmpty) {
        final doc = await db
            .collection('jawaban_tryout')
            .doc('${effectiveNis}_$token')
            .get()
            .timeout(const Duration(milliseconds: 3500));
        if (doc.exists && doc.data()?['subtest_scores'] is Map) {
          return Map<String, dynamic>.from(doc.data()!['subtest_scores'] as Map);
        }
      }

      // 2. Query berdasarkan device_id perangkat saat ini agar tidak mengambil nilai siswa lain
      final deviceId = await LicenseService.instance.getDeviceId();
      final query = await db
          .collection('jawaban_tryout')
          .where('device_id', isEqualTo: deviceId)
          .limit(20)
          .get()
          .timeout(const Duration(milliseconds: 3500));

      for (final doc in query.docs) {
        final data = doc.data();
        if (data['token']?.toString().toUpperCase() == token.trim().toUpperCase() &&
            data['subtest_scores'] is Map) {
          return Map<String, dynamic>.from(data['subtest_scores'] as Map);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<StudentTryoutHistoryItem?> getLatestAttempt(String token) async {
    final list = await getHistory();
    final upper = token.trim().toUpperCase();
    try {
      return list.firstWhere((e) => e.token.trim().toUpperCase() == upper);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasAttempted(String token) async {
    final list = await getHistory();
    return list.any((e) => e.token == token);
  }

  // ─── Leaderboard & Peringkat Nasional (Serverless & Zero-Cost) ──────────────

  /// Mengambil data leaderboard nasional untuk paket tryout tertentu (100% Data Real Firestore)
  Future<TryoutLeaderboardData> getNationalLeaderboard({
    required String token,
    required String kategori,
    required int userScore,
    String? userName,
  }) async {
    final cleanToken = token.trim();
    final upperToken = cleanToken.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    final currentName = userName ?? prefs.getString('student_name') ?? 'Siswa ExamGO';
    final currentNis = prefs.getString('student_nis') ?? '';
    final deviceId = await LicenseService.instance.getDeviceId();
    final maskedCurrentName = maskName(currentName);

    // Map untuk deduplikasi peserta unik (key: deviceId / nis / nama)
    final participantsMap = <String, TryoutLeaderboardEntry>{};

    final db = _db;
    if (db != null) {
      // 1. Rekam / update skor user ke Firestore rankings jika memiliki skor valid
      if (userScore > 0) {
        try {
          await db
              .collection('tryout_leaderboards')
              .doc(cleanToken)
              .collection('rankings')
              .doc(deviceId)
              .set({
            'device_id': deviceId,
            'student_name': maskedCurrentName,
            'score': userScore,
            'kategori': kategori,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      // 2. Ambil data peringkat dari tryout_leaderboards
      try {
        final snapRankings = await db
            .collection('tryout_leaderboards')
            .doc(cleanToken)
            .collection('rankings')
            .orderBy('score', descending: true)
            .limit(100)
            .get()
            .timeout(const Duration(milliseconds: 3500));

        for (final doc in snapRankings.docs) {
          final data = doc.data();
          final devId = data['device_id']?.toString() ?? doc.id;
          final isMe = devId == deviceId;
          final s = (data['score'] as num?)?.toInt() ?? 0;
          final sName = data['student_name']?.toString() ?? 'Peserta ExamGO';
          final dedupeKey = devId.isNotEmpty ? devId : sName.toLowerCase();
          final acc = (s.clamp(0, 1000) / (kategori.toUpperCase() == 'SNBT' ? 10 : (kategori.toUpperCase() == 'SKD' ? 5.5 : 1))).clamp(0.0, 100.0);

          participantsMap[dedupeKey] = TryoutLeaderboardEntry(
            rank: 0,
            name: isMe ? maskedCurrentName : maskName(sName),
            schoolOrCity: isMe ? 'Perangkat Ini' : 'Siswa Nasional',
            score: s,
            accuracy: acc,
            isCurrentUser: isMe,
          );
        }
      } catch (_) {}

      // 3. Ambil data real submissions dari jawaban_tryout
      try {
        final tokensToQuery = <String>{cleanToken, upperToken};
        for (final t in tokensToQuery) {
          final snapAnswers = await db
              .collection('jawaban_tryout')
              .where('token', isEqualTo: t)
              .limit(100)
              .get()
              .timeout(const Duration(milliseconds: 3500));

          for (final doc in snapAnswers.docs) {
            final data = doc.data();
            final docDevId = data['device_id']?.toString() ?? '';
            final docNis = data['nis']?.toString() ?? '';
            final rawName = data['nama_peserta']?.toString() ?? 'Peserta ExamGO';
            final rawScore = (data['skor_akhir'] as num?)?.toInt() ?? 0;

            final isMe = (docDevId.isNotEmpty && docDevId == deviceId) ||
                (docNis.isNotEmpty && currentNis.isNotEmpty && docNis == currentNis);

            final dedupeKey = docDevId.isNotEmpty
                ? docDevId
                : (docNis.isNotEmpty ? docNis : rawName.toLowerCase());

            final acc = (rawScore.clamp(0, 1000) / (kategori.toUpperCase() == 'SNBT' ? 10 : (kategori.toUpperCase() == 'SKD' ? 5.5 : 1))).clamp(0.0, 100.0);

            if (!participantsMap.containsKey(dedupeKey) ||
                rawScore > participantsMap[dedupeKey]!.score) {
              participantsMap[dedupeKey] = TryoutLeaderboardEntry(
                rank: 0,
                name: isMe ? maskedCurrentName : maskName(rawName),
                schoolOrCity: isMe ? 'Perangkat Ini' : 'Siswa Nasional',
                score: rawScore,
                accuracy: acc,
                isCurrentUser: isMe,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 4. Pastikan current user dengan userScore masuk ke dalam list
    final hasMe = participantsMap.values.any((e) => e.isCurrentUser);
    if (!hasMe && userScore > 0) {
      final acc = (userScore.clamp(0, 1000) / (kategori.toUpperCase() == 'SNBT' ? 10 : (kategori.toUpperCase() == 'SKD' ? 5.5 : 1))).clamp(0.0, 100.0);
      participantsMap[deviceId] = TryoutLeaderboardEntry(
        rank: 0,
        name: maskedCurrentName,
        schoolOrCity: 'Perangkat Ini',
        score: userScore,
        accuracy: acc,
        isCurrentUser: true,
      );
    }

    // 5. Urutkan secara descending berdasarkan skor riil
    final sorted = participantsMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final entries = <TryoutLeaderboardEntry>[];
    int userRank = 1;
    for (int i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      final rank = i + 1;
      if (item.isCurrentUser) {
        userRank = rank;
      }
      entries.add(
        TryoutLeaderboardEntry(
          rank: rank,
          name: item.name,
          schoolOrCity: item.schoolOrCity,
          score: item.score,
          accuracy: item.accuracy,
          isCurrentUser: item.isCurrentUser,
        ),
      );
    }

    final totalCount = entries.length;
    final percentile = totalCount > 1
        ? (((totalCount - userRank) / totalCount) * 100).clamp(1.0, 99.9)
        : (totalCount == 1 ? 100.0 : 0.0);

    final avgScore = entries.isNotEmpty
        ? (entries.map((e) => e.score).reduce((a, b) => a + b) / entries.length).round()
        : userScore;

    return TryoutLeaderboardData(
      userRank: userRank,
      totalParticipants: totalCount,
      percentile: percentile,
      averageScore: avgScore,
      entries: entries,
    );
  }

  /// Menyamarkan nama siswa untuk privasi (contoh: "Ahmad Subki" -> "Ahmad S.")
  static String maskName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Siswa ExamGO';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      if (parts[0].length <= 3) return parts[0];
      return '${parts[0].substring(0, 3)}***';
    }
    return '${parts[0]} ${parts[1][0]}.';
  }

  // ─── Target Passing Grade PTN / Formasi CPNS Tracker ────────────────────────

  static const String _kTargetNameKey = 'student_target_program_name';
  static const String _kTargetScoreKey = 'student_target_program_score';

  /// Menyimpan target kampus impian atau formasi CPNS
  Future<void> saveTargetGoal({required String name, required int targetScore}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTargetNameKey, name.trim());
    await prefs.setInt(_kTargetScoreKey, targetScore);
  }

  /// Mengambil target impian yang disimpan siswa (dengan fallback default jika belum diset)
  Future<Map<String, dynamic>> getTargetGoal(String kategori) async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_kTargetNameKey);
    final savedScore = prefs.getInt(_kTargetScoreKey);

    if (savedName != null && savedScore != null) {
      return {'name': savedName, 'score': savedScore};
    }

    // Default rekomendasi berdasarkan kategori
    final isSnbt = kategori.toUpperCase().contains('SNBT') || kategori.toUpperCase().contains('UTBK');
    final isSkd = kategori.toUpperCase().contains('SKD') || kategori.toUpperCase().contains('CPNS');

    if (isSnbt) {
      return {'name': 'Teknik Informatika / Kedokteran PTN', 'score': 685};
    } else if (isSkd) {
      return {'name': 'Formasi Kementerian / Lembaga Pusat', 'score': 410};
    } else {
      return {'name': 'Target Passing Grade Nasional', 'score': 75};
    }
  }
}

/// Data ringkasan leaderboard nasional
class TryoutLeaderboardData {
  final int userRank;
  final int totalParticipants;
  final double percentile;
  final int averageScore;
  final List<TryoutLeaderboardEntry> entries;

  const TryoutLeaderboardData({
    required this.userRank,
    required this.totalParticipants,
    required this.percentile,
    required this.averageScore,
    required this.entries,
  });
}

/// Entri baris leaderboard
class TryoutLeaderboardEntry {
  final int rank;
  final String name;
  final String schoolOrCity;
  final int score;
  final double accuracy;
  final bool isCurrentUser;

  const TryoutLeaderboardEntry({
    required this.rank,
    required this.name,
    required this.schoolOrCity,
    required this.score,
    required this.accuracy,
    this.isCurrentUser = false,
  });
}

