import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Layanan sinkronisasi dan verifikasi waktu terpercaya (Trusted Server Time)
/// untuk mencegah manipulasi jam HP manual oleh siswa selama/setelah ujian.
class TrustedTimeService {
  TrustedTimeService._();
  static final TrustedTimeService instance = TrustedTimeService._();

  /// Selisih waktu antara jam lokal HP dengan jam server resmi (Server - Local)
  Duration _serverOffset = Duration.zero;
  DateTime? _lastSyncedAt;
  bool _isSynced = false;

  /// Stopwatch monotonik lokal yang kebal terhadap pengubahan jam sistem oleh pengguna
  final Stopwatch _monotonicStopwatch = Stopwatch()..start();

  /// Waktu monotonik yang telah berlalu sejak service diinisialisasi
  Duration get monotonicElapsed => _monotonicStopwatch.elapsed;

  /// Apakah waktu sudah pernah disinkronkan dengan server resmi
  bool get isSynced => _isSynced;

  /// Sinkronisasi waktu dengan server terpercaya melalui HTTP Date Header
  /// (Menggunakan request HEAD super ringan ~100ms ke endpoint terpercaya)
  Future<DateTime> syncWithServer() async {
    final candidateEndpoints = [
      Uri.parse('https://www.google.com/generate_204'),
      Uri.parse('https://firebase.google.com'),
      Uri.parse('https://cloudflare.com'),
    ];

    for (final uri in candidateEndpoints) {
      try {
        final client = http.Client();
        final response = await client
            .head(uri)
            .timeout(const Duration(milliseconds: 2500));
        client.close();

        final dateHeader = response.headers['date'];
        if (dateHeader != null && dateHeader.isNotEmpty) {
          final serverDate = HttpDate.parse(dateHeader);
          final localNow = DateTime.now();

          _serverOffset = serverDate.difference(localNow);
          _lastSyncedAt = localNow;
          _isSynced = true;

          debugPrint(
            '[TrustedTimeService] Sinkronisasi sukses via $uri. Offset: ${_serverOffset.inSeconds} detik',
          );
          return serverDate;
        }
      } catch (e) {
        debugPrint('[TrustedTimeService] Gagal menghubungi $uri: $e');
      }
    }

    // Jika offline/gagal, gunakan waktu lokal disesuaikan dengan offset terakhir
    return DateTime.now().add(_serverOffset);
  }

  /// Mengambil waktu saat ini yang telah disinkronkan dengan server
  Future<DateTime> getTrustedNow({bool forceRefresh = false}) async {
    // Sinkronisasi ulang jika belum pernah atau sudah lewat dari 15 menit
    if (!_isSynced ||
        forceRefresh ||
        _lastSyncedAt == null ||
        DateTime.now().difference(_lastSyncedAt!) > const Duration(minutes: 15)) {
      try {
        return await syncWithServer();
      } catch (_) {}
    }
    return DateTime.now().add(_serverOffset);
  }

  /// Memverifikasi apakah waktu ujian resmi telah benar-benar berakhir
  /// Mencegah kecurangan siswa memajukan jam perangkat untuk membuka pembahasan lebih awal.
  Future<bool> isExamTimeEnded({
    required DateTime? examEndTime,
    DateTime? submittedAt,
  }) async {
    if (examEndTime == null) return true;

    // 1. Cek terhadap Waktu Server Terpercaya (Anti-Spoofing)
    final trustedNow = await getTrustedNow();
    if (trustedNow.isBefore(examEndTime)) {
      debugPrint(
        '[TrustedTimeService] Ujian belum berakhir berdasarkan waktu server. Server: $trustedNow, End: $examEndTime',
      );
      return false;
    }

    // 2. Monotonic Sanity Check jika ada data waktu pengerjaan
    // Jika jam lokal sengaja dimajukan drastis dibanding waktu server
    final localNow = DateTime.now();
    if (localNow.difference(trustedNow).abs() > const Duration(minutes: 10)) {
      debugPrint(
        '[TrustedTimeService] Terdeteksi perbedaan jam lokal dan server > 10 menit. Mengutamakan waktu server.',
      );
      if (trustedNow.isBefore(examEndTime)) {
        return false;
      }
    }

    return true;
  }
}
