/// Model data paket & jadwal tryout resmi dari Admin ExamGO
class TryoutSchedule {
  final String paketId;
  final String namaPaket;
  final String jenisTest; // 'SNBT', 'SKD', 'TKA', dll.
  final String jenisWaktu; // 'per_subtest' atau 'total'
  final int durasiMenit;
  final String tanggal; // YYYY-MM-DD
  final String jamMulai; // HH:mm
  final String jamSelesai; // HH:mm
  final int totalSoal;
  final String status; // 'aktif' atau 'nonaktif'
  final List<String> subtests;
  final bool isLifetime; // Selalu aktif / tanpa batasan tanggal & jam
  final bool allowRetake; // Bisa dikerjakan berulang kali oleh user

  const TryoutSchedule({
    required this.paketId,
    required this.namaPaket,
    required this.jenisTest,
    this.jenisWaktu = 'per_subtest',
    this.durasiMenit = 90,
    required this.tanggal,
    this.jamMulai = '08:00',
    this.jamSelesai = '23:59',
    this.totalSoal = 0,
    this.status = 'aktif',
    this.subtests = const [],
    this.isLifetime = false,
    this.allowRetake = true,
  });

  factory TryoutSchedule.fromMap(String id, Map<String, dynamic> data) {
    final subList = <String>[];
    if (data['subtests'] is List) {
      for (final s in (data['subtests'] as List)) {
        if (s is Map && s['nama'] != null) {
          subList.add(s['nama'].toString());
        } else if (s is String) {
          subList.add(s);
        }
      }
    }

    return TryoutSchedule(
      paketId: id,
      namaPaket: data['nama_paket']?.toString() ?? data['nama_ujian']?.toString() ?? 'Tryout Nasional',
      jenisTest: (data['jenis_test']?.toString() ?? 'UMUM').toUpperCase(),
      jenisWaktu: data['jenis_waktu']?.toString() ?? 'per_subtest',
      durasiMenit: (data['durasi_menit'] as num?)?.toInt() ?? 90,
      tanggal: data['tanggal']?.toString() ?? '',
      jamMulai: data['jam_mulai']?.toString() ?? '08:00',
      jamSelesai: data['jam_selesai']?.toString() ?? '23:59',
      totalSoal: (data['total_soal'] as num?)?.toInt() ?? (data['soal_count'] as num?)?.toInt() ?? 0,
      status: data['status']?.toString().toLowerCase() ?? 'aktif',
      subtests: subList,
      isLifetime: data['is_lifetime'] == true || data['lifetime'] == true,
      allowRetake: data['allow_retake'] != false && data['bisa_ulang'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nama_paket': namaPaket,
      'jenis_test': jenisTest,
      'jenis_waktu': jenisWaktu,
      'durasi_menit': durasiMenit,
      'tanggal': tanggal,
      'jam_mulai': jamMulai,
      'jam_selesai': jamSelesai,
      'total_soal': totalSoal,
      'status': status,
      'subtests': subtests,
      'is_lifetime': isLifetime,
      'allow_retake': allowRetake,
    };
  }

  bool get isActive => status == 'aktif';

  bool get isToday {
    if (isLifetime) return true;
    if (tanggal.isEmpty) return true; // Anggap bisa dikerjakan jika tanggal belum diatur
    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return tanggal == todayStr;
  }

  bool get isUpcoming {
    if (isLifetime) return false;
    if (tanggal.isEmpty) return false;
    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return tanggal.compareTo(todayStr) > 0;
  }

  bool get isPast {
    if (isLifetime) return false;
    if (tanggal.isEmpty) return false;
    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return tanggal.compareTo(todayStr) < 0;
  }

  String get badgeStatus {
    if (isLifetime) return 'Selalu Aktif';
    if (isToday) return 'Hari Ini';
    if (isUpcoming) return 'Mendatang';
    return 'Selesai';
  }
}

