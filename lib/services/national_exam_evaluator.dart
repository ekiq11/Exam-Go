import '../models/exam_question_model.dart';

/// Hasil evaluasi per subtest ujian
class SubtestEvaluation {
  final String subtestId;
  final String judul;
  final int benar;
  final int salah;
  final int kosong;
  final int total;
  final int skor;
  final int maxSkor;
  final int? passingGrade;
  final bool isPassed;
  final String predikat;
  final bool isTkp;

  const SubtestEvaluation({
    required this.subtestId,
    required this.judul,
    required this.benar,
    required this.salah,
    required this.kosong,
    required this.total,
    required this.skor,
    required this.maxSkor,
    this.passingGrade,
    required this.isPassed,
    required this.predikat,
    this.isTkp = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'subtest_id': subtestId,
      'judul': judul,
      'benar': benar,
      'salah': salah,
      'kosong': kosong,
      'total': total,
      'skor': skor,
      'max_skor': maxSkor,
      if (passingGrade != null) 'passing_grade': passingGrade,
      'is_passed': isPassed,
      'predikat': predikat,
      'is_tkp': isTkp,
    };
  }
}

/// Hasil evaluasi komprehensif ujian standar nasional (SNBT, SKD, TKA, UMUM)
class ExamEvaluationResult {
  final int finalScore;
  final int maxScore;
  final int totalBenar;
  final int totalSalah;
  final int totalKosong;
  final int totalSoal;
  final bool isPassed;
  final String statusKelulusan;
  final String predikat;
  final String category;
  final Map<String, SubtestEvaluation> subtests;

  const ExamEvaluationResult({
    required this.finalScore,
    required this.maxScore,
    required this.totalBenar,
    required this.totalSalah,
    required this.totalKosong,
    required this.totalSoal,
    required this.isPassed,
    required this.statusKelulusan,
    required this.predikat,
    required this.category,
    required this.subtests,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'skor_akhir': finalScore,
      'max_skor': maxScore,
      'jumlah_benar': totalBenar,
      'jumlah_salah': totalSalah,
      'jumlah_kosong': totalKosong,
      'total_soal': totalSoal,
      'is_passed': isPassed,
      'status_kelulusan': statusKelulusan,
      'predikat': predikat,
      'kategori': category,
      'subtest_scores': subtests.map((k, v) => MapEntry(k, v.toMap())),
    };
  }
}

/// Evaluator Standar Penilaian Nasional Resmi
/// Diadaptasi langsung dari logika myOLCv2 (TryoutLogicHelper & Kode_TryoutBankSoal.js)
class NationalExamEvaluator {
  NationalExamEvaluator._();

  /// Evaluasi jawaban siswa berdasarkan standar ujian nasional
  static ExamEvaluationResult evaluate({
    required String category,
    required List<ExamSubtest> subtests,
    required List<ExamQuestion> allQuestions,
    required Map<String, String> answers,
    int? customPassingPercentage,
  }) {
    final catNorm = category.trim().toUpperCase();
    final isSKD = catNorm.contains('SKD');
    final isSNBT = catNorm.contains('SNBT') || catNorm.contains('UTBK');
    final isTKA = catNorm.contains('TKA');

    final Map<String, SubtestEvaluation> evaluatedSubtests = {};

    int accBenar = 0;
    int accSalah = 0;
    int accKosong = 0;
    int accTotalSoal = 0;

    for (final st in subtests) {
      final stQuestions = st.soalList.isNotEmpty
          ? st.soalList
          : allQuestions.where((q) => q.subtestId == st.subtestId).toList();

      final stJudul = st.judul.trim();
      final judulLower = stJudul.toLowerCase();

      // Deteksi tipe subtest SKD
      final isTwk = isSKD && (judulLower.contains('twk') || judulLower.contains('wawasan'));
      final isTiu = isSKD && (judulLower.contains('tiu') || judulLower.contains('intelegensia') || judulLower.contains('intelejensia'));
      bool isTkp = isSKD && (judulLower.contains('tkp') || judulLower.contains('karakteristik'));

      // Cek apakah ada soal dengan kunci bertingkat (berisi koma, misal: D,B,A,C,E)
      if (!isTkp && isSKD && stQuestions.isNotEmpty) {
        if (stQuestions.any((q) => q.kunci.contains(','))) {
          isTkp = true;
        }
      }

      int stBenar = 0;
      int stSalah = 0;
      int stKosong = 0;
      int stScore = 0;

      for (final q in stQuestions) {
        final ans = (answers[q.soalId] ?? '').trim().toUpperCase();
        final rawKey = q.kunci.trim().toUpperCase();

        if (ans.isEmpty) {
          stKosong++;
          continue;
        }

        final cleanKey = rawKey.replaceAll(RegExp(r'[^A-Z]'), '');
        final isWeightedKey = rawKey.contains(',') && cleanKey.length > 1;

        if (isTkp || isWeightedKey) {
          // Penilaian bertingkat TKP: Skor berdasarkan bobot ranking opsi (misal 5,4,3,2,1)
          final idx = cleanKey.indexOf(ans);
          if (idx != -1) {
            final points = cleanKey.length - idx;
            stScore += points;
            stBenar++;
          } else {
            // Opsi dipilih namun tidak tercantum di kunci: skor minimal 1
            stScore += 1;
            stBenar++;
          }
        } else {
          // Penilaian biner (Benar / Salah)
          if (ans == cleanKey) {
            stBenar++;
            if (isSKD) {
              stScore += 5; // SKD: 5 poin per jawaban benar
            }
          } else {
            stSalah++;
          }
        }
      }

      accBenar += stBenar;
      accSalah += stSalah;
      accKosong += stKosong;
      accTotalSoal += stQuestions.length;

      // Kalkulasi nilai akhir subtest, maxScore, dan Passing Grade
      int maxScore = 100;
      int? passingGrade;
      bool passed = true;
      String predikat = '';

      if (isSKD) {
        if (isTwk) {
          maxScore = stQuestions.isNotEmpty ? stQuestions.length * 5 : 150;
          passingGrade = 65;
        } else if (isTiu) {
          maxScore = stQuestions.isNotEmpty ? stQuestions.length * 5 : 175;
          passingGrade = 80;
        } else if (isTkp) {
          maxScore = stQuestions.isNotEmpty ? stQuestions.length * 5 : 225;
          passingGrade = 166;
        } else {
          maxScore = stQuestions.length * 5;
          passingGrade = (maxScore * 0.65).round();
        }

        passed = stScore >= passingGrade;
        predikat = passed ? 'Lulus PG' : 'Belum Lulus PG';
      } else if (isSNBT) {
        // Skala UTBK Nasional: 0 - 1000
        maxScore = 1000;
        stScore = stQuestions.isNotEmpty ? ((stBenar / stQuestions.length) * 1000).round() : 0;
        passingGrade = ((customPassingPercentage ?? 65) * 10);
        passed = stScore >= passingGrade;

        if (stScore >= 800) {
          predikat = 'Sangat Memuaskan';
        } else if (stScore >= 650) {
          predikat = 'Baik';
        } else if (stScore >= 500) {
          predikat = 'Cukup';
        } else {
          predikat = 'Perlu Latihan';
        }
      } else if (isTKA) {
        // Skala Akademik Nasional: 0 - 100
        maxScore = 100;
        stScore = stQuestions.isNotEmpty ? ((stBenar / stQuestions.length) * 100).round() : 0;
        passingGrade = customPassingPercentage ?? 65;
        passed = stScore >= passingGrade;

        if (stScore >= 90) {
          predikat = 'Istimewa';
        } else if (stScore >= 75) {
          predikat = 'Baik';
        } else if (stScore >= 60) {
          predikat = 'Memadai';
        } else {
          predikat = 'Kurang';
        }
      } else {
        // UMUM / Standar 0 - 100
        maxScore = 100;
        stScore = stQuestions.isNotEmpty ? ((stBenar / stQuestions.length) * 100).round() : 0;
        passingGrade = customPassingPercentage ?? 65;
        passed = stScore >= passingGrade;
        predikat = passed ? 'Tuntas' : 'Belum Tuntas';
      }

      evaluatedSubtests[st.subtestId] = SubtestEvaluation(
        subtestId: st.subtestId,
        judul: stJudul,
        benar: stBenar,
        salah: stSalah,
        kosong: stKosong,
        total: stQuestions.length,
        skor: stScore,
        maxSkor: maxScore,
        passingGrade: passingGrade,
        isPassed: passed,
        predikat: predikat,
        isTkp: isTkp,
      );
    }

    // ─── Kalkulasi Nilai Akhir & Kelulusan Total ──────────────────
    int finalScore = 0;
    int maxTotalScore = 100;
    bool isOverallPassed = true;
    String statusKelulusan = '';
    String overallPredikat = '';

    if (isSKD) {
      // SKD: Akumulasi total skor dari seluruh subtest (Maks 550)
      finalScore = evaluatedSubtests.values.fold(0, (sum, st) => sum + st.skor);
      maxTotalScore = evaluatedSubtests.values.fold(0, (sum, st) => sum + st.maxSkor);
      if (maxTotalScore == 0) maxTotalScore = 550;

      // Syarat kelulusan SKD: SEMUA subtest harus mencapai/melampaui Passing Grade
      isOverallPassed = evaluatedSubtests.values.every((st) => st.isPassed);
      statusKelulusan = isOverallPassed
          ? 'MEMENUHI NILAI AMBANG BATAS (LULUS)'
          : 'BELUM MEMENUHI AMBANG BATAS (TIDAK LULUS)';

      if (isOverallPassed) {
        if (finalScore >= 450) {
          overallPredikat = 'Istimewa / Sangat Tinggi';
        } else if (finalScore >= 400) {
          overallPredikat = 'Tinggi';
        } else {
          overallPredikat = 'Memenuhi Standar';
        }
      } else {
        overallPredikat = 'Perlu Peningkatan';
      }
    } else if (isSNBT) {
      // SNBT: Rata-rata dari nilai-nilai subtes skala 1000
      maxTotalScore = 1000;
      if (evaluatedSubtests.isNotEmpty) {
        final sum = evaluatedSubtests.values.fold(0, (acc, st) => acc + st.skor);
        finalScore = (sum / evaluatedSubtests.length).round();
      }
      final targetPG = ((customPassingPercentage ?? 65) * 10);
      isOverallPassed = finalScore >= targetPG;
      statusKelulusan = isOverallPassed
          ? 'LULUS TARGET AMBANG BATAS UTBK'
          : 'BELUM MENCAPAI TARGET UTBK';

      if (finalScore >= 800) {
        overallPredikat = 'Sangat Memuaskan';
      } else if (finalScore >= 650) {
        overallPredikat = 'Baik';
      } else if (finalScore >= 500) {
        overallPredikat = 'Cukup';
      } else {
        overallPredikat = 'Perlu Peningkatan';
      }
    } else {
      // TKA & UMUM: Rata-rata dari nilai-nilai subtes skala 100
      maxTotalScore = 100;
      if (evaluatedSubtests.isNotEmpty) {
        final sum = evaluatedSubtests.values.fold(0, (acc, st) => acc + st.skor);
        finalScore = (sum / evaluatedSubtests.length).round();
      } else if (accTotalSoal > 0) {
        finalScore = ((accBenar / accTotalSoal) * 100).round();
      }

      final pg = customPassingPercentage ?? 65;
      isOverallPassed = finalScore >= pg;
      statusKelulusan = isOverallPassed
          ? 'LULUS (MEMENUHI KKM)'
          : 'BELUM MEMENUHI KKM';

      if (finalScore >= 90) {
        overallPredikat = 'Istimewa';
      } else if (finalScore >= 75) {
        overallPredikat = 'Baik';
      } else if (finalScore >= 60) {
        overallPredikat = 'Memadai';
      } else {
        overallPredikat = 'Kurang';
      }
    }

    return ExamEvaluationResult(
      finalScore: finalScore,
      maxScore: maxTotalScore,
      totalBenar: accBenar,
      totalSalah: accSalah,
      totalKosong: accKosong,
      totalSoal: accTotalSoal,
      isPassed: isOverallPassed,
      statusKelulusan: statusKelulusan,
      predikat: overallPredikat,
      category: category,
      subtests: evaluatedSubtests,
    );
  }
}
