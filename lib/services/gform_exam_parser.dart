import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/exam_question_model.dart';
import '../utils/math_widget_factory.dart';

class GFormParseResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final ExamPackage? package;

  GFormParseResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.package,
  });
}

class GFormExamParser {
  /// Mengambil dan mengonversi Google Form publik menjadi ExamPackage
  static Future<GFormParseResult> parseFromUrl({
    required String formUrl,
    String defaultCategory = ExamCategory.umum,
    int defaultDurationMinutes = 90,
  }) async {
    final warnings = <String>[];

    String cleanUrl = formUrl.trim();
    if (cleanUrl.isEmpty) {
      return GFormParseResult(
        isValid: false,
        errors: ['URL Google Form tidak boleh kosong.'],
      );
    }

    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    // Ubah URL /edit atau shortlink menjadi format viewform
    if (cleanUrl.contains('/edit')) {
      cleanUrl = cleanUrl.replaceAll('/edit', '/viewform');
    }

    http.Response response;
    try {
      response = await http.get(
        Uri.parse(cleanUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      return GFormParseResult(
        isValid: false,
        errors: ['Gagal mengakses Google Form: $e. Pastikan form terbuka untuk publik.'],
      );
    }

    if (response.statusCode != 200) {
      return GFormParseResult(
        isValid: false,
        errors: ['Google Form merespon dengan status code ${response.statusCode}. Pastikan link dapat diakses.'],
      );
    }

    final html = response.body;

    // Deteksi jika Google Form dibatasi khusus akun organisasi tertentu (Restricted Domain / Memerlukan Login)
    if (html.contains('ServiceLogin') ||
        html.contains('accounts.google.com') ||
        html.contains('Anda memerlukan izin') ||
        html.contains('You need permission') ||
        html.contains('form-restricted')) {
      return GFormParseResult(
        isValid: false,
        errors: [
          'Google Form ini dibatasi aksesnya (Restricted Domain / Memerlukan Login Google).',
          'Solusi: Buka Google Form Anda di browser > Setelan (Settings) > Respons > Nonaktifkan opsi "Batasi untuk pengguna di [Organisasi]" agar link publik dapat diimpor ke ExamGO.',
        ],
      );
    }

    // Cari blok script FB_PUBLIC_LOAD_DATA_
    final regex = RegExp(r'var\s+FB_PUBLIC_LOAD_DATA_\s*=\s*(.+?);\s*<\/script>', dotAll: true);
    final match = regex.firstMatch(html);
    if (match == null) {
      return GFormParseResult(
        isValid: false,
        errors: [
          'Tidak dapat mengekstrak data dari Google Form. '
          'Pastikan link merupakan link Google Form publik yang valid.',
        ],
      );
    }

    dynamic jsonData;
    try {
      jsonData = jsonDecode(match.group(1)!);
    } catch (e) {
      return GFormParseResult(
        isValid: false,
        errors: ['Gagal memproses struktur internal Google Form: $e'],
      );
    }

    if (jsonData is! List || jsonData.length < 2 || jsonData[1] is! List) {
      return GFormParseResult(
        isValid: false,
        errors: ['Struktur formulir Google Form tidak dikenali.'],
      );
    }

    final formInfo = jsonData[1] as List;
    final formTitle = formInfo.isNotEmpty && formInfo[0] != null
        ? formInfo[0].toString()
        : 'Ujian Google Form';

    final itemsList = formInfo.length > 1 && formInfo[1] is List ? formInfo[1] as List : [];
    if (itemsList.isEmpty) {
      return GFormParseResult(
        isValid: false,
        errors: ['Formulir Google Form tidak memiliki pertanyaan.'],
      );
    }

    final List<ExamQuestion> questions = [];
    int qNumber = 1;
    int skippedEssayCount = 0;

    for (final item in itemsList) {
      if (item is! List || item.length < 4) continue;

      final itemType = item.length > 3 && item[3] is int ? item[3] as int : -1;
      // 0: Short answer (Isian Singkat), 1: Paragraph (Esai), 13: File upload
      if (itemType == 0 || itemType == 1 || itemType == 13) {
        skippedEssayCount++;
        continue;
      }
      // 8: Section Header / Judul Bagian
      if (itemType == 8) {
        continue;
      }

      if (item.length < 5) continue;

      final qTitle = item[1]?.toString().trim() ?? '';
      final qDesc = item.length > 2 && item[2] != null ? item[2].toString().trim() : '';
      
      // Ambil opsi pilihan ganda
      final rawOptions = item[4] as List?;
      if (rawOptions == null || rawOptions.isEmpty || rawOptions[0] is! List) {
        if (itemType == 0 || itemType == 1) {
          skippedEssayCount++;
        }
        continue;
      }

      String fullPertanyaan = qTitle;
      if (qDesc.isNotEmpty) {
        fullPertanyaan += '\n$qDesc';
      }
      fullPertanyaan = _normalizeMathInText(fullPertanyaan);

      // Deteksi gambar di pertanyaan (item[6] atau item[8])
      String imgUrl = '';
      if (item.length > 6 && item[6] is List && (item[6] as List).isNotEmpty) {
        imgUrl = _extractImageUrl(item[6]);
      }
      if (imgUrl.isEmpty && item.length > 8 && item[8] is List && (item[8] as List).isNotEmpty) {
        imgUrl = _extractImageUrl(item[8]);
      }

      // ─── DUKUNGAN KISI PILIHAN GANDA / MULTIPLE CHOICE GRID (itemType == 7) ───
      if (itemType == 7 && rawOptions.length > 1) {
        for (int r = 0; r < rawOptions.length; r++) {
          final rowObj = rawOptions[r];
          if (rowObj is! List) continue;

          final rowCols = rowObj.length > 1 && rowObj[1] is List ? rowObj[1] as List : [];
          if (rowCols.isEmpty) continue;

          String rowTitle = '';
          if (rowObj.length > 3 && rowObj[3] != null) {
            rowTitle = rowObj[3].toString().trim();
          } else if (rowObj.length > 2 && rowObj[2] is String) {
            rowTitle = rowObj[2].toString().trim();
          }
          if (rowTitle.isEmpty) {
            rowTitle = 'Pernyataan ${r + 1}';
          }

          final fullGridPertanyaan = '$fullPertanyaan\n\n📌 $rowTitle';

          String oA = '', oB = '', oC = '', oD = '', oE = '';
          for (int c = 0; c < rowCols.length && c < 5; c++) {
            final colData = rowCols[c];
            if (colData is List && colData.isNotEmpty) {
              final colText = _normalizeMathInText(colData[0]?.toString() ?? '');
              switch (c) {
                case 0: oA = colText; break;
                case 1: oB = colText; break;
                case 2: oC = colText; break;
                case 3: oD = colText; break;
                case 4: oE = colText; break;
              }
            }
          }

          final detectedKey = _detectAnswerKey(item, rowCols);

          questions.add(ExamQuestion(
            soalId: 'GF_${qNumber}_${r + 1}',
            subtestId: 'ST1',
            nomorSoal: qNumber,
            pertanyaan: fullGridPertanyaan,
            opsiA: oA,
            opsiB: oB,
            opsiC: oC,
            opsiD: oD,
            opsiE: oE,
            kunci: detectedKey,
            gambar: imgUrl,
          ));
          qNumber++;
        }
        continue;
      }

      final optContainer = rawOptions[0] as List;
      final optItems = optContainer.length > 1 && optContainer[1] is List
          ? optContainer[1] as List
          : [];

      if (optItems.isEmpty) continue;

      // ─── DUKUNGAN SKALA LINIER (itemType == 5) ───
      if (itemType == 5 && optItems.isNotEmpty) {
        String minLabel = '';
        String maxLabel = '';
        if (optContainer.length > 3 && optContainer[3] is List && (optContainer[3] as List).isNotEmpty) {
          final labels = optContainer[3] as List;
          if (labels.isNotEmpty && labels[0] != null) minLabel = labels[0].toString().trim();
          if (labels.length > 1 && labels[1] != null) maxLabel = labels[1].toString().trim();
        }
        if (minLabel.isNotEmpty || maxLabel.isNotEmpty) {
          fullPertanyaan += '\n(Skala: $minLabel s.d. $maxLabel)';
        }
      }

      String oA = '', oB = '', oC = '', oD = '', oE = '';
      String gA = '', gB = '', gC = '', gD = '', gE = '';

      for (int i = 0; i < optItems.length; i++) {
        final optData = optItems[i];
        if (optData is List && optData.isNotEmpty) {
          final optText = _normalizeMathInText(optData[0]?.toString() ?? '');
          final optImg = _extractImageUrl(optData);

          switch (i) {
            case 0:
              oA = optText;
              gA = optImg;
              break;
            case 1:
              oB = optText;
              gB = optImg;
              break;
            case 2:
              oC = optText;
              gC = optImg;
              break;
            case 3:
              oD = optText;
              gD = optImg;
              break;
            case 4:
              oE = optText;
              gE = optImg;
              break;
          }
        }
      }

      // Deteksi kunci jawaban jika form mengekspos skor kuis
      final detectedKey = _detectAnswerKey(item, optItems);

      questions.add(ExamQuestion(
        soalId: 'GF_$qNumber',
        subtestId: 'ST1',
        nomorSoal: qNumber,
        pertanyaan: fullPertanyaan,
        opsiA: oA,
        opsiB: oB,
        opsiC: oC,
        opsiD: oD,
        opsiE: oE,
        gamA: gA,
        gamB: gB,
        gamC: gC,
        gamD: gD,
        gamE: gE,
        kunci: detectedKey,
        gambar: imgUrl,
      ));

      qNumber++;
    }

    if (questions.isEmpty) {
      return GFormParseResult(
        isValid: false,
        errors: ['Tidak ditemukan soal pilihan ganda di dalam Google Form tersebut.'],
      );
    }

    if (skippedEssayCount > 0) {
      warnings.add(
        'Ditemukan $skippedEssayCount butir soal bertipe Esai / Isian Singkat yang dilewati otomatis. '
        'Sistem penilaian otomatis CBT ExamGO saat ini dioptimalkan untuk butir Pilihan Ganda (A-E).',
      );
    }

    warnings.add(
      'Google Form merahasiakan kunci jawaban pada tautan publik (kebijakan anti-bocoran Google). '
      'Semua kunci default diatur ke "A". Anda dapat menyesuaikan kunci di preview satu per satu atau menggunakan fitur "⚡ Kunci Cepat" untuk menempelkan seluruh kunci sekaligus.',
    );

    final subtest = ExamSubtest(
      subtestId: 'ST1',
      paketId: '',
      judul: 'Soal Ujian',
      durasiMenit: defaultDurationMinutes,
      soalList: questions,
    );

    final package = ExamPackage(
      paketId: '',
      namaPaket: formTitle,
      kategori: defaultCategory,
      jenisWaktu: 'per_paket',
      durasiMenit: defaultDurationMinutes,
      subtests: [subtest],
      status: 'DRAFT',
    );

    return GFormParseResult(
      isValid: true,
      warnings: warnings,
      package: package,
    );
  }

  /// Ekstrak URL gambar baik dari link langsung, array metadata Google Form, maupun Google Drive
  static String _extractImageUrl(dynamic obj) {
    if (obj == null) return '';
    if (obj is String) {
      final s = obj.trim();
      if (s.startsWith('http://') || s.startsWith('https://')) {
        return MathHtmlFormatter.convertDriveUrl(s);
      }
      return '';
    }
    if (obj is List) {
      for (final el in obj) {
        final res = _extractImageUrl(el);
        if (res.isNotEmpty) return res;
      }
    }
    if (obj is Map) {
      for (final val in obj.values) {
        final res = _extractImageUrl(val);
        if (res.isNotEmpty) return res;
      }
    }
    return '';
  }

  /// Mendeteksi kunci jawaban jika form adalah kuis yang mengekspos skor
  static String _detectAnswerKey(dynamic item, List optItems) {
    for (int i = 0; i < optItems.length && i < 5; i++) {
      final opt = optItems[i];
      if (opt is List && opt.length > 2) {
        if (opt[2] == true || opt[2] == 1 || (opt.length > 4 && opt[4] == 1)) {
          return String.fromCharCode(65 + i);
        }
      }
    }

    try {
      if (item is List && item.length > 4 && item[4] is List && (item[4] as List).isNotEmpty) {
        final container = item[4][0];
        if (container is List && container.length > 2) {
          final gradingData = container.sublist(2);
          for (final grade in gradingData) {
            if (grade is List && grade.isNotEmpty) {
              final correctStr = grade.toString();
              for (int i = 0; i < optItems.length && i < 5; i++) {
                final opt = optItems[i];
                if (opt is List && opt.isNotEmpty && opt[0] != null) {
                  final text = opt[0].toString().trim();
                  if (text.isNotEmpty && correctStr.contains(text)) {
                    return String.fromCharCode(65 + i);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return 'A';
  }

  static String _normalizeMathInText(String text) {
    if (text.isEmpty) return '';
    return text;
  }
}

