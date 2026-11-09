import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/services/license_service.dart';
import 'package:examgo/services/student_tryout_history_service.dart';
import 'package:examgo/services/tryout_reminder_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TryoutReminderService Tests', () {
    test('markTryoutsAsSeen and getSeenTryoutIds persists IDs', () async {
      final service = TryoutReminderService.instance;
      var seen = await service.getSeenTryoutIds();
      expect(seen.isEmpty, isTrue);

      await service.markTryoutsAsSeen(['paket_1', 'paket_2']);
      seen = await service.getSeenTryoutIds();
      expect(seen.contains('paket_1'), isTrue);
      expect(seen.contains('paket_2'), isTrue);
      expect(seen.contains('paket_3'), isFalse);
    });

    test('getNewUnattemptedCount returns 0 for non-premium student', () async {
      final service = TryoutReminderService.instance;
      final schedules = [
        const TryoutSchedule(
          paketId: 'SNBT-01',
          namaPaket: 'SNBT Baru 2026',
          jenisTest: 'SNBT',
          jenisWaktu: 'per_paket',
          durasiMenit: 90,
          tanggal: '2026-11-09',
          jamMulai: '08:00',
          jamSelesai: '12:00',
          totalSoal: 20,
          status: 'aktif',
          subtests: ['PU', 'PK'],
          isLifetime: false,
          allowRetake: true,
        ),
      ];

      final count = await service.getNewUnattemptedCount(preloadedSchedules: schedules);
      // Siswa belum premium => 0
      expect(count, 0);
    });

    test('getNewUnattemptedCount counts unattempted new tryouts when premium', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('license_student_is_premium', true);

      final service = TryoutReminderService.instance;
      final schedules = [
        const TryoutSchedule(
          paketId: 'SNBT-01',
          namaPaket: 'SNBT Baru 2026',
          jenisTest: 'SNBT',
          jenisWaktu: 'per_paket',
          durasiMenit: 90,
          tanggal: '2026-11-09',
          jamMulai: '08:00',
          jamSelesai: '12:00',
          totalSoal: 20,
          status: 'aktif',
          subtests: ['PU', 'PK'],
          isLifetime: false,
          allowRetake: true,
        ),
        const TryoutSchedule(
          paketId: 'SKD-01',
          namaPaket: 'SKD CPNS 2026',
          jenisTest: 'SKD',
          jenisWaktu: 'per_paket',
          durasiMenit: 100,
          tanggal: '2026-11-08',
          jamMulai: '08:00',
          jamSelesai: '12:00',
          totalSoal: 30,
          status: 'aktif',
          subtests: ['TWK'],
          isLifetime: false,
          allowRetake: true,
        ),
      ];

      final count = await service.getNewUnattemptedCount(preloadedSchedules: schedules);
      expect(count, 2);

      // Tandai 1 sudah dikerjakan di history
      final historyItem = StudentTryoutHistoryItem(
        token: 'SNBT-01',
        namaPaket: 'SNBT Baru 2026',
        kategori: 'SNBT',
        submittedAt: DateTime.now(),
        finalScore: 800,
        maxScore: 1000,
        totalBenar: 16,
        totalSalah: 4,
        totalKosong: 0,
        totalSoal: 20,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'A',
        allowRetake: true,
        jawaban: {},
        questions: [],
      );
      final rawList = [historyItem].map((e) => e.toJson()).toList();
      // Simpan ke SharedPreferences
      await prefs.setStringList('student_tryout_history_list', [
        '{"token":"SNBT-01","nama_paket":"SNBT Baru 2026","kategori":"SNBT","final_score":800,"max_score":1000,"total_benar":16,"total_salah":4,"total_kosong":0,"total_soal":20,"is_passed":true,"status_kelulusan":"LULUS","predikat":"A","allow_retake":true,"jawaban":{},"questions":[]}'
      ]);

      // Sekarang hanya SKD-01 yang belum dikerjakan
      final countAfterHistory = await service.getNewUnattemptedCount(preloadedSchedules: schedules);
      expect(countAfterHistory, 1);
    });

    test('checkAndSendLocalReminder triggers for unattempted or retake candidate', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('license_student_is_premium', true);

      final service = TryoutReminderService.instance;
      final schedules = [
        const TryoutSchedule(
          paketId: 'SNBT-UNATTEMPTED',
          namaPaket: 'Paket Belum Dikerjakan',
          jenisTest: 'SNBT',
          jenisWaktu: 'per_paket',
          durasiMenit: 90,
          tanggal: '2026-11-09',
          jamMulai: '08:00',
          jamSelesai: '12:00',
          totalSoal: 20,
          status: 'aktif',
          subtests: ['PU'],
          isLifetime: false,
          allowRetake: true,
        ),
      ];

      final sent = await service.checkAndSendLocalReminder(
        preloadedSchedules: schedules,
        ignoreCooldown: true,
      );
      expect(sent, isTrue);
    });
  });
}
