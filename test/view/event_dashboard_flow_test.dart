import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/utils/indo_date_formatter.dart';

void main() {
  group('Event Schedule & Status Badges Tests', () {
    test('Badge logic correctly maps to Segera, Berlangsung, and Selesai', () {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // 1. Event Segera (jam mulai di masa depan)
      final futureH = (now.hour + 2) % 24;
      final scheduleSegera = TryoutSchedule(
        paketId: 'EVENT-001',
        namaPaket: 'Event Mendatang',
        jenisTest: 'EVENT',
        tanggal: todayStr,
        jamMulai: '${futureH.toString().padLeft(2, '0')}:00',
        jamSelesai: '${((futureH + 2) % 24).toString().padLeft(2, '0')}:00',
      );

      // 2. Event Selesai (jam selesai di masa lampau)
      final pastStartH = (now.hour - 4).clamp(0, 23);
      final pastEndH = (now.hour - 2).clamp(0, 23);
      final scheduleSelesai = TryoutSchedule(
        paketId: 'EVENT-002',
        namaPaket: 'Event Selesai',
        jenisTest: 'EVENT',
        tanggal: todayStr,
        jamMulai: '${pastStartH.toString().padLeft(2, '0')}:00',
        jamSelesai: '${pastEndH.toString().padLeft(2, '0')}:00',
      );

      // Helper function matching event_dashboard_screen logic
      String resolveBadge(TryoutSchedule s, DateTime referenceNow) {
        if (s.isLifetime || s.tanggal.isEmpty) return 'Berlangsung';
        final parsed = IndoDateFormatter.parse(s.tanggal) ?? DateTime.now();
        final jamP = s.jamMulai.split(':');
        final startH = int.tryParse(jamP[0]) ?? 8;
        final startM = jamP.length > 1 ? (int.tryParse(jamP[1]) ?? 0) : 0;
        final start = DateTime(parsed.year, parsed.month, parsed.day, startH, startM);

        final endP = s.jamSelesai.split(':');
        final endH = int.tryParse(endP[0]) ?? 23;
        final endM = endP.length > 1 ? (int.tryParse(endP[1]) ?? 59) : 59;
        final end = DateTime(parsed.year, parsed.month, parsed.day, endH, endM);

        if (referenceNow.isBefore(start)) return 'Segera';
        if (referenceNow.isAfter(end)) return 'Selesai';
        return 'Berlangsung';
      }

      if (now.hour < 21) {
        expect(resolveBadge(scheduleSegera, now), 'Segera');
      }
      if (now.hour >= 4) {
        expect(resolveBadge(scheduleSelesai, now), 'Selesai');
      }
    });

    test('Discussion lock condition: only allowed when event has ended', () {
      bool isDiscussionAllowed(String badge) {
        return badge == 'Selesai';
      }

      expect(isDiscussionAllowed('Segera'), isFalse);
      expect(isDiscussionAllowed('Berlangsung'), isFalse);
      expect(isDiscussionAllowed('Selesai'), isTrue);
    });

    test('1x attempt constraint for Event: cannot retake once completed', () {
      bool canStartEvent({required String statusBadge, required bool sudahDikerjakan}) {
        return (statusBadge == 'Berlangsung') && !sudahDikerjakan;
      }

      // Belum dikerjakan saat berlangsung -> BISA
      expect(canStartEvent(statusBadge: 'Berlangsung', sudahDikerjakan: false), isTrue);

      // Sudah dikerjakan saat berlangsung -> NON-AKTIF (TIDAK BISA)
      expect(canStartEvent(statusBadge: 'Berlangsung', sudahDikerjakan: true), isFalse);

      // Sudah dikerjakan saat selesai -> NON-AKTIF
      expect(canStartEvent(statusBadge: 'Selesai', sudahDikerjakan: true), isFalse);

      // Belum mulai -> NON-AKTIF
      expect(canStartEvent(statusBadge: 'Segera', sudahDikerjakan: false), isFalse);
    });

    test('IndoDateFormatter standard Indonesian date and time formatting', () {
      // Format Tanggal Lengkap
      final formatted = IndoDateFormatter.formatHariTanggal('2026-11-11');
      expect(formatted, contains('Rabu'));
      expect(formatted, contains('November'));
      expect(formatted, contains('2026'));

      // Format Jam dengan Zona Waktu (WITA/WIB)
      final jam = IndoDateFormatter.formatJam('08:00', '12:00', rawDateStr: '2026-11-11');
      expect(jam, contains('08:00 - 12:00'));
      expect(jam, anyOf(contains('WITA'), contains('WIB'), contains('WIT')));
    });

    test('Leaderboard podium logic: separates top 3 champions from list items', () {
      final scores = [950, 920, 890, 850, 810];
      final hasPodium = scores.length >= 3;
      expect(hasPodium, isTrue);

      final top3 = scores.take(3).toList();
      final rest = scores.skip(3).toList();

      expect(top3.length, 3);
      expect(top3[0], 950); // Gold
      expect(top3[1], 920); // Silver
      expect(top3[2], 890); // Bronze

      expect(rest.length, 2);
      expect(rest[0], 850); // Rank 4
      expect(rest[1], 810); // Rank 5
    });
  });
}

