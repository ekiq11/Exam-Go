import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:examgo/constant/app_config.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/docx_exam_parser.dart';
import 'package:examgo/services/docx_template_generator.dart';
import 'package:examgo/services/gform_exam_parser.dart';
import 'package:examgo/services/math_latex_converter.dart';
import 'package:examgo/utils/math_widget_factory.dart';

void main() {
  group('MathHtmlFormatter Tests', () {
    test(r'Mengonversi inline math $...$ ke tag span math-tex inline', () {
      const input = r'Jika $x + 2 = 5$, berapakah nilai $x$?';
      final formatted = MathHtmlFormatter.format(input);

      expect(formatted, contains('<span class="math-tex inline"'));
      expect(formatted, contains('data-math="x%20%2B%202%20%3D%205"'));
      expect(formatted, contains('data-math="x"'));
    });

    test(r'Mengonversi display math $$...$$ ke tag span math-tex display', () {
      const input = r'Rumus integral:' '\n' r'$$\int_0^1 x dx = \frac{1}{2}$$';
      final formatted = MathHtmlFormatter.format(input);

      expect(formatted, contains('<span class="math-tex display"'));
      expect(formatted, contains('data-math="'));
    });

    test('Mengonversi link Google Drive file/d/ID ke CDN lh3.googleusercontent.com', () {
      const driveUrl = 'https://drive.google.com/file/d/1a2B3c4D5e6F/view?usp=sharing';
      final direct = MathHtmlFormatter.convertDriveUrl(driveUrl);

      expect(direct, equals('https://lh3.googleusercontent.com/d/1a2B3c4D5e6F'));
    });

    test('Google Drive ID murni dikonversi ke URL CDN lh3.googleusercontent.com', () {
      const driveId = '1a2B3c4D5e6F';
      final direct = MathHtmlFormatter.convertDriveUrl(driveId);

      expect(direct, equals('https://lh3.googleusercontent.com/d/1a2B3c4D5e6F'));
    });
  });

  group('ExamPackage & ExamQuestion Model Tests', () {
    test('Perhitungan total soal pada package mengakumulasikan semua subtest', () {
      final pkg = ExamPackage(
        paketId: 'TEST01',
        namaPaket: 'Try Out SNBT Test',
        kategori: ExamCategory.snbt,
        subtests: [
          ExamSubtest(
            subtestId: 'ST1',
            paketId: 'TEST01',
            judul: 'Penalaran Umum',
            durasiMenit: 30,
            soalList: [
              ExamQuestion(
                soalId: 'ST1_1',
                subtestId: 'ST1',
                nomorSoal: 1,
                pertanyaan: 'Soal 1',
                opsiA: 'A',
                opsiB: 'B',
                kunci: 'A',
              ),
              ExamQuestion(
                soalId: 'ST1_2',
                subtestId: 'ST1',
                nomorSoal: 2,
                pertanyaan: 'Soal 2',
                opsiA: 'A',
                opsiB: 'B',
                kunci: 'B',
              ),
            ],
          ),
          ExamSubtest(
            subtestId: 'ST2',
            paketId: 'TEST01',
            judul: 'Literasi B. Indonesia',
            durasiMenit: 40,
            soalList: [
              ExamQuestion(
                soalId: 'ST2_1',
                subtestId: 'ST2',
                nomorSoal: 1,
                pertanyaan: 'Soal 3',
                opsiA: 'A',
                opsiB: 'B',
                kunci: 'A',
              ),
            ],
          ),
        ],
      );

      expect(pkg.totalSoal, equals(3));
      final firestoreMap = pkg.toFirestore();
      expect(firestoreMap['total_soal'], equals(3));
      expect(firestoreMap['kategori'], equals('SNBT'));
    });
  });

  group('DocxExamParser Tests', () {
    test('Menolak byte bukan-zip dengan pesan error yang jelas', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await DocxExamParser.parseDocxBytes(bytes: invalidBytes);

      expect(result.isValid, isFalse);
      expect(result.errors.isNotEmpty, isTrue);
    });

    test('Memproses zip DOCX sintetis dengan format soal standar', () async {
      final xmlContent = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>[JUDUL: Ujian Matematika]</w:t></w:r></w:p>
    <w:p><w:r><w:t>[KATEGORI: SNBT]</w:t></w:r></w:p>
    <w:p><w:r><w:t>[SUBTEST: Penalaran Matematika]</w:t></w:r></w:p>
    <w:p><w:r><w:t>1. Jika \$x + 3 = 10\$, maka nilai x adalah ...</w:t></w:r></w:p>
    <w:p><w:r><w:t>A. 5</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. 7</w:t></w:r></w:p>
    <w:p><w:r><w:t>C. 9</w:t></w:r></w:p>
    <w:p><w:r><w:t>D. 11</w:t></w:r></w:p>
    <w:p><w:r><w:t>E. 13</w:t></w:r></w:p>
    <w:p><w:r><w:t>KUNCI: B</w:t></w:r></w:p>
    <w:p><w:r><w:t>PEMBAHASAN: \$x = 10 - 3 = 7\$.</w:t></w:r></w:p>
  </w:body>
</w:document>
''';

      final archive = Archive();
      final xmlBytes = utf8.encode(xmlContent);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));

      final zipEncoder = ZipEncoder();
      final docxBytes = Uint8List.fromList(zipEncoder.encode(archive)!);

      final result = await DocxExamParser.parseDocxBytes(bytes: docxBytes);

      expect(result.isValid, isTrue);
      expect(result.package, isNotNull);
      expect(result.package!.namaPaket, equals('Ujian Matematika'));
      expect(result.package!.kategori, equals('SNBT'));
      expect(result.package!.totalSoal, equals(1));

      final firstQ = result.package!.subtests.first.soalList.first;
      expect(firstQ.kunci, equals('B'));
      expect(firstQ.opsiA, equals('5'));
      expect(firstQ.opsiB, equals('7'));
      expect(firstQ.pembahasan, contains('7'));
    });

    test('Memproses format teks kaya (bold, italic, underline, strike, sub/sup) dan tabel HTML dari XML DOCX', () async {
      final richXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>[JUDUL: Ujian Sains]</w:t></w:r></w:p>
    <w:p><w:r><w:t>[KATEGORI: TKA]</w:t></w:r></w:p>
    <w:p><w:r><w:t>[SUBTEST: Kimia Fisika]</w:t></w:r></w:p>
    <w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t>1. </w:t></w:r>
      <w:r><w:t>Perhatikan senyawa </w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t>H</w:t></w:r>
      <w:r><w:rPr><w:vertAlign w:val="subscript"/></w:rPr><w:t>2</w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t>SO</w:t></w:r>
      <w:r><w:rPr><w:vertAlign w:val="subscript"/></w:rPr><w:t>4</w:t></w:r>
      <w:r><w:t> dan ion </w:t></w:r>
      <w:r><w:t>Fe</w:t></w:r>
      <w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>3+</w:t></w:r>
      <w:r><w:t>. Teks ini </w:t></w:r>
      <w:r><w:rPr><w:i/></w:rPr><w:t>miring</w:t></w:r>
      <w:r><w:t>, </w:t></w:r>
      <w:r><w:rPr><w:u/></w:rPr><w:t>garis bawah</w:t></w:r>
      <w:r><w:t>, dan </w:t></w:r>
      <w:r><w:rPr><w:strike/></w:rPr><w:t>coret</w:t></w:r>
      <w:r><w:t>.</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tr>
        <w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Unsur</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Massa</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Hidrogen</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>1 g/mol</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
    <w:p><w:r><w:t>A. Benar</w:t></w:r></w:p>
    <w:p><w:r><w:t>B. Salah</w:t></w:r></w:p>
    <w:p><w:r><w:t>C. Ragu</w:t></w:r></w:p>
    <w:p><w:r><w:t>D. Tidak Tahu</w:t></w:r></w:p>
    <w:p><w:r><w:t>E. Kosong</w:t></w:r></w:p>
    <w:p><w:r><w:t>KUNCI: A</w:t></w:r></w:p>
  </w:body>
</w:document>
''';

      final archive = Archive();
      final xmlBytes = utf8.encode(richXml);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final zipEncoder = ZipEncoder();
      final docxBytes = Uint8List.fromList(zipEncoder.encode(archive)!);

      final result = await DocxExamParser.parseDocxBytes(bytes: docxBytes);
      expect(result.isValid, isTrue);

      final q = result.package!.subtests.first.soalList.first;
      expect(q.pertanyaan, contains('<sub>2</sub>'));
      expect(q.pertanyaan, contains('<sub>4</sub>'));
      expect(q.pertanyaan, contains('<sup>3+</sup>'));
      expect(q.pertanyaan, contains('<i>miring</i>'));
      expect(q.pertanyaan, contains('<u>garis bawah</u>'));
      expect(q.pertanyaan, contains('<s>coret</s>'));
      expect(q.pertanyaan, contains('<table'));
      expect(q.pertanyaan, contains('<th'));
      expect(q.pertanyaan, contains('Unsur'));
      expect(q.pertanyaan, contains('<td'));
      expect(q.pertanyaan, contains('Hidrogen'));
      expect(q.pertanyaan, contains('1 g/mol'));
      expect(q.kunci, equals('A'));
    });

    test('Memverifikasi folder Google Drive tujuan upload terkonfigurasi sesuai instruksi', () {
      expect(AppConfig.driveFolderId, equals('1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ'));
    });
  });

  group('DocxTemplateGenerator Tests', () {
    test('Menghasilkan file DOCX template standar yang valid dan dapat di-parse balik', () async {
      final templateBytes = DocxTemplateGenerator.generateTemplateBytes();
      expect(templateBytes.isNotEmpty, isTrue);

      // Verifikasi struktur internal ZIP OpenXML
      final archive = ZipDecoder().decodeBytes(templateBytes);
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(archive.findFile('_rels/.rels'), isNotNull);
      expect(archive.findFile('word/document.xml'), isNotNull);

      // Verifikasi parsing oleh DocxExamParser
      final parseResult = await DocxExamParser.parseDocxBytes(bytes: templateBytes);
      expect(parseResult.isValid, isTrue, reason: parseResult.errors.join(', '));
      expect(parseResult.errors, isEmpty);
      expect(parseResult.package, isNotNull);

      final pkg = parseResult.package!;
      expect(pkg.namaPaket, equals('Try Out Mandiri SNBT 2026'));
      expect(pkg.kategori, equals('SNBT'));
      expect(pkg.subtests.length, equals(2));
      expect(pkg.totalSoal, equals(4));

      // Verifikasi Subtest 1 (Pengetahuan Umum biasa tanpa rumus/LaTeX rumit)
      final st1 = pkg.subtests[0];
      expect(st1.judul, equals('Pengetahuan Umum'));
      expect(st1.durasiMenit, equals(30));
      expect(st1.soalList.length, equals(2));
      expect(st1.soalList[0].kunci, equals('A'));
      expect(st1.soalList[0].pertanyaan, contains('Ibu kota negara Indonesia'));
      expect(st1.soalList[1].kunci, equals('C'));
      expect(st1.soalList[1].pertanyaan, contains('dasar negara Indonesia'));

      // Verifikasi Subtest 2
      final st2 = pkg.subtests[1];
      expect(st2.judul, equals('Literasi Bahasa Indonesia'));
      expect(st2.durasiMenit, equals(25));
      expect(st2.soalList.length, equals(2));
      expect(st2.soalList[0].kunci, equals('B'));
      expect(st2.soalList[1].kunci, equals('B'));
    });

    test('Menghasilkan template dengan kustomisasi judul dan kategori', () async {
      final customBytes = DocxTemplateGenerator.generateTemplateBytes(
        title: 'Penilaian Akhir Semester Fisika',
        category: 'TKA',
      );

      final parseResult = await DocxExamParser.parseDocxBytes(bytes: customBytes);
      expect(parseResult.isValid, isTrue);
      expect(parseResult.package!.namaPaket, equals('Penilaian Akhir Semester Fisika'));
      expect(parseResult.package!.kategori, equals('TKA'));
    });
  });

  group('MathLatexConverter Tests', () {
    test('Mengonversi superskrip biasa x² dan operasi matematika ke LaTeX', () {
      final converted = MathLatexConverter.convertPlainTextToLatex('Jika x² + 2x - 15 = 0, maka x ≥ 0');
      expect(converted, contains(r'x^{2}'));
      expect(converted, contains(r'\ge'));
      expect(converted, contains(r'$'));
    });

    test('Mengonversi simbol akar √3 dan pecahan biasa', () {
      final converted = MathLatexConverter.convertPlainTextToLatex('Bentuk sederhana dari √3 / (√5 - √2)');
      expect(converted, contains(r'\sqrt{3}'));
      expect(converted, contains(r'\sqrt{5}'));
      expect(converted, contains(r'\sqrt{2}'));
    });
  });

  group('GFormExamParser Tests', () {
    test('Validasi link kosong mengembalikan error yang jelas', () async {
      final res = await GFormExamParser.parseFromUrl(formUrl: '');
      expect(res.isValid, isFalse);
      expect(res.errors, isNotEmpty);
      expect(res.errors[0], contains('tidak boleh kosong'));
    });

    test('Validasi link non-Google Form yang gagal diakses ditangani aman', () async {
      final res = await GFormExamParser.parseFromUrl(
        formUrl: 'https://invalid-non-existent-domain-12345.com/form',
      );
      expect(res.isValid, isFalse);
      expect(res.errors, isNotEmpty);
    });

    test('Validasi deteksi restricted domain Google Form', () async {
      // Form yang meminta login organisasi ditolak dengan panduan jelas
      final res = await GFormExamParser.parseFromUrl(
        formUrl: 'https://docs.google.com/forms/d/e/invalid_restricted_form/viewform',
      );
      expect(res.isValid, isFalse);
      expect(res.errors, isNotEmpty);
    });
  });
}
