/// Helper pemformatan dan parsing tanggal, hari, jam, dan zona waktu Indonesia (WITA/WIB/WIT)
/// Dirancang untuk menangani berbagai format input (JS Date string, ISO, Indo text) secara elegan dan bebas error.
class IndoDateFormatter {
  IndoDateFormatter._();

  static const List<String> _daysIndo = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  static const List<String> _monthsIndo = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const List<String> _monthsIndoShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Ags',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static const Map<String, int> _enMonthMap = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Deteksi zona waktu dari teks atau default ke WITA (Makassar)
  static String detectTimeZone(String? rawString) {
    if (rawString == null || rawString.isEmpty) return 'WITA';
    final s = rawString.toUpperCase();
    if (s.contains('GMT+0700') || s.contains('WIB') || s.contains('JAKARTA')) {
      return 'WIB';
    }
    if (s.contains('GMT+0900') || s.contains('WIT') || s.contains('JAYAPURA')) {
      return 'WIT';
    }
    if (s.contains('GMT+0800') || s.contains('WITA') || s.contains('MAKASSAR') || s.contains('INDONESIA TENGAH')) {
      return 'WITA';
    }
    return 'WITA';
  }

  /// Parsing berbagai format string tanggal menjadi DateTime
  static DateTime? parse(String? rawDateStr) {
    if (rawDateStr == null || rawDateStr.trim().isEmpty) return null;
    final clean = rawDateStr.trim();

    // 1. Coba ISO format standard (YYYY-MM-DD)
    final iso = DateTime.tryParse(clean);
    if (iso != null) return iso;

    // 2. Coba format JavaScript toString(): "Wed Sep 09 2026 08:00:00 GMT+0800 (Waktu Indonesia Tengah)"
    final jsReg = RegExp(r'([A-Za-z]{3})\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})');
    final match = jsReg.firstMatch(clean);
    if (match != null) {
      final monStr = match.group(2)!.toLowerCase();
      final day = int.tryParse(match.group(3)!) ?? 1;
      final year = int.tryParse(match.group(4)!) ?? 2026;
      final month = _enMonthMap[monStr] ?? 1;

      // Cek apakah ada jam:menit:detik
      final timeReg = RegExp(r'(\d{2}):(\d{2}):(\d{2})');
      final timeMatch = timeReg.firstMatch(clean);
      if (timeMatch != null) {
        final hour = int.tryParse(timeMatch.group(1)!) ?? 0;
        final min = int.tryParse(timeMatch.group(2)!) ?? 0;
        final sec = int.tryParse(timeMatch.group(3)!) ?? 0;
        return DateTime(year, month, day, hour, min, sec);
      }
      return DateTime(year, month, day);
    }

    // 3. Coba format slash: DD/MM/YYYY
    if (clean.contains('/')) {
      final parts = clean.split('/');
      if (parts.length == 3) {
        final p0 = int.tryParse(parts[0]) ?? 0;
        final p1 = int.tryParse(parts[1]) ?? 0;
        final p2 = int.tryParse(parts[2]) ?? 0;
        if (p2 > 1000) {
          // DD/MM/YYYY
          return DateTime(p2, p1, p0);
        } else if (p0 > 1000) {
          // YYYY/MM/DD
          return DateTime(p0, p1, p2);
        }
      }
    }

    // 4. Coba format dash: DD-MM-YYYY
    if (clean.contains('-')) {
      final parts = clean.split('-');
      if (parts.length == 3) {
        final p0 = int.tryParse(parts[0]) ?? 0;
        final p1 = int.tryParse(parts[1]) ?? 0;
        final p2 = int.tryParse(parts[2]) ?? 0;
        if (p0 > 1000) {
          // YYYY-MM-DD
          return DateTime(p0, p1, p2);
        } else if (p2 > 1000) {
          // DD-MM-YYYY
          return DateTime(p2, p1, p0);
        }
      }
    }

    return null;
  }

  /// Format Hari dan Tanggal Standar Indonesia, contoh: "Rabu, 9 September 2026"
  static String formatHariTanggal(String? rawDateStr, {bool shortMonth = false}) {
    final dt = parse(rawDateStr);
    if (dt == null) {
      if (rawDateStr == null || rawDateStr.isEmpty) return 'Fleksibel';
      return rawDateStr;
    }

    final dayName = _daysIndo[dt.weekday % 7];
    final monthName = shortMonth ? _monthsIndoShort[dt.month - 1] : _monthsIndo[dt.month - 1];
    return '$dayName, ${dt.day} $monthName ${dt.year}';
  }

  /// Format Jam Pelaksanaan Ujian dengan Zona Waktu (WITA/WIB/WIT), contoh: "17:34 - 23:59 WITA"
  static String formatJam(String jamMulai, String jamSelesai, {String? rawDateStr}) {
    final tz = detectTimeZone(rawDateStr);
    final jM = jamMulai.trim().isEmpty ? '08:00' : jamMulai.trim();
    final jS = jamSelesai.trim().isEmpty ? '23:59' : jamSelesai.trim();

    return '$jM - $jS $tz';
  }

  /// Format Ringkas untuk Kartu agar tidak Overflex di layar kecil
  /// Contoh: "Rabu, 9 Sep 2026 • 17:34 - 23:59 WITA"
  static String formatJadwalRingkas(
    String? rawDateStr,
    String jamMulai,
    String jamSelesai, {
    bool isLifetime = false,
  }) {
    if (isLifetime || rawDateStr == null || rawDateStr.trim().isEmpty) {
      return 'Selalu Aktif (Tanpa Batas Waktu)';
    }

    final dt = parse(rawDateStr);
    if (dt == null) {
      return rawDateStr.length > 25 ? '${rawDateStr.substring(0, 22)}...' : rawDateStr;
    }

    final dayName = _daysIndo[dt.weekday % 7];
    final monthShort = _monthsIndoShort[dt.month - 1];
    final tz = detectTimeZone(rawDateStr);

    final jM = jamMulai.trim().isEmpty ? '08:00' : jamMulai.trim();
    final jS = jamSelesai.trim().isEmpty ? '23:59' : jamSelesai.trim();

    return '$dayName, ${dt.day} $monthShort ${dt.year} • $jM-$jS $tz';
  }
}
