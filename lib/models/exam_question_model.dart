import 'dart:convert';

/// Kategori Tryout / Ujian
class ExamCategory {
  static const String snbt = 'SNBT';
  static const String skd = 'SKD';
  static const String tkaSma = 'TKA SMA';
  static const String tkaSmp = 'TKA SMP';
  static const String tkaSd = 'TKA SD';
  static const String umum = 'UMUM';

  static const List<String> all = [
    snbt,
    skd,
    tkaSma,
    tkaSmp,
    tkaSd,
    umum,
  ];
}

/// Model untuk Paket Ujian
class ExamPackage {
  String paketId; // Token 6 karakter atau UUID
  String namaPaket;
  String kategori;
  String jenisWaktu; // 'per_subtest' atau 'per_paket'
  int durasiMenit;
  List<ExamSubtest> subtests;
  DateTime createdAt;
  String status; // 'ACTIVE', 'DRAFT', 'CLOSED'
  bool allowRetake; // Izinkan dikerjakan berulang kali
  bool isTeacherGenerated; // Ujian buatan guru mandiri (WebGAS / App)
  int passingGrade; // Ambang batas kelulusan / KKM Ujian UMUM (default: 75)
  bool randomizeQuestions; // Acak urutan butir soal per siswa (Anti-lirik sebangku)
  bool randomizeOptions; // Acak urutan opsi jawaban A-E per siswa

  ExamPackage({
    required this.paketId,
    required this.namaPaket,
    this.kategori = ExamCategory.umum,
    this.jenisWaktu = 'per_paket',
    this.durasiMenit = 90,
    List<ExamSubtest>? subtests,
    DateTime? createdAt,
    this.status = 'ACTIVE',
    this.allowRetake = true,
    this.isTeacherGenerated = false,
    this.passingGrade = 75,
    this.randomizeQuestions = true,
    this.randomizeOptions = false,
  })  : subtests = subtests ?? [],
        createdAt = createdAt ?? DateTime.now();

  int get totalSoal => subtests.fold(0, (sum, st) => sum + st.soalList.length);

  Map<String, dynamic> toFirestore() {
    return {
      'paket_id': paketId,
      'nama_paket': namaPaket,
      'kategori': kategori,
      'jenis_waktu': jenisWaktu,
      'durasi_menit': durasiMenit,
      'total_soal': totalSoal,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'allow_retake': allowRetake,
      'is_teacher_generated': isTeacherGenerated,
      'passing_grade': passingGrade,
      'randomize_questions': randomizeQuestions,
      'randomize_options': randomizeOptions,
      'subtest_count': subtests.length,
      // Ringkasan subtests disimpan di dokumen paket
      'subtests_meta': subtests.map((s) => s.toMetaJson()).toList(),
    };
  }

  factory ExamPackage.fromFirestore(Map<String, dynamic> data, String id) {
    return ExamPackage(
      paketId: data['paket_id']?.toString() ?? id,
      namaPaket: data['nama_paket']?.toString() ?? 'Ujian',
      kategori: data['kategori']?.toString() ?? data['jenis_test']?.toString() ?? ExamCategory.umum,
      jenisWaktu: data['jenis_waktu']?.toString() ?? 'per_paket',
      durasiMenit: (data['durasi_menit'] as num?)?.toInt() ?? 90,
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: data['status']?.toString() ?? 'ACTIVE',
      allowRetake: data['allow_retake'] != false && data['bisa_ulang'] != false,
      isTeacherGenerated: data['is_teacher_generated'] == true ||
          data['teacher_token'] != null ||
          data['is_webgas'] == true,
      passingGrade: (data['passing_grade'] as num?)?.toInt() ??
          (data['kkm'] as num?)?.toInt() ??
          75,
      randomizeQuestions: data['randomize_questions'] != false && data['acak_soal'] != false,
      randomizeOptions: data['randomize_options'] == true || data['acak_opsi'] == true,
    );
  }
}

/// Model untuk Subtest (Bagian dari Paket Ujian)
/// Guru dapat menambah, mengedit nama, dan mengatur durasi subtest.
class ExamSubtest {
  String subtestId;
  String paketId;
  String judul;
  int durasiMenit;
  int orderIndex;
  List<ExamQuestion> soalList;

  ExamSubtest({
    required this.subtestId,
    required this.paketId,
    required this.judul,
    this.durasiMenit = 30,
    this.orderIndex = 0,
    List<ExamQuestion>? soalList,
  }) : soalList = soalList ?? [];

  Map<String, dynamic> toMetaJson() {
    return {
      'subtest_id': subtestId,
      'judul': judul,
      'durasi_menit': durasiMenit,
      'jumlah_soal': soalList.length,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'subtest_id': subtestId,
      'paket_id': paketId,
      'judul_subtest': judul,
      'durasi_menit': durasiMenit,
      'soal_count': soalList.length,
    };
  }

  factory ExamSubtest.fromFirestore(Map<String, dynamic> data, String id) {
    return ExamSubtest(
      subtestId: data['subtest_id']?.toString() ?? id,
      paketId: data['paket_id']?.toString() ?? '',
      judul: data['judul_subtest']?.toString() ?? data['judul']?.toString() ?? 'Subtest',
      durasiMenit: (data['durasi_menit'] as num?)?.toInt() ?? 30,
      orderIndex: (data['order_index'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Model Butir Soal Ujian (Format LaTeX & Gambar Google Drive)
class ExamQuestion {
  String soalId;
  String subtestId;
  int nomorSoal;
  String pertanyaan;
  String opsiA;
  String opsiB;
  String opsiC;
  String opsiD;
  String opsiE;
  String gamA;
  String gamB;
  String gamC;
  String gamD;
  String gamE;
  String kunci; // 'A', 'B', 'C', 'D', 'E'
  String pembahasan;
  String gambar; // URL Google Drive
  String tabel;

  ExamQuestion({
    required this.soalId,
    required this.subtestId,
    required this.nomorSoal,
    required this.pertanyaan,
    this.opsiA = '',
    this.opsiB = '',
    this.opsiC = '',
    this.opsiD = '',
    this.opsiE = '',
    this.gamA = '',
    this.gamB = '',
    this.gamC = '',
    this.gamD = '',
    this.gamE = '',
    this.kunci = 'A',
    this.pembahasan = '',
    this.gambar = '',
    this.tabel = '',
  });

  Map<String, dynamic> toFirestore() {
    return {
      'soal_id': soalId,
      'subtest_id': subtestId,
      'nomor_soal': nomorSoal,
      'pertanyaan': pertanyaan,
      'opsi_a': opsiA,
      'opsi_b': opsiB,
      'opsi_c': opsiC,
      'opsi_d': opsiD,
      'opsi_e': opsiE,
      'gam_a': gamA,
      'gam_b': gamB,
      'gam_c': gamC,
      'gam_d': gamD,
      'gam_e': gamE,
      'kunci': kunci.toUpperCase(),
      'pembahasan': pembahasan,
      'gambar': gambar,
      'tabel': tabel,
    };
  }

  factory ExamQuestion.fromFirestore(Map<String, dynamic> j, String id) {
    String a = j['opsi_a']?.toString() ?? j['a']?.toString() ?? '';
    String b = j['opsi_b']?.toString() ?? j['b']?.toString() ?? '';
    String c = j['opsi_c']?.toString() ?? j['c']?.toString() ?? '';
    String d = j['opsi_d']?.toString() ?? j['d']?.toString() ?? '';
    String e = j['opsi_e']?.toString() ?? j['e']?.toString() ?? '';

    // Dukung juga format opsi_jawaban / opsi_jawaban_parsed jika ada
    if (a.isEmpty && (j['opsi_jawaban'] != null || j['opsi_jawaban_parsed'] != null)) {
      try {
        final rawOpsi = j['opsi_jawaban_parsed'] ?? j['opsi_jawaban'];
        Map<String, dynamic>? map;
        if (rawOpsi is Map) {
          map = Map<String, dynamic>.from(rawOpsi);
        } else if (rawOpsi is String && rawOpsi.trim().startsWith('{')) {
          map = jsonDecode(rawOpsi.trim()) as Map<String, dynamic>;
        }
        if (map != null) {
          a = map['A']?.toString() ?? map['a']?.toString() ?? a;
          b = map['B']?.toString() ?? map['b']?.toString() ?? b;
          c = map['C']?.toString() ?? map['c']?.toString() ?? c;
          d = map['D']?.toString() ?? map['d']?.toString() ?? d;
          e = map['E']?.toString() ?? map['e']?.toString() ?? e;
        }
      } catch (_) {}
    }

    return ExamQuestion(
      soalId: j['soal_id']?.toString() ?? id,
      subtestId: j['subtest_id']?.toString() ?? '',
      nomorSoal: (j['nomor_soal'] as num?)?.toInt() ?? 1,
      pertanyaan: j['pertanyaan']?.toString() ?? j['soal']?.toString() ?? '',
      opsiA: a,
      opsiB: b,
      opsiC: c,
      opsiD: d,
      opsiE: e,
      gamA: j['gam_a']?.toString() ?? '',
      gamB: j['gam_b']?.toString() ?? '',
      gamC: j['gam_c']?.toString() ?? '',
      gamD: j['gam_d']?.toString() ?? '',
      gamE: j['gam_e']?.toString() ?? '',
      kunci: (j['kunci']?.toString() ?? j['kunci_jawaban']?.toString() ?? 'A').toUpperCase(),
      pembahasan: j['pembahasan']?.toString() ?? '',
      gambar: j['gambar']?.toString() ?? j['gambar_soal']?.toString() ?? '',
      tabel: j['tabel']?.toString() ?? j['baris_tabel']?.toString() ?? '',
    );
  }
}

