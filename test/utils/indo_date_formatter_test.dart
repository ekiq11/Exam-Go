import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/utils/indo_date_formatter.dart';

void main() {
  group('IndoDateFormatter Timezone & Formatting Tests', () {
    test('localZoneSuffix returns valid Indonesian timezone or GMT offset', () {
      final suffix = IndoDateFormatter.localZoneSuffix;
      expect(
        suffix == 'WIB' || suffix == 'WITA' || suffix == 'WIT' || suffix.startsWith('GMT'),
        isTrue,
      );
    });

    test('detectTimeZone detects explicit timezone from text or defaults to localZoneSuffix', () {
      expect(IndoDateFormatter.detectTimeZone('Wed Sep 09 2026 GMT+0700 (WIB)'), 'WIB');
      expect(IndoDateFormatter.detectTimeZone('Wed Sep 09 2026 GMT+0800 (WITA)'), 'WITA');
      expect(IndoDateFormatter.detectTimeZone('Wed Sep 09 2026 GMT+0900 (WIT)'), 'WIT');
      expect(IndoDateFormatter.detectTimeZone('JAKARTA'), 'WIB');
      expect(IndoDateFormatter.detectTimeZone('MAKASSAR'), 'WITA');
      expect(IndoDateFormatter.detectTimeZone('JAYAPURA'), 'WIT');
      
      // Null or empty string defaults to localZoneSuffix
      expect(IndoDateFormatter.detectTimeZone(null), IndoDateFormatter.localZoneSuffix);
      expect(IndoDateFormatter.detectTimeZone(''), IndoDateFormatter.localZoneSuffix);
    });

    test('formatJam includes detected or local timezone suffix', () {
      final jamStr = IndoDateFormatter.formatJam('08:00', '10:00', rawDateStr: 'JAKARTA');
      expect(jamStr, '08:00 - 10:00 WIB');

      final jamLocal = IndoDateFormatter.formatJam('08:00', '10:00');
      expect(jamLocal, contains(IndoDateFormatter.localZoneSuffix));
    });

    test('formatJadwalRingkas formats properly with timezone', () {
      final ringkas = IndoDateFormatter.formatJadwalRingkas(
        '2026-09-09',
        '08:00',
        '10:00',
      );
      expect(ringkas, contains('Sep 2026'));
      expect(ringkas, contains('08:00-10:00'));
      expect(ringkas, contains(IndoDateFormatter.localZoneSuffix));
    });
  });
}

