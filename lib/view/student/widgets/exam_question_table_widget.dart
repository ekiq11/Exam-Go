import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/utils/math_widget_factory.dart';

/// Widget cerdas untuk merender konten 'tabel' dari data soal.
/// Secara otomatis mendeteksi apakah data berupa:
/// 1. Teks Bacaan / Wacana / Informasi / Paragraf -> dirender vertikal sebagai paragraf elegan (bukan tabel melebar)
/// 2. Tabel Data Numerik / Statistik sebenarnya -> dirender sebagai tabel rapi, responsif, & scrollable
class ExamQuestionTableWidget extends StatelessWidget {
  final String tabelStr;
  final double fontSizeScale;

  const ExamQuestionTableWidget({
    super.key,
    required this.tabelStr,
    this.fontSizeScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (tabelStr.trim().isEmpty) return const SizedBox.shrink();

    try {
      final rawRows = tabelStr.contains('===') ? tabelStr.split('===') : tabelStr.split(',/');
      final delim = tabelStr.contains('===') ? '|||' : '-';
      final List<List<String>> parsedRows = [];

      for (final r in rawRows) {
        if (r.trim().isEmpty) continue;
        final cells = r.split(delim);
        // Lepas kolom indeks jika format angka di sel pertama (1|||Bacaan, 2|||dst)
        if (cells.isNotEmpty && int.tryParse(cells[0].trim()) != null) {
          cells.removeAt(0);
        }
        final trimmed = cells.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        if (trimmed.isNotEmpty) parsedRows.add(trimmed);
      }

      if (parsedRows.isEmpty) return const SizedBox.shrink();

      // Deteksi apakah data adalah teks bacaan atau tabel data angka
      const passageKeywords = [
        'bacaan',
        'teks',
        'informasi',
        'pernyataan',
        'paragraf',
        'paragraph',
        'passage',
        'wacana',
        'cerita',
        'kutipan',
        'deskripsi',
        'narasi',
        'artikel',
        'studi kasus',
      ];

      final maxCols = parsedRows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      final hasLongText = parsedRows.any((r) => r.any((c) => c.length > 70));
      final headerMatches = parsedRows[0].any((c) =>
          passageKeywords.any((k) => c.toLowerCase().contains(k)));

      final isPassage = headerMatches || (hasLongText && maxCols <= 2);

      if (isPassage) {
        return _buildPassageCard(parsedRows);
      } else {
        return _buildDataTable(parsedRows);
      }
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  /// Merender teks bacaan dalam bentuk kartu editorial vertikal (paragraf ke bawah)
  Widget _buildPassageCard(List<List<String>> parsedRows) {
    String title = 'BACAAN / INFORMASI SOAL';
    List<List<String>> bodyRows = parsedRows;

    // Cek apakah baris pertama adalah judul/label bacaan
    const passageKeywords = [
      'bacaan',
      'teks',
      'informasi',
      'pernyataan',
      'paragraf',
      'paragraph',
      'passage',
      'wacana',
      'cerita',
      'kutipan',
    ];

    if (parsedRows.isNotEmpty) {
      final firstRowJoined = parsedRows[0].join(' ').toLowerCase();
      final isHeaderRow = parsedRows.length > 1 &&
          (parsedRows[0].any((c) => passageKeywords.any((k) => c.toLowerCase().contains(k))) ||
              parsedRows[0].first.length <= 40);

      if (isHeaderRow && firstRowJoined.isNotEmpty) {
        title = parsedRows[0].join(' • ');
        bodyRows = parsedRows.sublist(1);
      }
    }

    final paragraphWidgets = <Widget>[];

    for (int i = 0; i < bodyRows.length; i++) {
      final row = bodyRows[i];
      if (row.isEmpty) continue;

      if (row.length == 1) {
        final text = row[0];
        // Cek jika teks pendek di baris tersendiri yang berperan sebagai sub-judul (misal: "WAYANG", "TEKS 1")
        final isShortTitle = text.length <= 35 &&
            (text == text.toUpperCase() || !text.contains('.'));

        if (isShortTitle && i == 0 && title == 'BACAAN / INFORMASI SOAL') {
          title = text;
          continue;
        }

        if (isShortTitle) {
          paragraphWidgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 13.5 * fontSizeScale,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          );
        } else {
          paragraphWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: HtmlWidget(
                MathHtmlFormatter.format(text),
                textStyle: GoogleFonts.poppins(
                  fontSize: 13 * fontSizeScale,
                  color: const Color(0xFF1E293B),
                  height: 1.65,
                ),
                factoryBuilder: () => MathWidgetFactory(fontSize: 13 * fontSizeScale),
              ),
            ),
          );
        }
      } else {
        // Format multi-kolom (misal: ["Paragraph 1", "Over this decade..."])
        final label = row[0];
        final content = row.sublist(1).join(' ');

        paragraphWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 11 * fontSizeScale,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF065F46),
                      ),
                    ),
                  ),
                HtmlWidget(
                  MathHtmlFormatter.format(content),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 13 * fontSizeScale,
                    color: const Color(0xFF1E293B),
                    height: 1.65,
                  ),
                  factoryBuilder: () => MathWidgetFactory(fontSize: 13 * fontSizeScale),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Teks Bacaan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 15,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: const Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Isi Paragraf
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: paragraphWidgets,
            ),
          ),
        ],
      ),
    );
  }

  /// Merender tabel data angka / statistik sebenarnya secara rapi dan proporsional
  Widget _buildDataTable(List<List<String>> parsedRows) {
    final tableRows = <TableRow>[];

    for (int k = 0; k < parsedRows.length; k++) {
      final cells = parsedRows[k];
      final isHeader = k == 0;

      tableRows.add(TableRow(
        decoration: BoxDecoration(
          color: isHeader
              ? const Color(0xFFF1F5F9)
              : (k.isEven ? const Color(0xFFFAFAFA) : Colors.white),
        ),
        children: cells.map((cell) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: HtmlWidget(
              MathHtmlFormatter.format(cell.trim()),
              textStyle: GoogleFonts.poppins(
                fontSize: 12.5 * fontSizeScale,
                fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                color: const Color(0xFF1E293B),
              ),
              factoryBuilder: () =>
                  MathWidgetFactory(fontSize: 12.5 * fontSizeScale),
            ),
          );
        }).toList(),
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320),
          child: Table(
            border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: tableRows,
          ),
        ),
      ),
    );
  }
}
