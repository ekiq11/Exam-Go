import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../constant/app_config.dart';
import '../models/exam_question_model.dart';
import 'math_latex_converter.dart';

class DocxParseResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final ExamPackage? package;

  DocxParseResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.package,
  });
}

class DocxExamParser {
  /// Membaca dan memvalidasi file DOCX menjadi ExamPackage.
  /// Mendukung tabel, paragraf, bold, italic (garis miring), underline, rumus matematika, dan gambar.
  /// Gambar otomatis diunggah ke Google Drive folder target.
  static Future<DocxParseResult> parseDocxBytes({
    required Uint8List bytes,
    String defaultTitle = 'Ujian Baru',
    String defaultCategory = ExamCategory.umum,
    Function(String status, double progress)? onProgress,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];

    try {
      onProgress?.call('Membuka file DOCX...', 0.1);

      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        return DocxParseResult(
          isValid: false,
          errors: ['File bukan dokumen .docx yang valid atau rusak: $e'],
        );
      }

    // 1. Ambil word/document.xml
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) {
      return DocxParseResult(
        isValid: false,
        errors: ['Dokumen tidak memiliki berkas word/document.xml standar.'],
      );
    }

    // 2. Ambil relasi gambar di word/_rels/document.xml.rels jika ada
    final relsFile = archive.findFile('word/_rels/document.xml.rels');
    final Map<String, String> relTargetMap = {}; // rId -> media/image1.png
    if (relsFile != null) {
      try {
        final relsXml = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
        for (final el in relsXml.findAllElements('Relationship')) {
          final id = el.getAttribute('Id');
          final target = el.getAttribute('Target');
          if (id != null && target != null) {
            relTargetMap[id] = target;
          }
        }
      } catch (_) {}
    }

    // 3. Parse XML document
    onProgress?.call('Menganalisis isi dokumen, tabel & format...', 0.25);
    XmlDocument xmlDoc;
    try {
      xmlDoc = XmlDocument.parse(utf8.decode(docFile.content as List<int>));
    } catch (e) {
      return DocxParseResult(
        isValid: false,
        errors: ['Gagal membaca struktur XML dokumen: $e'],
      );
    }

    // 4. Ekstrak elemen dokumen (paragraf, tabel, format teks, gambar)
    final rawBlocks = _extractDocumentBlocks(xmlDoc, relTargetMap);

    // 5. Upload gambar ke Google Drive jika ada
    final Map<String, String> rIdToDriveUrl = {};
    final allImagesToUpload = <String>{};
    for (final b in rawBlocks) {
      allImagesToUpload.addAll(b.imageRIds);
    }

    if (allImagesToUpload.isNotEmpty) {
      onProgress?.call('Mengunggah ${allImagesToUpload.length} gambar ke Google Drive...', 0.4);
      int uploadedCount = 0;
      for (final rId in allImagesToUpload) {
        final targetPath = relTargetMap[rId];
        if (targetPath != null) {
          final fullZipPath = targetPath.startsWith('word/')
              ? targetPath
              : 'word/${targetPath.replaceFirst(RegExp(r'^\.?\/?'), '')}';

          final imageFile = archive.findFile(fullZipPath);
          if (imageFile != null) {
            final fileName = fullZipPath.split('/').last;
            final driveUrl = await _uploadImageToDrive(
              Uint8List.fromList(imageFile.content as List<int>),
              fileName,
            );
            if (driveUrl != null && driveUrl.isNotEmpty) {
              rIdToDriveUrl[rId] = driveUrl;
            } else {
              warnings.add('Gagal mengunggah gambar $fileName ke Google Drive.');
            }
          }
        }
        uploadedCount++;
        final progressRatio = 0.4 + (0.3 * (uploadedCount / allImagesToUpload.length));
        onProgress?.call('Mengunggah gambar ($uploadedCount/${allImagesToUpload.length})...', progressRatio);
      }
    }

    // 6. Parsing Struktur Soal, Opsi, Kunci, Subtest, Metadata
    onProgress?.call('Menyusun paket soal dan validasi format...', 0.75);

    String examTitle = defaultTitle;
    String examCategory = defaultCategory;
    String jenisWaktu = 'per_paket';
    int durasiTotal = 90;

    final List<ExamSubtest> subtests = [];
    ExamSubtest currentSubtest = ExamSubtest(
      subtestId: 'ST1',
      paketId: '',
      judul: 'Soal Ujian',
      durasiMenit: 30,
    );

    _DraftQuestion? currentQuestion;
    final List<_DraftQuestion> draftList = [];

    void finalizeCurrentQuestion() {
      if (currentQuestion != null) {
        draftList.add(currentQuestion!);
        currentQuestion = null;
      }
    }

    void finalizeCurrentSubtest() {
      finalizeCurrentQuestion();
      if (draftList.isNotEmpty) {
        final qList = <ExamQuestion>[];
        for (final dq in draftList) {
          qList.add(dq.toExamQuestion(currentSubtest.subtestId));
        }
        currentSubtest.soalList = qList;
        subtests.add(currentSubtest);
        draftList.clear();
      }
    }

    for (final block in rawBlocks) {
      String line = block.text;

      // Sisipkan gambar yang sudah diunggah ke Google Drive ke dalam placeholder teks
      for (final rId in block.imageRIds) {
        final driveUrl = rIdToDriveUrl[rId];
        if (driveUrl != null && driveUrl.isNotEmpty) {
          line = line.replaceAll('[IMAGE:$rId]', '<img src="$driveUrl" style="max-width:100%; height:auto; border-radius:8px; margin:8px 0;"/><br/>');
        } else {
          line = line.replaceAll('[IMAGE:$rId]', '');
        }
      }

      // Bersihkan tag formatting untuk pencocokan header & nomor soal
      final cleanLine = line.replaceAll(RegExp(r'<\/?(?:b|strong|i|em|u|s|span|table|tr|td|th|tbody|thead)[^>]*>'), '').trim();
      final upperClean = cleanLine.toUpperCase();

      // Cek Metadata Header
      if (upperClean.startsWith('[JUDUL:') || upperClean.startsWith('[NAMA:')) {
        examTitle = _extractTagValue(cleanLine);
        continue;
      }
      if (upperClean.startsWith('[KATEGORI:')) {
        examCategory = _extractTagValue(cleanLine).toUpperCase();
        continue;
      }
      if (upperClean.startsWith('[JENIS_WAKTU:') || upperClean.startsWith('[WAKTU:')) {
        final jw = _extractTagValue(cleanLine).toLowerCase();
        if (jw.contains('subtest')) jenisWaktu = 'per_subtest';
        continue;
      }
      if (upperClean.startsWith('[DURASI:') || upperClean.startsWith('[DURASI_TOTAL:')) {
        durasiTotal = int.tryParse(_extractTagValue(cleanLine)) ?? durasiTotal;
        continue;
      }

      // Cek Header Subtest Baru
      if (upperClean.startsWith('[SUBTEST:') || upperClean.startsWith('[BAGIAN:')) {
        finalizeCurrentSubtest();
        final subtestTitle = _extractTagValue(cleanLine);
        final nextId = 'ST${subtests.length + 1}';
        currentSubtest = ExamSubtest(
          subtestId: nextId,
          paketId: '',
          judul: subtestTitle.isNotEmpty ? subtestTitle : 'Subtest ${subtests.length + 1}',
          durasiMenit: 30,
        );
        continue;
      }
      if (upperClean.startsWith('[DURASI_SUBTEST:')) {
        currentSubtest.durasiMenit = int.tryParse(_extractTagValue(cleanLine)) ?? currentSubtest.durasiMenit;
        continue;
      }

      // Cek Nomor Soal Baru (misal: "1. Pertanyaan...", "1) Pertanyaan...", "<b>1.</b> Pertanyaan")
      final qNumMatch = RegExp(r'^(?:Soal\s*)?(\d+)[\.\)]\s*(.*)', caseSensitive: false).firstMatch(cleanLine);
      if (qNumMatch != null) {
        finalizeCurrentQuestion();
        final qNum = int.tryParse(qNumMatch.group(1)!) ?? (draftList.length + 1);
        final qText = line.replaceFirst(RegExp(r'^(?:<[^>]+>)*(?:Soal\s*)?\d+[\.\)]\s*(?:<\/[^>]+>)*\s*', caseSensitive: false), '').trim();
        currentQuestion = _DraftQuestion(nomor: qNum, pertanyaan: qText);

        if (block.imageRIds.isNotEmpty) {
          final firstImg = rIdToDriveUrl[block.imageRIds.first];
          if (firstImg != null) currentQuestion!.gambarUrl = firstImg;
        }
        continue;
      }

      // Jika sedang di dalam butir soal:
      if (currentQuestion != null) {
        if (block.imageRIds.isNotEmpty && currentQuestion!.gambarUrl.isEmpty) {
          final firstImg = rIdToDriveUrl[block.imageRIds.first];
          if (firstImg != null) currentQuestion!.gambarUrl = firstImg;
        }

        // Cek Opsi Jawaban: A. , B. , C. , D. , E. (bisa dalam bold/italic)
        final optMatch = RegExp(r'^([A-Ea-e])[\.\)]\s*(.*)').firstMatch(cleanLine);
        if (optMatch != null) {
          final optKey = optMatch.group(1)!.toUpperCase();
          final optText = line.replaceFirst(RegExp(r'^(?:<[^>]+>)*[A-Ea-e][\.\)]\s*(?:<\/[^>]+>)*\s*'), '').trim();
          String optImg = '';
          if (block.imageRIds.isNotEmpty) {
            optImg = rIdToDriveUrl[block.imageRIds.first] ?? '';
          }
          currentQuestion!.setOption(optKey, optText, optImg);
          continue;
        }

        // Cek Kunci Jawaban: KUNCI: A / KUNCI JAWABAN: A
        if (upperClean.startsWith('KUNCI:') || upperClean.startsWith('KUNCI JAWABAN:') || upperClean.startsWith('JAWABAN:')) {
          final parts = cleanLine.split(':');
          if (parts.length > 1) {
            final keyCandidate = RegExp(r'[A-Ea-e]').firstMatch(parts[1])?.group(0)?.toUpperCase();
            if (keyCandidate != null) {
              currentQuestion!.kunci = keyCandidate;
            }
          }
          continue;
        }

        // Cek Pembahasan
        if (upperClean.startsWith('PEMBAHASAN:') || upperClean.startsWith('PENJELASAN:')) {
          final colonIdx = line.indexOf(':');
          if (colonIdx != -1) {
            currentQuestion!.pembahasan = line.substring(colonIdx + 1).trim();
          }
          continue;
        }

        // Jika bukan opsi/kunci/pembahasan dan belum masuk opsi A:
        // Ini adalah paragraf lanjutan dari pertanyaan soal, atau tabel
        if (currentQuestion!.opsiA.isEmpty) {
          if (line.isNotEmpty) {
            if (currentQuestion!.pertanyaan.isNotEmpty) {
              if (line.startsWith('<table')) {
                currentQuestion!.pertanyaan += '<br/>\n$line';
              } else {
                currentQuestion!.pertanyaan += '<br/>$line';
              }
            } else {
              currentQuestion!.pertanyaan = line;
            }
          }
        }
      }
    }

    // Finalisasi subtest terakhir
    finalizeCurrentSubtest();

    // 7. Validasi Kualitas Soal
    onProgress?.call('Memvalidasi kelengkapan butir soal...', 0.95);

    int totalQuestionsFound = 0;
    for (final st in subtests) {
      totalQuestionsFound += st.soalList.length;
      for (final q in st.soalList) {
        if (q.pertanyaan.trim().isEmpty && q.gambar.isEmpty) {
          errors.add('Soal No. ${q.nomorSoal} (${st.judul}): Pertanyaan kosong.');
        }
        if (q.opsiA.isEmpty && q.opsiB.isEmpty) {
          errors.add('Soal No. ${q.nomorSoal} (${st.judul}): Belum memiliki pilihan jawaban A dan B.');
        }
        if (q.kunci.isEmpty || !RegExp(r'^[A-E]$').hasMatch(q.kunci)) {
          errors.add('Soal No. ${q.nomorSoal} (${st.judul}): KUNCI jawaban tidak valid atau belum diset.');
        }
      }
    }

    if (totalQuestionsFound == 0) {
      errors.add(
        'Tidak ada butir soal yang berhasil diekstrak. '
        'Pastikan nomor soal diawali dengan angka dan titik/kurung (contoh: "1. Teks soal").',
      );
    }

    final isValid = errors.isEmpty;
    ExamPackage? finalPackage;

    if (isValid) {
      finalPackage = ExamPackage(
        paketId: '',
        namaPaket: examTitle,
        kategori: examCategory,
        jenisWaktu: jenisWaktu,
        durasiMenit: durasiTotal,
        subtests: subtests,
        status: 'DRAFT',
      );
    }

    onProgress?.call('Selesai.', 1.0);

    return DocxParseResult(
      isValid: isValid,
      errors: errors,
      warnings: warnings,
      package: finalPackage,
    );
  } catch (e) {
    return DocxParseResult(
      isValid: false,
      errors: ['Terjadi kesalahan saat memproses dokumen: $e'],
    );
  }
}

  /// Mengekstrak seluruh elemen dokumen (paragraf, tabel, drawing) berurutan dari `<w:body>`
  static List<_ParagraphBlock> _extractDocumentBlocks(
    XmlDocument xmlDoc,
    Map<String, String> relTargetMap,
  ) {
    final blocks = <_ParagraphBlock>[];

    final bodyNode = xmlDoc.findAllElements('w:body').firstOrNull ??
        xmlDoc.findAllElements('body').firstOrNull;

    if (bodyNode != null) {
      for (final child in bodyNode.children) {
        if (child is XmlElement) {
          final name = child.name.local;
          if (name == 'p') {
            final pBlock = _parseParagraphElement(child, relTargetMap);
            if (pBlock.text.isNotEmpty || pBlock.imageRIds.isNotEmpty) {
              blocks.add(pBlock);
            }
          } else if (name == 'tbl') {
            final List<String> tblImages = [];
            final tblHtml = _parseTableElement(child, relTargetMap, tblImages);
            if (tblHtml.isNotEmpty) {
              blocks.add(_ParagraphBlock(text: tblHtml, imageRIds: tblImages));
            }
          }
        }
      }
    } else {
      // Fallback jika w:body tidak ditemukan
      for (final p in xmlDoc.findAllElements('w:p')) {
        final pBlock = _parseParagraphElement(p, relTargetMap);
        if (pBlock.text.isNotEmpty || pBlock.imageRIds.isNotEmpty) {
          blocks.add(pBlock);
        }
      }
    }

    return blocks;
  }

  /// Membaca satu node `<w:p>` dengan mempertahankan bold, italic, underline, math, line break, dan gambar
  static _ParagraphBlock _parseParagraphElement(
    XmlElement pNode,
    Map<String, String> relTargetMap,
  ) {
    final buffer = StringBuffer();
    final List<String> imageRIds = [];

    for (final child in pNode.children) {
      if (child is XmlElement) {
        _extractRunFormattingAndContent(child, buffer, imageRIds);
      }
    }

    var text = buffer.toString().trim();
    final plainUpper = text.replaceAll(RegExp(r'<[^>]*>'), '').trim().toUpperCase();
    if (text.isNotEmpty &&
        !plainUpper.startsWith('[') &&
        !plainUpper.startsWith('KUNCI:') &&
        !plainUpper.startsWith('KUNCI JAWABAN:') &&
        !plainUpper.startsWith('JAWABAN:')) {
      text = MathLatexConverter.convertPlainTextToLatex(text);
    }

    return _ParagraphBlock(text: text, imageRIds: imageRIds);
  }

  /// Mengekstrak konten satu run atau node anak paragraf
  static void _extractRunFormattingAndContent(
    XmlElement node,
    StringBuffer buffer,
    List<String> imageRIds,
  ) {
    final localName = node.name.local;

    // 1. Run (<w:r>)
    if (localName == 'r') {
      final rPr = node.findElements('w:rPr').firstOrNull ?? node.findElements('rPr').firstOrNull;

      bool isBold = false;
      bool isItalic = false;
      bool isUnderline = false;
      bool isStrike = false;
      bool isSup = false;
      bool isSub = false;

      if (rPr != null) {
        final bEl = rPr.findElements('w:b').firstOrNull ?? rPr.findElements('b').firstOrNull;
        if (bEl != null) {
          final val = bEl.getAttribute('w:val') ?? bEl.getAttribute('val');
          isBold = val != '0' && val != 'false';
        }

        final iEl = rPr.findElements('w:i').firstOrNull ?? rPr.findElements('i').firstOrNull;
        if (iEl != null) {
          final val = iEl.getAttribute('w:val') ?? iEl.getAttribute('val');
          isItalic = val != '0' && val != 'false';
        }

        final uEl = rPr.findElements('w:u').firstOrNull ?? rPr.findElements('u').firstOrNull;
        if (uEl != null) {
          final val = uEl.getAttribute('w:val') ?? uEl.getAttribute('val');
          isUnderline = val != 'none';
        }

        final strikeEl = rPr.findElements('w:strike').firstOrNull ?? rPr.findElements('strike').firstOrNull;
        if (strikeEl != null) {
          final val = strikeEl.getAttribute('w:val') ?? strikeEl.getAttribute('val');
          isStrike = val != '0' && val != 'false';
        }

        final vertEl = rPr.findElements('w:vertAlign').firstOrNull ?? rPr.findElements('vertAlign').firstOrNull;
        if (vertEl != null) {
          final val = vertEl.getAttribute('w:val') ?? vertEl.getAttribute('val');
          isSup = val == 'superscript';
          isSub = val == 'subscript';
        }
      }

      final runBuffer = StringBuffer();
      for (final child in node.children) {
        if (child is XmlElement) {
          final cName = child.name.local;
          if (cName == 't') {
            runBuffer.write(child.innerText);
          } else if (cName == 'br') {
            runBuffer.write('<br/>');
          } else if (cName == 'drawing') {
            for (final blip in child.findAllElements('a:blip')) {
              final rEmbed = blip.getAttribute('r:embed') ?? blip.getAttribute('embed');
              if (rEmbed != null && rEmbed.isNotEmpty) {
                imageRIds.add(rEmbed);
                runBuffer.write(' [IMAGE:$rEmbed] ');
              }
            }
          }
        }
      }

      String runText = runBuffer.toString();
      if (runText.isNotEmpty) {
        if (isBold) runText = '<b>$runText</b>';
        if (isItalic) runText = '<i>$runText</i>';
        if (isUnderline) runText = '<u>$runText</u>';
        if (isStrike) runText = '<s>$runText</s>';
        if (isSup) runText = '<sup>$runText</sup>';
        if (isSub) runText = '<sub>$runText</sub>';
        buffer.write(runText);
      }
      return;
    }

    // 2. Equation Office Math (<m:oMath> atau <m:oMathPara>)
    if (localName == 'oMath' || localName == 'oMathPara') {
      final mathLatex = MathLatexConverter.convertOMathElementToLatex(node);
      if (mathLatex.isNotEmpty) {
        buffer.write(' $mathLatex ');
      }
      return;
    }

    // 3. Line break langsung di <w:p>
    if (localName == 'br') {
      buffer.write('<br/>');
      return;
    }

    // 4. Drawing langsung di <w:p>
    if (localName == 'drawing') {
      for (final blip in node.findAllElements('a:blip')) {
        final rEmbed = blip.getAttribute('r:embed') ?? blip.getAttribute('embed');
        if (rEmbed != null && rEmbed.isNotEmpty) {
          imageRIds.add(rEmbed);
          buffer.write(' [IMAGE:$rEmbed] ');
        }
      }
      return;
    }

    // 5. Rekursif untuk child elements lain (misal <w:hyperlink>, <w:sdt>)
    for (final child in node.children) {
      if (child is XmlElement) {
        _extractRunFormattingAndContent(child, buffer, imageRIds);
      }
    }
  }

  /// Membaca satu node tabel `<w:tbl>` dan mengubahnya menjadi format HTML `<table>`
  static String _parseTableElement(
    XmlElement tblNode,
    Map<String, String> relTargetMap,
    List<String> imageRIds,
  ) {
    final rows = tblNode.findAllElements('w:tr').toList();
    if (rows.isEmpty) rows.addAll(tblNode.findAllElements('tr'));
    if (rows.isEmpty) return '';

    final sb = StringBuffer();
    sb.writeln('<table border="1" cellpadding="6" style="border-collapse:collapse; width:100%; margin:10px 0; border:1px solid #CBD5E1; font-size:13px;">');
    sb.writeln('  <tbody>');

    bool isFirstRow = true;
    for (final tr in rows) {
      sb.writeln('    <tr${isFirstRow ? ' style="background-color:#F1F5F9;"' : ''}>');
      final cells = tr.findElements('w:tc').toList();
      if (cells.isEmpty) cells.addAll(tr.findElements('tc'));

      for (final tc in cells) {
        final cellBuffer = StringBuffer();
        final paragraphs = tc.findElements('w:p').toList();
        if (paragraphs.isEmpty) paragraphs.addAll(tc.findElements('p'));

        for (int i = 0; i < paragraphs.length; i++) {
          final pBlock = _parseParagraphElement(paragraphs[i], relTargetMap);
          imageRIds.addAll(pBlock.imageRIds);
          if (i > 0 && pBlock.text.isNotEmpty) cellBuffer.write('<br/>');
          cellBuffer.write(pBlock.text);
        }

        final cellContent = cellBuffer.toString().trim();
        final tag = isFirstRow ? 'th' : 'td';
        final style = isFirstRow
            ? 'style="border:1px solid #CBD5E1; padding:6px 10px; font-weight:bold; text-align:left;"'
            : 'style="border:1px solid #CBD5E1; padding:6px 10px;"';
        sb.writeln('      <$tag $style>${cellContent.isNotEmpty ? cellContent : '&nbsp;'}</$tag>');
      }

      sb.writeln('    </tr>');
      isFirstRow = false;
    }

    sb.writeln('  </tbody>');
    sb.writeln('</table>');
    return sb.toString();
  }

  static String _extractTagValue(String line) {
    final start = line.indexOf(':');
    final end = line.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return line.substring(start + 1, end).trim();
    } else if (start != -1) {
      return line.substring(start + 1).trim();
    }
    return '';
  }

  /// Unggah gambar ke Google Drive via GAS Backend ke folder target
  static Future<String?> _uploadImageToDrive(Uint8List imageBytes, String filename) async {
    try {
      final gasUrl = AppConfig.gasUrl;
      final apiKey = AppConfig.gasApiKey;
      if (gasUrl.isEmpty || apiKey.isEmpty) return null;

      final base64Data = base64Encode(imageBytes);
      final resp = await http.post(
        Uri.parse(gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': apiKey,
          'action': 'uploadFileToDrive',
          'base64': base64Data,
          'filename': filename,
          'mimeType': 'image/png',
          'folderId': AppConfig.driveFolderId,
        }),
      ).timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final resJson = jsonDecode(resp.body) as Map<String, dynamic>;
        if (resJson['success'] == true && resJson['url'] != null) {
          return resJson['url'] as String;
        }
      }
    } catch (_) {}
    return null;
  }
}

class _ParagraphBlock {
  final String text;
  final List<String> imageRIds;
  _ParagraphBlock({required this.text, required this.imageRIds});
}

class _DraftQuestion {
  final int nomor;
  String pertanyaan;
  String opsiA = '';
  String opsiB = '';
  String opsiC = '';
  String opsiD = '';
  String opsiE = '';
  String gamA = '';
  String gamB = '';
  String gamC = '';
  String gamD = '';
  String gamE = '';
  String kunci = 'A';
  String pembahasan = '';
  String gambarUrl = '';

  _DraftQuestion({required this.nomor, required this.pertanyaan});

  void setOption(String key, String text, String img) {
    switch (key) {
      case 'A':
        opsiA = text;
        gamA = img;
        break;
      case 'B':
        opsiB = text;
        gamB = img;
        break;
      case 'C':
        opsiC = text;
        gamC = img;
        break;
      case 'D':
        opsiD = text;
        gamD = img;
        break;
      case 'E':
        opsiE = text;
        gamE = img;
        break;
    }
  }

  ExamQuestion toExamQuestion(String subtestId) {
    return ExamQuestion(
      soalId: '${subtestId}_$nomor',
      subtestId: subtestId,
      nomorSoal: nomor,
      pertanyaan: pertanyaan,
      opsiA: opsiA,
      opsiB: opsiB,
      opsiC: opsiC,
      opsiD: opsiD,
      opsiE: opsiE,
      gamA: gamA,
      gamB: gamB,
      gamC: gamC,
      gamD: gamD,
      gamE: gamE,
      kunci: kunci,
      pembahasan: pembahasan,
      gambar: gambarUrl,
    );
  }
}
