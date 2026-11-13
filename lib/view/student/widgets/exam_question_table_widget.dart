import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/utils/math_widget_factory.dart';

/// Widget cerdas untuk merender konten 'tabel' dari data soal.
/// Secara otomatis mendeteksi apakah data berupa:
/// 1. Teks Bacaan / Wacana / Informasi / Paragraf -> dirender vertikal mengalir alami (bukan tabel melebar)
/// 2. Tabel Data Numerik / Statistik sebenarnya -> dirender sebagai tabel rapi, responsif, & scrollable
class ExamQuestionTableWidget extends StatelessWidget {
  final String tabelStr;
  final String? subtestJudul;
  final double fontSizeScale;

  const ExamQuestionTableWidget({
    super.key,
    required this.tabelStr,
    this.subtestJudul,
    this.fontSizeScale = 1.0,
  });

  /// Parsing serbaguna untuk berbagai format tabel:
  /// 1. HTML Table (dari WebGAS / DOCX / Google Form)
  /// 2. Markdown Table (| Kolom 1 | Kolom 2 |)
  /// 3. Delimiter Klasik (=== ||| atau ,/ -)
  static List<List<String>> parseTableRows(String tabelStr) {
    final List<List<String>> parsedRows = [];
    final trimmedStr = tabelStr.trim();
    if (trimmedStr.isEmpty) return parsedRows;

    // 1. Format HTML Table (misal <table ...><tr>...</tr></table>)
    if (trimmedStr.contains('<table') || trimmedStr.contains('<tr')) {
      final rowMatches = RegExp(r'<tr[^>]*>(.*?)<\/tr>', dotAll: true, caseSensitive: false)
          .allMatches(trimmedStr);
      for (final rMatch in rowMatches) {
        final rowContent = rMatch.group(1) ?? '';
        final cellMatches = RegExp(r'<(?:td|th)[^>]*>(.*?)<\/(?:td|th)>', dotAll: true, caseSensitive: false)
            .allMatches(rowContent);
        final cells = <String>[];
        for (final cMatch in cellMatches) {
          String cell = cMatch.group(1) ?? '';
          // Buang tag wrapper seperti <div class="..."> atau <p> jika ada
          cell = cell.replaceAll(RegExp(r'<\/?(?:div|p)[^>]*>', caseSensitive: false), ' ').trim();
          cells.add(cell);
        }
        if (cells.isNotEmpty) {
          parsedRows.add(cells);
        }
      }
      if (parsedRows.isNotEmpty) return parsedRows;
    }

    // 2. Format Markdown Table (| Kolom 1 | Kolom 2 |)
    if (trimmedStr.contains('|') && trimmedStr.contains('---')) {
      final lines = trimmedStr.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
          if (trimmed.contains('---')) continue; // Lewati garis pemisah header
          final parts = trimmed.split('|');
          if (parts.length > 2) {
            final cells = parts
                .sublist(1, parts.length - 1)
                .map((c) => c.trim())
                .toList();
            if (cells.isNotEmpty) {
              parsedRows.add(cells);
            }
          }
        }
      }
      if (parsedRows.isNotEmpty) return parsedRows;
    }

    // 3. Format Delimiter Klasik (=== ||| atau ,/ -)
    final rawRows = trimmedStr.contains('===') ? trimmedStr.split('===') : trimmedStr.split(',/');
    final delim = trimmedStr.contains('===') ? '|||' : '-';

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

    return parsedRows;
  }

  /// Deteksi apakah string tabel sebenarnya merupakan teks stimulus / bacaan
  static bool isReadingPassage(String tabelStr, {String? subtestJudul}) {
    if (tabelStr.trim().isEmpty) return false;

    // Subtest bacaan/literasi selalu mengalirkan tabel sebagai teks bacaan (bukan tabel angka)
    if (subtestJudul != null && subtestJudul.trim().isNotEmpty) {
      final s = subtestJudul.toLowerCase();
      if (s.contains('bacaan') ||
          s.contains('literasi') ||
          s.contains('bahasa') ||
          s.contains('pemahaman') ||
          s.contains('menulis') ||
          s.contains('reading') ||
          s.contains('english')) {
        return true;
      }
    }

    try {
      final parsedRows = parseTableRows(tabelStr);
      if (parsedRows.isEmpty) return false;

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
        'kalimat',
        'dialog',
        'percakapan',
      ];

      final maxCols = parsedRows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      final hasLongText = parsedRows.any((r) => r.any((c) => c.length > 60));
      final headerMatches = parsedRows[0].any((c) =>
          passageKeywords.any((k) => c.toLowerCase().contains(k)));

      return headerMatches || (hasLongText && maxCols <= 2);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (tabelStr.trim().isEmpty) return const SizedBox.shrink();

    try {
      final parsedRows = parseTableRows(tabelStr);
      if (parsedRows.isEmpty) return const SizedBox.shrink();

      if (isReadingPassage(tabelStr, subtestJudul: subtestJudul)) {
        return _buildPassageCard(parsedRows);
      } else {
        return _buildDataTable(parsedRows);
      }
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  /// Merender teks bacaan mengalir alami ke bawah dengan aksen editorial elegan
  Widget _buildPassageCard(List<List<String>> parsedRows) {
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
      final isHeaderRow = parsedRows.length > 1 &&
          (parsedRows[0].any((c) => passageKeywords.any((k) => c.toLowerCase().contains(k))) ||
              parsedRows[0].first.length <= 40);

      if (isHeaderRow) {
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

        if (isShortTitle) {
          paragraphWidgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
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
              padding: const EdgeInsets.only(bottom: 10),
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
        // Multi-kolom (misal: ["Paragraph 1", "Over this decade..."])
        final label = row[0];
        final content = row.sublist(1).join(' ');

        paragraphWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 12 * fontSizeScale,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreen,
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

    // Teks bacaan ditampilkan mengalir vertikal alami, tanpa kotak/border yang mengganggu
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: paragraphWidgets,
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
