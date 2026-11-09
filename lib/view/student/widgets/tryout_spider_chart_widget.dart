import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/exam_question_model.dart';
import '../../../services/student_tryout_history_service.dart';

/// Model item skor per subtest untuk grafik radar / spider chart
class TryoutSubScore {
  final String name;
  final double score; // 0..100
  final double maxValue;
  final int totalSoal;
  final int totalBenar;
  final Color color;

  const TryoutSubScore({
    required this.name,
    required this.score,
    this.maxValue = 100.0,
    this.totalSoal = 0,
    this.totalBenar = 0,
    required this.color,
  });

  /// Factory untuk menghitung subscore dari 1 sesi riwayat ujian
  static List<TryoutSubScore> fromHistoryItem(StudentTryoutHistoryItem item) {
    if (item.questions.isEmpty) {
      return _generateFallbackScores(item);
    }

    // Kelompokkan soal berdasarkan subtestId atau jenis materi
    final Map<String, List<ExamQuestion>> grouped = {};
    for (final q in item.questions) {
      final key = (q.subtestId.isNotEmpty ? q.subtestId : 'Umum').trim();
      grouped.putIfAbsent(key, () => []).add(q);
    }

    // Jika subtest < 3, pecah atau lengkapi agar grafik spider memiliki minimal 3 sumbu
    if (grouped.length < 3) {
      return _generateAdaptiveScores(item, grouped);
    }

    final colors = _palette;
    int colIdx = 0;
    final List<TryoutSubScore> result = [];

    grouped.forEach((subtestName, questions) {
      int benar = 0;
      for (final q in questions) {
        final studentAns = (item.jawaban[q.soalId] ?? '').trim().toUpperCase();
        final keyAns = q.kunci.trim().toUpperCase();
        if (studentAns.isNotEmpty && studentAns == keyAns) {
          benar++;
        }
      }
      final total = questions.length;
      final pct = total > 0 ? ((benar / total) * 100.0) : 0.0;

      result.add(
        TryoutSubScore(
          name: _formatSubtestLabel(subtestName),
          score: pct.clamp(0.0, 100.0),
          maxValue: 100.0,
          totalSoal: total,
          totalBenar: benar,
          color: colors[colIdx % colors.length],
        ),
      );
      colIdx++;
    });

    return result;
  }

  /// Factory untuk menghitung subscore langsung dari daftar soal dan jawaban siswa
  static List<TryoutSubScore> fromQuestions({
    required List<ExamQuestion> questions,
    required Map<String, String> studentAnswers,
    String kategori = 'Umum',
    int? score,
    int? maxScore,
  }) {
    if (questions.isEmpty) return [];

    final Map<String, List<ExamQuestion>> grouped = {};
    for (final q in questions) {
      final key = (q.subtestId.isNotEmpty ? q.subtestId : 'Umum').trim();
      grouped.putIfAbsent(key, () => []).add(q);
    }

    int totalBenar = 0;
    int totalSalah = 0;
    int totalKosong = 0;

    for (final q in questions) {
      final userAns = (studentAnswers[q.soalId] ?? '').trim().toUpperCase();
      final keyAns = q.kunci.trim().toUpperCase();
      if (userAns.isEmpty) {
        totalKosong++;
      } else if (userAns == keyAns) {
        totalBenar++;
      } else {
        totalSalah++;
      }
    }

    if (grouped.length < 3) {
      final total = questions.length;
      final benarPct = total > 0 ? (totalBenar / total) * 100.0 : 0.0;
      final akurasi = (totalBenar + totalSalah) > 0
          ? (totalBenar / (totalBenar + totalSalah)) * 100.0
          : 0.0;
      final kelengkapan = total > 0 ? ((total - totalKosong) / total) * 100.0 : 0.0;
      final effectiveScore = (score != null && maxScore != null && maxScore > 0)
          ? ((score.toDouble() / maxScore) * 100.0).clamp(0.0, 100.0)
          : benarPct;

      return [
        TryoutSubScore(
          name: 'Ketepatan',
          score: benarPct.clamp(0.0, 100.0),
          color: const Color(0xFF10B981),
          totalSoal: total,
          totalBenar: totalBenar,
        ),
        TryoutSubScore(
          name: 'Akurasi',
          score: akurasi.clamp(0.0, 100.0),
          color: const Color(0xFF3B82F6),
          totalSoal: totalBenar + totalSalah,
          totalBenar: totalBenar,
        ),
        TryoutSubScore(
          name: 'Ketuntasan',
          score: kelengkapan.clamp(0.0, 100.0),
          color: const Color(0xFF8B5CF6),
          totalSoal: total,
          totalBenar: total - totalKosong,
        ),
        if (kategori.isNotEmpty)
          TryoutSubScore(
            name: kategori,
            score: effectiveScore.clamp(0.0, 100.0),
            color: const Color(0xFFF59E0B),
            totalSoal: total,
            totalBenar: totalBenar,
          ),
      ];
    }

    final colors = _palette;
    int colIdx = 0;
    final List<TryoutSubScore> result = [];

    grouped.forEach((subtestName, qList) {
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

      result.add(
        TryoutSubScore(
          name: _formatSubtestLabel(subtestName),
          score: pct.clamp(0.0, 100.0),
          maxValue: 100.0,
          totalSoal: total,
          totalBenar: benar,
          color: colors[colIdx % colors.length],
        ),
      );
      colIdx++;
    });

    return result;
  }

  /// Factory untuk menghitung radar kumulatif dari seluruh riwayat tryout siswa
  static List<TryoutSubScore> fromCumulativeHistory(List<StudentTryoutHistoryItem> list) {
    if (list.isEmpty) return [];

    final Map<String, _AggScore> agg = {};
    for (final item in list) {
      if (item.questions.isNotEmpty) {
        for (final q in item.questions) {
          final key = (q.subtestId.isNotEmpty ? q.subtestId : item.kategori).trim();
          agg.putIfAbsent(key, () => _AggScore());
          agg[key]!.total++;
          final studentAns = (item.jawaban[q.soalId] ?? '').trim().toUpperCase();
          if (studentAns.isNotEmpty && studentAns == q.kunci.trim().toUpperCase()) {
            agg[key]!.benar++;
          }
        }
      } else {
        // Fallback berdasarkan kategori paket jika butir soal tidak tersimpan
        final key = item.kategori.trim();
        agg.putIfAbsent(key, () => _AggScore());
        agg[key]!.total += item.totalSoal > 0 ? item.totalSoal : 10;
        agg[key]!.benar += item.totalBenar;
      }
    }

    if (agg.length < 3) {
      // Buat default metrik jika kategori sedikit
      return _generateCumulativeFallback(list);
    }

    final colors = _palette;
    int colIdx = 0;
    final List<TryoutSubScore> result = [];

    agg.forEach((key, val) {
      final pct = val.total > 0 ? ((val.benar / val.total) * 100.0) : 0.0;
      result.add(
        TryoutSubScore(
          name: _formatSubtestLabel(key),
          score: pct.clamp(0.0, 100.0),
          maxValue: 100.0,
          totalSoal: val.total,
          totalBenar: val.benar,
          color: colors[colIdx % colors.length],
        ),
      );
      colIdx++;
    });

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
    final kelengkapan = total > 0 ? ((total - item.totalKosong) / total) * 100.0 : 0.0;

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
          score: (item.finalScore.toDouble() / (item.maxScore > 0 ? item.maxScore : 100.0) * 100.0).clamp(0.0, 100.0),
          color: const Color(0xFFF59E0B), // Amber
          totalSoal: total,
          totalBenar: item.totalBenar,
        ),
    ];
  }

  static List<TryoutSubScore> _generateFallbackScores(StudentTryoutHistoryItem item) {
    return _generateAdaptiveScores(item, {});
  }

  static List<TryoutSubScore> _generateCumulativeFallback(List<StudentTryoutHistoryItem> list) {
    int totalSoal = 0;
    int totalBenar = 0;
    int totalSalah = 0;
    int totalKosong = 0;

    for (final it in list) {
      totalSoal += it.totalSoal > 0 ? it.totalSoal : 1;
      totalBenar += it.totalBenar;
      totalSalah += it.totalSalah;
      totalKosong += it.totalKosong;
    }

    final pctBenar = totalSoal > 0 ? (totalBenar / totalSoal) * 100.0 : 0.0;
    final pctAkurasi = (totalBenar + totalSalah) > 0 ? (totalBenar / (totalBenar + totalSalah)) * 100.0 : 0.0;
    final pctTuntas = totalSoal > 0 ? ((totalSoal - totalKosong) / totalSoal) * 100.0 : 0.0;
    final lulusCount = list.where((e) => e.isPassed).length;
    final pctLulus = list.isNotEmpty ? (lulusCount / list.length) * 100.0 : 0.0;

    return [
      TryoutSubScore(
        name: 'Ketepatan',
        score: pctBenar.clamp(0.0, 100.0),
        color: const Color(0xFF10B981),
        totalSoal: totalSoal,
        totalBenar: totalBenar,
      ),
      TryoutSubScore(
        name: 'Akurasi',
        score: pctAkurasi.clamp(0.0, 100.0),
        color: const Color(0xFF3B82F6),
        totalSoal: totalBenar + totalSalah,
        totalBenar: totalBenar,
      ),
      TryoutSubScore(
        name: 'Ketuntasan',
        score: pctTuntas.clamp(0.0, 100.0),
        color: const Color(0xFF8B5CF6),
        totalSoal: totalSoal,
        totalBenar: totalSoal - totalKosong,
      ),
      TryoutSubScore(
        name: 'Kelulusan',
        score: pctLulus.clamp(0.0, 100.0),
        color: const Color(0xFFF59E0B),
        totalSoal: list.length,
        totalBenar: lulusCount,
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

class _AggScore {
  int total = 0;
  int benar = 0;
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
    this.title = 'Grafik Radar Kemampuan Subtest',
    this.subtitle,
    this.height = 280,
    this.showLegend = true,
  });

  @override
  State<TryoutSpiderChartWidget> createState() => _TryoutSpiderChartWidgetState();
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
    _anim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );
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

    final avgScore = widget.subScores.fold<double>(0.0, (acc, e) => acc + e.score) /
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
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    const Icon(Icons.speed_rounded, size: 12, color: Colors.white),
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
            // Legend Item Grid/Wrap
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: widget.subScores.map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: s.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                        '${s.score.round()}%',
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

  const _SpiderChartPainter({
    required this.subScores,
    required this.progress,
  });

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
      return Offset(cx + radius * frac * math.cos(a), cy + radius * frac * math.sin(a));
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
              text: '$scoreVal%',
              style: GoogleFonts.poppins(
                color: labelCol,
                fontSize: 11,
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
