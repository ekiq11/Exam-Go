import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/exam_question_model.dart';
import '../../utils/math_widget_factory.dart';

/// Layar pembahasan dan kunci jawaban tryout lengkap dengan rendering LaTeX
class TryoutDiscussionScreen extends StatefulWidget {
  final String title;
  final String kategori;
  final List<ExamQuestion> questions;
  final Map<String, String> studentAnswers;
  final int? score;
  final String? statusKelulusan;

  const TryoutDiscussionScreen({
    super.key,
    required this.title,
    required this.kategori,
    required this.questions,
    required this.studentAnswers,
    this.score,
    this.statusKelulusan,
  });

  @override
  State<TryoutDiscussionScreen> createState() => _TryoutDiscussionScreenState();
}

class _TryoutDiscussionScreenState extends State<TryoutDiscussionScreen> {
  String _filter = 'Semua'; // 'Semua', 'Salah', 'Benar', 'Kosong'
  int _currentIndex = 0;
  final ScrollController _chipScrollCtrl = ScrollController();

  List<ExamQuestion> get _filteredQuestions {
    if (_filter == 'Semua') return widget.questions;
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      final correctAns = q.kunci.toUpperCase();
      if (_filter == 'Benar') return userAns.isNotEmpty && userAns == correctAns;
      if (_filter == 'Salah') return userAns.isNotEmpty && userAns != correctAns;
      if (_filter == 'Kosong') return userAns.isEmpty;
      return true;
    }).toList();
  }

  int get _countBenar {
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      return userAns.isNotEmpty && userAns == q.kunci.toUpperCase();
    }).length;
  }

  int get _countSalah {
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      return userAns.isNotEmpty && userAns != q.kunci.toUpperCase();
    }).length;
  }

  int get _countKosong {
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      return userAns.isEmpty;
    }).length;
  }

  @override
  void dispose() {
    _chipScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredQuestions;
    if (_currentIndex >= filtered.length && filtered.isNotEmpty) {
      _currentIndex = 0;
    }

    final currentQ = filtered.isNotEmpty ? filtered[_currentIndex] : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pembahasan & Kunci',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            Text(
              widget.title,
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F766E),
        elevation: 0,
        actions: [
          if (widget.score != null)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Skor: ${widget.score}',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Ringkasan Statistik
          _buildSummaryBar(),

          // Filter Chips
          _buildFilterChips(),

          // Nomor Soal Indicator Horizontal Strip
          if (filtered.isNotEmpty) _buildNumberSelector(filtered),

          // Main Question Card & Options & Pembahasan
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyFilteredState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: _buildQuestionDetailCard(currentQ!, _currentIndex + 1, filtered.length),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF134E4A),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatPill('Total', '${widget.questions.length}', Colors.white),
          _buildStatPill('Benar', '$_countBenar', const Color(0xFF4ADE80)),
          _buildStatPill('Salah', '$_countSalah', const Color(0xFFF87171)),
          _buildStatPill('Kosong', '$_countKosong', const Color(0xFFCBD5E1)),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withValues(alpha: 0.75)),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Semua', 'Salah', 'Benar', 'Kosong'];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final f = filters[idx];
          final isSelected = _filter == f;
          return ChoiceChip(
            label: Text(
              f,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            selected: isSelected,
            selectedColor: const Color(0xFF0F766E),
            backgroundColor: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onSelected: (_) {
              setState(() {
                _filter = f;
                _currentIndex = 0;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildNumberSelector(List<ExamQuestion> list) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListView.separated(
        controller: _chipScrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final q = list[i];
          final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
          final isCorrect = userAns.isNotEmpty && userAns == q.kunci.toUpperCase();
          final isWrong = userAns.isNotEmpty && userAns != q.kunci.toUpperCase();
          final isSelected = i == _currentIndex;

          Color bg;
          Color textCol;
          if (isCorrect) {
            bg = const Color(0xFFDCFCE7);
            textCol = const Color(0xFF15803D);
          } else if (isWrong) {
            bg = const Color(0xFFFEE2E2);
            textCol = const Color(0xFFB91C1C);
          } else {
            bg = const Color(0xFFF1F5F9);
            textCol = const Color(0xFF64748B);
          }

          return GestureDetector(
            onTap: () => setState(() => _currentIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                '${q.nomorSoal}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textCol,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionDetailCard(ExamQuestion q, int displayNum, int totalFiltered) {
    final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
    final correctAns = q.kunci.toUpperCase();
    final isCorrect = userAns.isNotEmpty && userAns == correctAns;
    final isWrong = userAns.isNotEmpty && userAns != correctAns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Soal
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Soal No. ${q.nomorSoal}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? const Color(0xFFDCFCE7)
                          : (isWrong ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCorrect
                              ? Icons.check_circle_rounded
                              : (isWrong ? Icons.cancel_rounded : Icons.help_outline_rounded),
                          size: 14,
                          color: isCorrect
                              ? const Color(0xFF16A34A)
                              : (isWrong ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          userAns.isEmpty
                              ? 'Tidak Dijawab'
                              : (isCorrect ? 'Jawaban Benar ($userAns)' : 'Jawaban Salah ($userAns)'),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCorrect
                                ? const Color(0xFF15803D)
                                : (isWrong ? const Color(0xFFB91C1C) : const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Pertanyaan Teks
              HtmlWidget(
                MathHtmlFormatter.format(q.pertanyaan),
                factoryBuilder: () => MathWidgetFactory(fontSize: 14),
                textStyle: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF0F172A), height: 1.5),
              ),

              if (q.gambar.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    q.gambar,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Pilihan Jawaban A, B, C, D, E
        Text(
          'Pilihan Jawaban:',
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        ),
        const SizedBox(height: 8),

        ...['A', 'B', 'C', 'D', 'E'].map((opt) {
          final text = _getOptionText(q, opt);
          if (text.isEmpty && opt != 'A' && opt != 'B' && opt != 'C' && opt != 'D') {
            return const SizedBox.shrink();
          }

          final isKey = opt == correctAns;
          final isChosen = opt == userAns;

          Color borderColor;
          Color bgColor;
          if (isKey) {
            borderColor = const Color(0xFF16A34A);
            bgColor = const Color(0xFFF0FDF4);
          } else if (isChosen && !isKey) {
            borderColor = const Color(0xFFDC2626);
            bgColor = const Color(0xFFFEF2F2);
          } else {
            borderColor = const Color(0xFFE2E8F0);
            bgColor = Colors.white;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: (isKey || isChosen) ? 1.5 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isKey
                        ? const Color(0xFF16A34A)
                        : (isChosen ? const Color(0xFFDC2626) : const Color(0xFFF1F5F9)),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    opt,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: (isKey || isChosen) ? Colors.white : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HtmlWidget(
                    MathHtmlFormatter.format(text),
                    factoryBuilder: () => MathWidgetFactory(fontSize: 13),
                    textStyle: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1E293B)),
                  ),
                ),
                if (isKey)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'KUNCI',
                      style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                    ),
                  ),
                if (isChosen && !isKey)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'PILIHANMU',
                      style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFFB91C1C)),
                    ),
                  ),
              ],
            ),
          );
        }),

        const SizedBox(height: 14),

        // Kotak Pembahasan Lengkap
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb_rounded, color: Color(0xFF15803D), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Pembahasan Soal',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF166534),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Kunci: $correctAns',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (q.pembahasan.isNotEmpty)
                HtmlWidget(
                  MathHtmlFormatter.format(q.pembahasan),
                  factoryBuilder: () => MathWidgetFactory(fontSize: 13),
                  textStyle: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF14532D), height: 1.5),
                )
              else
                Text(
                  'Kunci jawaban yang benar adalah opsi $correctAns. Pembahasan teks belum disediakan untuk butir ini.',
                  style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF15803D), fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Navigasi Prev / Next
        Row(
          children: [
            if (_currentIndex > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentIndex--),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text('Sebelumnya', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    side: const BorderSide(color: Color(0xFF0F766E)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            if (_currentIndex > 0 && _currentIndex < totalFiltered - 1)
              const SizedBox(width: 12),
            if (_currentIndex < totalFiltered - 1)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _currentIndex++),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text('Berikutnya', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _getOptionText(ExamQuestion q, String opt) {
    switch (opt) {
      case 'A': return q.opsiA;
      case 'B': return q.opsiB;
      case 'C': return q.opsiC;
      case 'D': return q.opsiD;
      case 'E': return q.opsiE;
      default: return '';
    }
  }

  Widget _buildEmptyFilteredState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.filter_list_off_rounded, size: 40, color: Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text(
            'Tidak ada butir soal dengan status "$_filter"',
            style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
