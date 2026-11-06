import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Generator file template Microsoft Word (.docx) standar untuk ExamGO.
class DocxTemplateGenerator {
  /// Menghasilkan file byte .docx yang valid dan siap diunduh/dibagikan.
  static Uint8List generateTemplateBytes({String? title, String? category}) {
    final examTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : 'Try Out Mandiri SNBT 2026';
    final examCat = (category != null && category.trim().isNotEmpty)
        ? category.trim().toUpperCase()
        : 'SNBT';

    final paragraphs = <_Para>[
      _Para('TEMPLATE SOAL UJIAN EXAMGO', isBold: true, fontSize: 32),
      _Para(
        'Dokumen ini adalah format standar impor soal ke aplikasi ExamGO.',
        isItalic: true,
      ),
      _Para(''),
      _Para('[JUDUL: $examTitle]', isBold: true),
      _Para('[KATEGORI: $examCat]', isBold: true),
      _Para('[JENIS_WAKTU: per_subtest]', isBold: true),
      _Para('[DURASI: 90]', isBold: true),
      _Para(''),
      _Para('--- PETUNJUK PENGISIAN SOAL ---', isBold: true),
      _Para(
        '• Jangan menghapus atau mengubah tanda kurung siku pada tag seperti [JUDUL: ...], [KATEGORI: ...], [SUBTEST: ...].',
      ),
      _Para('• Pilihan kategori yang didukung: UMUM, TKA, SNBT, SKD.'),
      _Para(
        '• Pilihan jenis waktu: "total" (durasi gabungan seluruh soal) atau "per_subtest" (durasi dihitung bergantian tiap babak).',
      ),
      _Para(
        '• Anda TIDAK PERLU mengetik kode LaTeX manual yang rumit. Tuliskan rumus/simbol matematika secara alami (contoh: x² + 2x - 15 = 0, simbol akar √, pangkat, pecahan, atau fitur Equation Word). Sistem ExamGO akan otomatis mengonversinya ke format LaTeX yang rapi.',
      ),
      _Para(
        '• Gambar soal maupun gambar pada opsi jawaban dapat langsung di-paste (Ctrl+V) ke dalam dokumen Word ini. Saat file DOCX diunggah, ExamGO akan otomatis mengunggah gambar ke Google Drive sekolah.',
      ),
      _Para(
        '• Setiap butir soal WAJIB diawali nomor (misal: "1." atau "1)"), pilihan jawaban A sampai E, dan baris KUNCI: (A/B/C/D/E). Baris PEMBAHASAN bersifat opsional.',
      ),
      _Para(''),
      _Para('[SUBTEST: Penalaran Matematika]', isBold: true, fontSize: 28),
      _Para('[DURASI_SUBTEST: 30]', isBold: true),
      _Para(''),
      _Para(
        '1. Jika nilai dari x² + 2x - 15 = 0 dengan syarat x > 0, maka nilai x yang memenuhi adalah ...',
      ),
      _Para('A. 1'),
      _Para('B. 3'),
      _Para('C. 5'),
      _Para('D. 7'),
      _Para('E. 9'),
      _Para('KUNCI: B', isBold: true),
      _Para(
        'PEMBAHASAN: Faktorisasi persamaan kuadrat: (x + 5)(x - 3) = 0. Diperoleh akar x = -5 atau x = 3. Karena disyaratkan x > 0, maka nilai yang memenuhi adalah x = 3.',
      ),
      _Para(''),
      _Para(
        '2. Bentuk sederhana dari pecahan bentuk akar √3 / (√5 - √2) adalah ...',
      ),
      _Para('A. (√15 + √6) / 3'),
      _Para('B. (√15 - √6) / 3'),
      _Para('C. (√10 + √6) / 3'),
      _Para('D. √15 + √6'),
      _Para('E. √15 - √6'),
      _Para('KUNCI: A', isBold: true),
      _Para(
        'PEMBAHASAN: Kalikan pembilang dan penyebut dengan sekawan (√5 + √2). Hasil penyebut 5 - 2 = 3, dan pembilang √15 + √6.',
      ),
      _Para(''),
      _Para('[SUBTEST: Literasi Bahasa Indonesia]', isBold: true, fontSize: 28),
      _Para('[DURASI_SUBTEST: 25]', isBold: true),
      _Para(''),
      _Para('3. Cermati paragraf berikut!'),
      _Para(
        'Perkembangan kecerdasan buatan (AI) telah mengubah paradigma pembelajaran di era digital. Tenaga pendidik kini dituntut tidak hanya menguasai materi kurikulum, namun juga mampu mengintegrasikan teknologi evaluasi interaktif yang adaptif terhadap kebutuhan siswa.',
      ),
      _Para(
        'Gagasan pokok yang tepat untuk kutipan paragraf di atas adalah ...',
      ),
      _Para('A. Penggantian peran guru secara total oleh kecerdasan buatan.'),
      _Para(
        'B. Tuntutan integrasi teknologi digital dan AI dalam evaluasi pembelajaran.',
      ),
      _Para(
        'C. Pembelajaran tradisional lebih unggul daripada teknologi modern.',
      ),
      _Para('D. Kurikulum sekolah yang menolak pemanfaatan teknologi digital.'),
      _Para('E. Penurunan minat belajar siswa di era transformasi digital.'),
      _Para('KUNCI: B', isBold: true),
      _Para(
        'PEMBAHASAN: Ide pokok terdapat pada kalimat kedua mengenai tuntutan integrasi teknologi ke dalam evaluasi belajar.',
      ),
      _Para(''),
      _Para('4. Perhatikan contoh soal dengan ilustrasi gambar berikut:'),
      _Para(
        '[Silakan tempel atau paste gambar diagram/grafik langsung di posisi ini pada Word]',
      ),
      _Para(
        'Berdasarkan data tren peningkatan hasil belajar siswa pada grafik di atas, kesimpulan yang paling tepat adalah ...',
      ),
      _Para(
        'A. Terjadi peningkatan nilai secara konsisten pada setiap periode ujian.',
      ),
      _Para('B. Nilai rata-rata siswa mengalami penurunan drastis.'),
      _Para('C. Tidak ada perubahan hasil evaluasi belajar.'),
      _Para('D. Penurunan signifikan terjadi di akhir semester.'),
      _Para('E. Semua siswa meraih nilai sempurna tanpa evaluasi.'),
      _Para('KUNCI: A', isBold: true),
      _Para(
        'PEMBAHASAN: Tren garis grafik memperlihatkan kenaikan hasil belajar secara konsisten dari awal hingga akhir periode.',
      ),
    ];

    final docXml = _buildDocumentXml(paragraphs);
    const contentTypesXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rootRelsXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    const docRelsXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';

    final archive = Archive();
    final ctBytes = utf8.encode(contentTypesXml);
    archive.addFile(
      ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes),
    );

    final rootRelsBytes = utf8.encode(rootRelsXml);
    archive.addFile(
      ArchiveFile('_rels/.rels', rootRelsBytes.length, rootRelsBytes),
    );

    final docRelsBytes = utf8.encode(docRelsXml);
    archive.addFile(
      ArchiveFile(
        'word/_rels/document.xml.rels',
        docRelsBytes.length,
        docRelsBytes,
      ),
    );

    final docBytes = utf8.encode(docXml);
    archive.addFile(
      ArchiveFile('word/document.xml', docBytes.length, docBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes!);
  }

  static String _buildDocumentXml(List<_Para> paras) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.writeln(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
    sb.writeln('  <w:body>');

    for (final p in paras) {
      sb.write('    <w:p>');
      if (p.text.isNotEmpty) {
        sb.write('<w:r>');
        if (p.isBold || p.isItalic || p.fontSize != null) {
          sb.write('<w:rPr>');
          if (p.isBold) sb.write('<w:b/>');
          if (p.isItalic) sb.write('<w:i/>');
          if (p.fontSize != null) sb.write('<w:sz w:val="${p.fontSize}"/>');
          sb.write('</w:rPr>');
        }
        sb.write('<w:t xml:space="preserve">${_escapeXml(p.text)}</w:t>');
        sb.write('</w:r>');
      }
      sb.writeln('</w:p>');
    }

    sb.writeln('  </w:body>');
    sb.writeln('</w:document>');
    return sb.toString();
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _Para {
  final String text;
  final bool isBold;
  final bool isItalic;
  final int? fontSize;

  _Para(this.text, {this.isBold = false, this.isItalic = false, this.fontSize});
}
