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
        '• Tuliskan soal dan pilihan jawaban secara biasa dan alami seperti mengetik naskah ujian sekolah pada umumnya. Tidak perlu kode rumus khusus.',
      ),
      _Para(
        '• Gambar soal maupun gambar pada opsi jawaban dapat langsung di-paste (Ctrl+V) ke dalam dokumen Word ini.',
      ),
      _Para(
        '• Setiap butir soal WAJIB diawali nomor (misal: "1." atau "1)"), pilihan jawaban A sampai E, dan baris KUNCI: (A/B/C/D/E). Baris PEMBAHASAN bersifat opsional.',
      ),
      _Para(''),
      _Para('[SUBTEST: Pengetahuan Umum]', isBold: true, fontSize: 28),
      _Para('[DURASI_SUBTEST: 30]', isBold: true),
      _Para(''),
      _Para(
        '1. Ibu kota negara Indonesia yang baru dan berlokasi di Provinsi Kalimantan Timur adalah ...',
      ),
      _Para('A. Nusantara'),
      _Para('B. Balikpapan'),
      _Para('C. Samarinda'),
      _Para('D. Banjarmasin'),
      _Para('E. Pontianak'),
      _Para('KUNCI: A', isBold: true),
      _Para(
        'PEMBAHASAN: Berdasarkan undang-undang pemindahan ibu kota negara, Nusantara (IKN) berlokasi di Kalimantan Timur.',
      ),
      _Para(''),
      _Para(
        '2. Lambang negara Indonesia adalah Burung Garuda, sedangkan dasar negara Indonesia adalah ...',
      ),
      _Para('A. UUD 1945'),
      _Para('B. Bhinneka Tunggal Ika'),
      _Para('C. Pancasila'),
      _Para('D. Proklamasi'),
      _Para('E. Sumpah Pemuda'),
      _Para('KUNCI: C', isBold: true),
      _Para(
        'PEMBAHASAN: Dasar falsafah dan ideologi negara Republik Indonesia adalah Pancasila.',
      ),
      _Para(''),
      _Para('[SUBTEST: Literasi Bahasa Indonesia]', isBold: true, fontSize: 28),
      _Para('[DURASI_SUBTEST: 25]', isBold: true),
      _Para(''),
      _Para('3. Cermati kutipan teks berikut!'),
      _Para(
        'Membaca buku secara rutin dapat melatih konsentrasi, memperluas wawasan pengetahuan, dan mengasah daya ingat siswa.',
      ),
      _Para(
        'Manfaat utama membaca buku berdasarkan kutipan di atas adalah ...',
      ),
      _Para('A. Menggantikan proses belajar di sekolah'),
      _Para('B. Melatih konsentrasi dan memperluas wawasan'),
      _Para('C. Mempercepat kelulusan ujian nasional'),
      _Para('D. Menghilangkan waktu bermain anak'),
      _Para('E. Menambah beban tugas harian siswa'),
      _Para('KUNCI: B', isBold: true),
      _Para(
        'PEMBAHASAN: Teks secara eksplisit menyebutkan bahwa membaca melatih konsentrasi dan memperluas wawasan pengetahuan.',
      ),
      _Para(''),
      _Para('4. Perhatikan contoh soal dengan ilustrasi gambar berikut:'),
      _Para(
        '[Silakan paste atau tempel gambar diagram atau foto langsung di posisi ini]',
      ),
      _Para(
        'Berdasarkan ilustrasi gambar bagian tumbuhan di atas, fungsi utama daun adalah ...',
      ),
      _Para('A. Menyerap air dan mineral dari dalam tanah'),
      _Para('B. Tempat utama berlangsungnya proses fotosintesis'),
      _Para('C. Menopang tegaknya batang tanaman'),
      _Para('D. Menyimpan cadangan makanan di dalam tanah'),
      _Para('E. Mengalirkan sari makanan ke seluruh akar'),
      _Para('KUNCI: B', isBold: true),
      _Para(
        'PEMBAHASAN: Daun mengandung klorofil dan merupakan tempat utama fotosintesis pada tumbuhan.',
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
