import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Layanan sinkronisasi dan verifikasi waktu terpercaya (Trusted Server Time)
/// dengan arsitektur 3 lapis:
/// 1. HTTP Date Header (TCP 443 Google/Firebase/Cloudflare)
/// 2. UDP NTP Protocol (Port 123 time.google.com / pool.ntp.org)
/// 3. Hardware Monotonic Elapsed Realtime (SystemClock Android/iOS)
class TrustedTimeService {
  TrustedTimeService._();
  static final TrustedTimeService instance = TrustedTimeService._();

  static const MethodChannel _securityChannel =
      MethodChannel('com.examgo/locktask');

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

  /// Mengambil elapsed realtime perangkat keras (dalam milidetik)
  /// Nilai ini dihitung oleh CPU hardware sejak boot, kebal terhadap manipulasi jam sistem.
  Future<int?> getElapsedRealtime() async {
    try {
      final res =
          await _securityChannel.invokeMethod<int>('getElapsedRealtime');
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Sinkronisasi waktu dengan server terpercaya melalui HTTP Date Header (Layer 1)
  /// dan fallback ke UDP NTP (Layer 2)
  Future<DateTime> syncWithServer() async {
    // 1. Coba HTTP Date Header (Port 443 - kebal pemblokiran firewall)
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
            '[TrustedTimeService] Sinkronisasi HTTP sukses via $uri. Offset: ${_serverOffset.inSeconds} detik',
          );
          return serverDate;
        }
      } catch (_) {}
    }

    // 2. Fallback: Coba UDP NTP Protocol (Port 123)
    try {
      final ntpDate = await queryNtpServer();
      if (ntpDate != null) {
        final localNow = DateTime.now();
        _serverOffset = ntpDate.difference(localNow);
        _lastSyncedAt = localNow;
        _isSynced = true;

        debugPrint(
          '[TrustedTimeService] Sinkronisasi UDP NTP sukses. Offset: ${_serverOffset.inSeconds} detik',
        );
        return ntpDate;
      }
    } catch (_) {}

    // Jika offline/gagal, gunakan waktu lokal disesuaikan dengan offset terakhir
    return DateTime.now().add(_serverOffset);
  }

  /// Kueri langsung ke server NTP resmi melalui UDP Datagram Socket murni
  Future<DateTime?> queryNtpServer([String host = 'time.google.com']) async {
    RawDatagramSocket? socket;
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) return null;
      final address = addresses.first;

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      // Paket NTP 48 bytes (LI=0, VN=3, Mode=3 client)
      final ntpData = Uint8List(48);
      ntpData[0] = 0x1B;

      socket.send(ntpData, address, 123);

      final completer = Completer<DateTime?>();
      late StreamSubscription sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null && datagram.data.length >= 48) {
            final data = datagram.data;
            final secondsSince1900 = (data[40] << 24) |
                (data[41] << 16) |
                (data[42] << 8) |
                data[43];
            final unixSeconds = secondsSince1900 - 2208988800;
            if (unixSeconds > 0) {
              final ntpTime = DateTime.fromMillisecondsSinceEpoch(
                unixSeconds * 1000,
                isUtc: true,
              ).toLocal();
              completer.complete(ntpTime);
            } else {
              completer.complete(null);
            }
          }
        }
      });

      return await completer.future
          .timeout(
            const Duration(milliseconds: 2000),
            onTimeout: () => null,
          )
          .whenComplete(() {
            sub.cancel();
          });
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Mengambil waktu saat ini yang telah disinkronkan dengan server
  Future<DateTime> getTrustedNow({bool forceRefresh = false}) async {
    if (!_isSynced ||
        forceRefresh ||
        _lastSyncedAt == null ||
        DateTime.now().difference(_lastSyncedAt!) >
            const Duration(minutes: 15)) {
      try {
        return await syncWithServer();
      } catch (_) {}
    }
    return DateTime.now().add(_serverOffset);
  }

  /// Memverifikasi apakah waktu ujian resmi telah benar-benar berakhir
  /// Mencegah kecurangan siswa memajukan jam perangkat untuk membuka pembahasan lebih awal:
  /// - Online: diverifikasi melalui HTTP Date Header & UDP NTP.
  /// - Offline: diverifikasi melalui hardware elapsed realtime (kebal perubahan jam sistem).
  Future<bool> isExamTimeEnded({
    required DateTime? examEndTime,
    DateTime? submittedAt,
    int? elapsedRealtimeMs,
  }) async {
    if (examEndTime == null) return true;

    // 1. Verifikasi Online: Cek terhadap Waktu Server Terpercaya
    try {
      final trustedNow = await getTrustedNow();
      if (_isSynced) {
        if (trustedNow.isBefore(examEndTime)) {
          debugPrint(
            '[TrustedTimeService] Ujian belum berakhir berdasarkan waktu server. Server: $trustedNow, End: $examEndTime',
          );
          return false;
        }
        return true;
      }
    } catch (_) {}

    // 2. Verifikasi Offline: Cek Hardware Monotonic Elapsed Realtime
    if (submittedAt != null &&
        elapsedRealtimeMs != null &&
        elapsedRealtimeMs > 0) {
      final currentElapsed = await getElapsedRealtime();
      if (currentElapsed != null && currentElapsed >= elapsedRealtimeMs) {
        final realPhysicalPassedMs = currentElapsed - elapsedRealtimeMs;
        final requiredWaitMs =
            examEndTime.difference(submittedAt).inMilliseconds;
        if (realPhysicalPassedMs < requiredWaitMs) {
          // Siswa mengubah jam sistem manual saat offline!
          debugPrint(
            '[Anti-Cheat] Deteksi manipulasi jam! Waktu fisik baru berjalan ${realPhysicalPassedMs}ms < syarat ${requiredWaitMs}ms',
          );
          return false;
        }
      }
    }

    // 3. Monotonic Sanity Check jika jam lokal melompat aneh
    final localNow = DateTime.now();
    return localNow.isAfter(examEndTime);
  }
}
