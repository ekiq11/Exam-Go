import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/models/tryout_schedule_model.dart';

void main() {
  group('TryoutSchedule Model Tests', () {
    test('fromMap sets default values when optional fields are null', () {
      final data = {
        'nama_paket': 'Tryout Akbar SNBT 2026',
        'jenis_test': 'SNBT',
      };

      final schedule = TryoutSchedule.fromMap('doc-01', data);

      expect(schedule.paketId, 'doc-01');
      expect(schedule.namaPaket, 'Tryout Akbar SNBT 2026');
      expect(schedule.jenisTest, 'SNBT');
      expect(schedule.durasiMenit, 90);
      expect(schedule.totalSoal, 0);
      expect(schedule.status, 'aktif');
      expect(schedule.isActive, isTrue);
    });

    test('badgeStatus detects Today, Upcoming, and Completed correctly', () {
      final now = DateTime.now();
      final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final scheduleToday = TryoutSchedule.fromMap('TO-TODAY', {
        'nama_paket': 'Tryout Hari Ini',
        'tanggal': todayStr,
      });

      expect(scheduleToday.isToday, isTrue);
      expect(scheduleToday.badgeStatus, 'Hari Ini');

      final tomorrow = now.add(const Duration(days: 2));
      final tomorrowStr = '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      final scheduleUpcoming = TryoutSchedule.fromMap('TO-UPCOMING', {
        'nama_paket': 'Tryout Mendatang',
        'tanggal': tomorrowStr,
      });

      expect(scheduleUpcoming.isUpcoming, isTrue);
      expect(scheduleUpcoming.badgeStatus, 'Mendatang');

      final pastStr = '2020-01-01';
      final schedulePast = TryoutSchedule.fromMap('TO-PAST', {
        'nama_paket': 'Tryout Lama',
        'tanggal': pastStr,
      });

      expect(schedulePast.badgeStatus, 'Selesai');
    });

    test('toMap creates valid map matching Firestore schema', () {
      const schedule = TryoutSchedule(
        paketId: 'TO-SNBT',
        namaPaket: 'Tryout SNBT Gelombang 1',
        jenisTest: 'SNBT',
        jenisWaktu: 'total',
        tanggal: '2026-12-01',
        jamMulai: '08:00',
        jamSelesai: '23:59',
        durasiMenit: 120,
        totalSoal: 50,
        status: 'aktif',
        subtests: ['TPS', 'Literasi Bahasa', 'Penalaran Matematika'],
      );

      final map = schedule.toMap();

      expect(map['nama_paket'], 'Tryout SNBT Gelombang 1');
      expect(map['jenis_test'], 'SNBT');
      expect(map['durasi_menit'], 120);
      expect(map['total_soal'], 50);
      expect(map['subtests'], hasLength(3));
    });
  });
}
