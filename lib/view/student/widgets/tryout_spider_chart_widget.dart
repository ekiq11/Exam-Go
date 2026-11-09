import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/exam_question_model.dart';
import '../../../services/student_tryout_history_service.dart';

/// Model item skor per subtest untuk grafik radar / spider chart
class TryoutSubScore {
  final String name;
  final double score; // 0..100 (persentase visualisasi)
  final double maxValue;
  final int totalSoal;
  final int totalBenar;
  final Color color;
  final int? rawScore; // Nilai / skor riil subtest (misal TWK 110, PU 750)
  final int?
  maxRawScore; // Nilai maksimum riil subtest (misal TWK 150, PU 1000)

  const TryoutSubScore({
    required this.name,
    required this.score,
    this.maxValue = 100.0,
    this.totalSoal = 0,
    this.totalBenar = 0,
    required this.color,
    this.rawScore,
    this.maxRawScore,
  });

  /// Daftar nama subtest standar berdasarkan kategori paket tryout
  static List<String> getStandardSubtestNames(String kategori) {
    final cat = kategori.trim().toUpperCase();
    if (cat.contains('SKD') ||
        cat.contains('KEDINASAN') ||
        cat.contains('CPNS')) {
      return ['TWK', 'TIU', 'TKP'];
    }
    if (cat.contains('SNBT') || cat.contains('UTBK')) {
      return ['PU', 'PK', 'PBM', 'LBI', 'LBE', 'PM', 'PPU'];
    }
    if (cat.contains('SMA') || cat.contains('TKA')) {
      return ['Matematika', 'B. Indonesia', 'B. Inggris', 'Sains/Soshum'];
    }
    if (cat.contains('SMP') || cat.contains('MTS')) {
      return ['Matematika', 'IPA', 'B. Indonesia', 'B. Inggris'];
    }
    if (cat.contains('SD') || cat.contains('MI')) {
      return ['Matematika', 'B. Indonesia', 'IPAS'];
    }
    return ['Subtest 1', 'Subtest 2', 'Subtest 3'];
  }

  /// Memetakan key teknis (ST1, ST2) atau judul panjang ke nama singkat subtest
  static String resolveSubtestName(String rawKey, int index, String kategori) {
    final k = rawKey.trim();
    final matchParen = RegExp(r'\(([^)]+)\)').firstMatch(k);
    if (matchParen != null && matchParen.group(1) != null) {
      final inner = matchParen.group(1)!.trim();
      if (inner.isNotEmpty && inner.length <= 6) return inner;
    }

    final matchSt = RegExp(
      r'^(?:ST|SUBTEST|SUB)[_-]?(\d+)$',
      caseSensitive: false,
    ).firstMatch(k);
    if (matchSt != null) {
      final idx = int.tryParse(matchSt.group(1) ?? '') ?? (index + 1);
      final std = getStandardSubtestNames(kategori);
      if (idx >= 1 && idx <= std.length) {
        return std[idx - 1];
      }
    }

    final lower = k.toLowerCase();
    if (lower.contains('wawasan kebangsaan') || lower == 'twk') return 'TWK';
    if (lower.contains('intelegensia') ||
        lower.contains('intelegensi') ||
        lower == 'tiu') {
      return 'TIU';
    }
    if (lower.contains('karakteristik pribadi') || lower == 'tkp') return 'TKP';
    if (lower.contains('penalaran umum') || lower == 'pu') return 'PU';
    if (lower.contains('pengetahuan kuantitatif') || lower == 'pk') return 'PK';
    if (lower.contains('pemahaman bacaan') || lower == 'pbm') return 'PBM';
    if (lower.contains('pemahaman umum') || lower == 'ppu') return 'PPU';
    if (lower.contains('penalaran matematika') || lower == 'pm') return 'PM';
    if (lower.contains('bahasa indonesia') || lower == 'lbi') return 'LBI';
    if (lower.contains('bahasa inggris') || lower == 'lbe') return 'LBE';

    return _formatSubtestLabel(k);
  }

  /// Parsing data `subtest_scores` riil dari Firestore / evaluasi ujian
  static List<TryoutSubScore> _parseSubtestScoresMap(
    Map<String, dynamic> map,
    String kategori,
  ) {
    if (map.isEmpty) return [];
    final colors = _palette;
    int colIdx = 0;
    final List<TryoutSubScore> result = [];

    final sortedEntries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final val = entry.value;
      if (val is! Map) continue;

      final m = Map<String, dynamic>.from(val);
      final judul = (m['judul'] ?? m['nama'] ?? entry.key).toString();
      final name = resolveSubtestName(
        judul.isNotEmpty ? judul : entry.key,
        i,
        kategori,
      );

      final rawSkor = (m['skor'] as num?)?.toInt() ?? 0;
      final maxSkor = (m['max_skor'] as num?)?.toInt() ?? 0;
      final benar = (m['benar'] as num?)?.toInt() ?? 0;
      final total = (m['total'] as num?)?.toInt() ?? 0;

      double pct = 0.0;
      if (maxSkor > 0) {
        pct = (rawSkor / maxSkor) * 100.0;
      } else if (total > 0) {
        pct = (benar / total) * 100.0;
      }

      result.add(
        TryoutSubScore(
          name: name,
          score: pct.clamp(0.0, 100.0),
          maxValue: 100.0,
          rawScore: rawSkor,
          maxRawScore: maxSkor > 0 ? maxSkor : (total > 0 ? total : 100),
          totalBenar: benar,
          totalSoal: total,
          color: colors[colIdx % colors.length],
        ),
      );
      colIdx++;
    }

    if (result.length < 3 && result.isNotEmpty) {
      final existingNames = result.map((r) => r.name.toUpperCase()).toSet();
      final std = getStandardSubtestNames(kategori);
      for (final sName in std) {
        if (!existingNames.contains(sName.toUpperCase())) {
          result.add(
            TryoutSubScore(
              name: sName,
              score: 0.0,
              maxValue: 100.0,
              rawScore: 0,
              maxRawScore: 100,
              totalBenar: 0,
              totalSoal: 0,
              color: colors[colIdx % colors.length],
            ),
          );
          colIdx++;
          if (result.length >= 3) break;
        }
      }
    }

    return result;
  }

  /// Factory untuk menghitung subscore dari 1 sesi riwayat ujian
  static List<TryoutSubScore> fromHistoryItem(StudentTryoutHistoryItem item) {
    // 1. Prioritaskan nilai per subtest riil dari Firestore
    if (item.subtestScores != null && item.subtestScores!.isNotEmpty) {
      final parsed = _parseSubtestScoresMap(item.subtestScores!, item.kategori);
      if (parsed.isNotEmpty) return parsed;
    }

    // 2. Evaluasi berdasarkan butir soal yang tersimpan
    if (item.questions.isNotEmpty) {
      final parsed = fromQuestions(
        questions: item.questions,
        studentAnswers: item.jawaban,
        kategori: item.kategori,
        score: item.finalScore,
        maxScore: item.maxScore,
        subtestScores: item.subtestScores,
      );
      if (parsed.isNotEmpty) return parsed;
    }

    // 3. Fallback adaptif subtest standar per kategori
    return _generateAdaptiveScores(item, {});
  }

  /// Factory untuk menghitung subscore langsung dari daftar soal dan jawaban siswa
  static List<TryoutSubScore> fromQuestions({
    required List<ExamQuestion> questions,
    required Map<String, String> studentAnswers,
    String kategori = 'Umum',
    int? score,
    int? maxScore,
    Map<String, dynamic>? subtestScores,
  }) {
    if (subtestScores != null && subtestScores.isNotEmpty) {
      final parsed = _parseSubtestScoresMap(subtestScores, kategori);
      if (parsed.isNotEmpty) return parsed;
    }

    if (questions.isEmpty) return [];

    final Map<String, List<ExamQuestion>> grouped = {};
    for (final q in questions) {
      final key = (q.subtestId.isNotEmpty ? q.subtestId : 'Umum').trim();
      grouped.putIfAbsent(key, () => []).add(q);
    }

    final colors = _palette;
    int colIdx = 0;
    final List<TryoutSubScore> result = [];

    grouped.forEach((subtestKey, qList) {
      int benar = 0;
      for (final q in qList) {
        final userAns = (studentAnswers[q.soalId] ?? '').trim().toUpperCase();
        final keyAns = q.kunci.trim().toUpperCase();
        if (userAns.isNotEmpty && userAns == keyAns) {
          benar++;
        }
      }
      final total = qList.length;
      final pct = total > 0 ? ((benar / total) * 100.0) : 0.0;
      final resolvedName = resolveSubtestName(subtestKey, colIdx, kategori);

      result.add(
        TryoutSubScore(
          name: resolvedName,
          score: pct.clamp(0.0, 100.0),
          maxValue: 100.0,
          rawScore: benar,
          maxRawScore: total,
          totalSoal: total,
          totalBenar: benar,
          color: colors[colIdx % colors.length],
        ),
      );
      colIdx++;
    });

    if (result.length < 3) {
      final existingNames = result.map((r) => r.name.toUpperCase()).toSet();
      final std = getStandardSubtestNames(kategori);
      for (final sName in std) {
        if (!existingNames.contains(sName.toUpperCase())) {
          result.add(
            TryoutSubScore(
              name: sName,
              score: 0.0,
              maxValue: 100.0,
              rawScore: 0,
              maxRawScore: 100,
              totalBenar: 0,
              totalSoal: 0,
              color: colors[colIdx % colors.length],
            ),
          );
          colIdx++;
          if (result.length >= 3) break;
        }
      }
    }

    return result;
  }

  /// Factory untuk menghitung radar kumulatif dari seluruh riwayat tryout siswa
  static List<TryoutSubScore> fromCumulativeHistory(
    List<StudentTryoutHistoryItem> list,
  ) {
    if (list.isEmpty) return [];

    final Map<String, _SubtestAccumulator> accum = {};

    for (final item in list) {
      if (item.subtestScores != null && item.subtestScores!.isNotEmpty) {
        int idx = 0;
        item.subtestScores!.forEach((k, v) {
          if (v is Map) {
            final m = Map<String, dynamic>.from(v);
            final title = (m['judul'] ?? m['nama'] ?? k).toString();
            final name = resolveSubtestName(title, idx, item.kategori);
            final acc = accum.putIfAbsent(name, () => _SubtestAccumulator());
            acc.skorSum += (m['skor'] as num?)?.toInt() ?? 0;
            acc.maxSkorSum += (m['max_skor'] as num?)?.toInt() ?? 0;
            acc.benarSum += (m['benar'] as num?)?.toInt() ?? 0;
            acc.totalSum += (m['total'] as num?)?.toInt() ?? 0;
            idx++;
          }
        });
      } else if (item.questions.isNotEmpty) {
        int idx = 0;
        final Map<String, List<ExamQuestion>> qGroup = {};
        for (final q in item.questions) {
          final k = (q.subtestId.isNotEmpty ? q.subtestId : item.kategori)
              .trim();
          qGroup.putIfAbsent(k, () => []).add(q);
        }
        qGroup.forEach((k, qList) {
          final name = resolveSubtestName(k, idx, item.kategori);
          final acc = accum.putIfAbsent(name, () => _SubtestAccumulator());
          for (final q in qList) {
            acc.totalSum++;
            final studentAns = (item.jawaban[q.soalId] ?? '')
                .trim()
                .toUpperCase();
            if (studentAns.isNotEmpty &&
                studentAns == q.kunci.trim().toUpperCase()) {
              acc.benarSum++;
            }
          }
          acc.skorSum = acc.benarSum;
          acc.maxSkorSum = acc.totalSum;
          idx++;
        });
      } else {
        final std = getStandardSubtestNames(item.kategori);
        for (final sName in std) {
          final acc = accum.putIfAbsent(sName, () => _SubtestAccumulator());
          final subTotal = (item.totalSoal / std.length).ceil();
          final subBenar = (item.totalBenar / std.length).round();
          acc.totalSum += subTotal > 0 ? subTotal : 5;
          acc.benarSum += subBenar;
          acc.skorSum = acc.benarSum;
          acc.maxSkorSum = acc.totalSum;
        }
      }
    }

    final colors = _palette;
    int colIdx = 0;
    final List<TryoutSubScore> result = [];

    accum.forEach((name, acc) {
      double pct = 0.0;
      if (acc.maxSkorSum > 0) {
        pct = (acc.skorSum / acc.maxSkorSum) * 100.0;
      } else if (acc.totalSum > 0) {
        pct = (acc.benarSum / acc.totalSum) * 100.0;
      }
      result.add(
        TryoutSubScore(
          name: name,
          score: pct.clamp(0.0, 100.0),
          maxValue: 100.0,
          rawScore: acc.skorSum > 0 ? acc.skorSum : acc.benarSum,
          maxRawScore: acc.maxSkorSum > 0 ? acc.maxSkorSum : acc.totalSum,
          totalSoal: acc.totalSum,
          totalBenar: acc.benarSum,
          color: colors[colIdx % colors.length],
        ),
      );
      colIdx++;
    });

    if (result.length < 3) {
      final std = getStandardSubtestNames(list.first.kategori);
      for (final sName in std) {
        if (!accum.containsKey(sName)) {
          result.add(
            TryoutSubScore(
              name: sName,
              score: 0.0,
              maxValue: 100.0,
              rawScore: 0,
              maxRawScore: 100,
              color: colors[colIdx % colors.length],
            ),
          );
          colIdx++;
          if (result.length >= 3) break;
        }
      }
    }

    return result;
  }

  static String _formatSubtestLabel(String raw) {
    var clean = raw.replaceAll(RegExp(r'[_-]'), ' ').trim();
    if (clean.length > 12) {
      // Ambil akronim atau 10 huruf pertama
      final words = clean.split(' ');
      if (words.length >= 2) {
        return words.map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
      }
      return '${clean.substring(0, 10)}.';
    }
    return clean;
  }

  static List<TryoutSubScore> _generateAdaptiveScores(
    StudentTryoutHistoryItem item,
    Map<String, List<ExamQuestion>> grouped,
  ) {
    final total = item.totalSoal > 0 ? item.totalSoal : 10;
    final benarPct = total > 0 ? (item.totalBenar / total) * 100.0 : 0.0;
    final akurasi = (item.totalBenar + item.totalSalah) > 0
        ? (item.totalBenar / (item.totalBenar + item.totalSalah)) * 100.0
        : 0.0;
    final kelengkapan = total > 0
        ? ((total - item.totalKosong) / total) * 100.0
        : 0.0;

    return [
      TryoutSubScore(
        name: 'Ketepatan',
        score: benarPct.clamp(0.0, 100.0),
        color: const Color(0xFF10B981), // Emerald
        totalSoal: total,
        totalBenar: item.totalBenar,
      ),
      TryoutSubScore(
        name: 'Akurasi',
        score: akurasi.clamp(0.0, 100.0),
        color: const Color(0xFF3B82F6), // Blue
        totalSoal: item.totalBenar + item.totalSalah,
        totalBenar: item.totalBenar,
      ),
      TryoutSubScore(
        name: 'Ketuntasan',
        score: kelengkapan.clamp(0.0, 100.0),
        color: const Color(0xFF8B5CF6), // Purple
        totalSoal: total,
        totalBenar: total - item.totalKosong,
      ),
      if (item.kategori.isNotEmpty)
        TryoutSubScore(
          name: item.kategori,
          score:
              (item.finalScore.toDouble() /
                      (item.maxScore > 0 ? item.maxScore : 100.0) *
                      100.0)
                  .clamp(0.0, 100.0),
          color: const Color(0xFFF59E0B), // Amber
          totalSoal: total,
          totalBenar: item.totalBenar,
        ),
    ];
  }

  static const List<Color> _palette = [
    Color(0xFF10B981), // Emerald
    Color(0xFF3B82F6), // Blue
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFF59E0B), // Amber
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF97316), // Orange
    Color(0xFF6366F1), // Indigo
  ];
}

class _SubtestAccumulator {
  int totalSum = 0;
  int benarSum = 0;
  int skorSum = 0;
  int maxSkorSum = 0;
}

/// Widget Spider / Radar Chart Interaktif dengan Desain Fresh & Modern
class TryoutSpiderChartWidget extends StatefulWidget {
  final List<TryoutSubScore> subScores;
  final String title;
  final String? subtitle;
  final double height;
  final bool showLegend;

  const TryoutSpiderChartWidget({
    super.key,
    required this.subScores,
    this.title = 'Grafik Kemampuan',
    this.subtitle,
    this.height = 280,
    this.showLegend = true,
  });

  @override
  State<TryoutSpiderChartWidget> createState() =>
      _TryoutSpiderChartWidgetState();
}

class _TryoutSpiderChartWidgetState extends State<TryoutSpiderChartWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant TryoutSpiderChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subScores != widget.subScores) {
      _animCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subScores.isEmpty) {
      return const SizedBox.shrink();
    }

    final avgScore =
        widget.subScores.fold<double>(0.0, (acc, e) => acc + e.score) /
        widget.subScores.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.radar_rounded,
                            size: 18,
                            color: Color(0xFF059669),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Skor Rata-rata Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.speed_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${avgScore.round()}% Rata2',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Area Canvas Spider Chart
          AnimatedBuilder(
            animation: _anim,
            builder: (context, child) {
              return SizedBox(
                height: widget.height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SpiderChartPainter(
                    subScores: widget.subScores,
                    progress: _anim.value,
                  ),
                ),
              );
            },
          ),

          if (widget.showLegend) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            const SizedBox(height: 12),
            // Legend Item Grid/Wrap (Posisi Presisi di Tengah-Tengah)
            SizedBox(
              width: double.infinity,
              child: Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: widget.subScores.map((s) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: s.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: s.color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            s.name,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.rawScore != null
                                ? '${s.rawScore} (${s.score.round()}%)'
                                : '${s.score.round()}%',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: s.color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// CustomPainter untuk menggambar Polygon Radar Spider Chart
class _SpiderChartPainter extends CustomPainter {
  final List<TryoutSubScore> subScores;
  final double progress;

  const _SpiderChartPainter({required this.subScores, required this.progress});

  static const int _gridLevels = 5; // 20%, 40%, 60%, 80%, 100%

  @override
  void paint(Canvas canvas, Size size) {
    final n = subScores.length;
    if (n < 3) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (math.min(cx, cy) * 0.65).clamp(60.0, 115.0);
    final labelRadius = radius + 24;

    // Titik sudut lingkaran penuh (100%)
    final fullVerts = List.generate(n, (i) {
      final a = _angle(i, n);
      return Offset(cx + radius * math.cos(a), cy + radius * math.sin(a));
    });

    // Titik sudut data aktual disesuaikan persentase × progress animasi
    final dataVerts = List.generate(n, (i) {
      final s = subScores[i];
      final frac = (s.score.clamp(0.0, s.maxValue) / s.maxValue) * progress;
      final a = _angle(i, n);
      return Offset(
        cx + radius * frac * math.cos(a),
        cy + radius * frac * math.sin(a),
      );
    });

    // ── 1. Cincin Poligon Jaring-Jaring (Grid Rings) ──
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int g = 1; g <= _gridLevels; g++) {
      final r = radius * g / _gridLevels;
      final path = Path();
      for (int i = 0; i < n; i++) {
        final a = _angle(i, n);
        final pt = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Label persentase pada sumbu pertama (20%, 40%, 60%, 80%)
    const gridLabels = ['20%', '40%', '60%', '80%'];
    for (int g = 1; g <= _gridLevels - 1; g++) {
      final r = radius * g / _gridLevels;
      final a = _angle(0, n);
      final lx = cx + r * math.cos(a) + 4;
      final ly = cy + r * math.sin(a) - 7;
      final tp = TextPainter(
        text: TextSpan(
          text: gridLabels[g - 1],
          style: GoogleFonts.poppins(
            color: const Color(0xFF94A3B8),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(lx, ly));
    }

    // ── 2. Garis Jari-Jari (Spoke Lines) ──
    final spokePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 0.8;
    for (int i = 0; i < n; i++) {
      canvas.drawLine(Offset(cx, cy), fullVerts[i], spokePaint);
    }

    // ── 3. Irisan Poligon Segitiga Berwarna (Color Slices) ──
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final vi = dataVerts[i];
      final vj = dataVerts[j];

      final colI = subScores[i].color;
      final colJ = subScores[j].color;
      final sliceColor = Color.lerp(colI, colJ, 0.5) ?? colI;

      final slicePath = Path()
        ..moveTo(cx, cy)
        ..lineTo(vi.dx, vi.dy)
        ..lineTo(vj.dx, vj.dy)
        ..close();

      canvas.drawPath(
        slicePath,
        Paint()
          ..color = sliceColor.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
    }

    // ── 4. Garis Kontur Luar Data (Outer Polygon Stroke) ──
    final strokePath = Path();
    for (int i = 0; i < n; i++) {
      final v = dataVerts[i];
      if (i == 0) {
        strokePath.moveTo(v.dx, v.dy);
      } else {
        strokePath.lineTo(v.dx, v.dy);
      }
    }
    strokePath.close();

    canvas.drawPath(
      strokePath,
      Paint()
        ..color = const Color(0xFF0F766E).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round,
    );

    // ── 5. Node Titik Sudut dengan Glow & Inner White Circle ──
    for (int i = 0; i < n; i++) {
      final dv = dataVerts[i];
      final col = subScores[i].color;

      // Outer glow
      canvas.drawCircle(dv, 8, Paint()..color = col.withValues(alpha: 0.25));
      // White ring
      canvas.drawCircle(dv, 5.5, Paint()..color = Colors.white);
      // Colored center
      canvas.drawCircle(dv, 3.8, Paint()..color = col);
    }

    // ── 6. Teks Label Subtest & Nilai di Ujung Sumbu ──
    for (int i = 0; i < n; i++) {
      final a = _angle(i, n);
      final lx = cx + labelRadius * math.cos(a);
      final ly = cy + labelRadius * math.sin(a);
      final label = subScores[i].name;
      final scoreVal = (subScores[i].score * progress).round();
      final labelCol = subScores[i].color;

      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label\n',
              style: GoogleFonts.poppins(
                color: const Color(0xFF475569),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: subScores[i].rawScore != null
                  ? '${subScores[i].rawScore} ($scoreVal%)'
                  : '$scoreVal%',
              style: GoogleFonts.poppins(
                color: labelCol,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: 72);
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  double _angle(int i, int n) => (2 * math.pi * i / n) - (math.pi / 2);

  @override
  bool shouldRepaint(_SpiderChartPainter old) =>
      old.progress != progress || old.subScores != subScores;
}
