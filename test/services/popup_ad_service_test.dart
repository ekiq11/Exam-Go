import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/services/popup_ad_service.dart';

void main() {
  group('PopupAdItem Tests', () {
    test('fromMap parses valid active ad with 1:1 image and Lynk.id CTA', () {
      final map = {
        'imageUrl': 'https://images.lynk.id/banner1.jpg',
        'ctaUrl': 'https://lynk.id/examgo/siswa-premium',
        'title': 'Promo Siswa 2026',
        'isActive': true,
      };

      final ad = PopupAdItem.fromMap(map);
      expect(ad.imageUrl, 'https://images.lynk.id/banner1.jpg');
      expect(ad.ctaUrl, 'https://lynk.id/examgo/siswa-premium');
      expect(ad.title, 'Promo Siswa 2026');
      expect(ad.isActive, isTrue);
      expect(ad.isValid, isTrue);
    });

    test('fromMap handles null and missing fields gracefully', () {
      final ad = PopupAdItem.fromMap(null);
      expect(ad.imageUrl, '');
      expect(ad.ctaUrl, 'https://lynk.id');
      expect(ad.isActive, isFalse);
      expect(ad.isValid, isFalse);
    });

    test('isValid returns false when image is empty even if active is true', () {
      final ad = PopupAdItem.fromMap({
        'imageUrl': '',
        'ctaUrl': 'https://lynk.id',
        'isActive': true,
      });
      expect(ad.isValid, isFalse);
    });

    test('fromMap parses boolean strings from GAS/Sheets correctly', () {
      final ad = PopupAdItem.fromMap({
        'imageUrl': 'https://example.com/ad.png',
        'isActive': 'true',
      });
      expect(ad.isActive, isTrue);
      expect(ad.isValid, isTrue);
    });
  });

  group('PopupAdsConfig Segmentation Logic Tests', () {
    test('correctly segments student, teacher, and event ads', () {
      final configMap = {
        'student': {
          'imageUrl': 'https://example.com/student.jpg',
          'ctaUrl': 'https://lynk.id/examgo/siswa',
          'title': 'Iklan Siswa',
          'isActive': true,
        },
        'teacher': {
          'imageUrl': 'https://example.com/teacher.jpg',
          'ctaUrl': 'https://lynk.id/examgo/guru',
          'title': 'Iklan Guru',
          'isActive': true,
        },
        'event': {
          'imageUrl': 'https://example.com/event.jpg',
          'ctaUrl': 'https://lynk.id/examgo/event',
          'title': 'Iklan Event',
          'isActive': false,
        },
      };

      final config = PopupAdsConfig.fromMap(configMap);
      expect(config.student.isValid, isTrue);
      expect(config.student.title, 'Iklan Siswa');
      expect(config.teacher.isValid, isTrue);
      expect(config.teacher.title, 'Iklan Guru');
      expect(config.event.isValid, isFalse); // Inactive
    });

    test('ad display priority rule: free vs premium vs event', () {
      final config = PopupAdsConfig(
        student: const PopupAdItem(
          imageUrl: 'https://example.com/student.jpg',
          ctaUrl: 'https://lynk.id/siswa',
          title: 'Siswa',
          isActive: true,
        ),
        teacher: const PopupAdItem(
          imageUrl: 'https://example.com/teacher.jpg',
          ctaUrl: 'https://lynk.id/guru',
          title: 'Guru',
          isActive: true,
        ),
        event: const PopupAdItem(
          imageUrl: '',
          ctaUrl: 'https://lynk.id/event',
          title: 'Event',
          isActive: false,
        ),
      );

      // Helper function that mirrors HomeScreen ad logic:
      PopupAdItem? resolveHomeAd({required bool isPremium}) {
        if (config.event.isValid) return config.event;
        if (!isPremium && config.student.isValid) return config.student;
        return null;
      }

      // 1. Siswa Free: Tampil iklan siswa
      expect(resolveHomeAd(isPremium: false), isNotNull);
      expect(resolveHomeAd(isPremium: false)!.title, 'Siswa');

      // 2. Siswa Premium: TIDAK tampil iklan jika tidak ada event aktif
      expect(resolveHomeAd(isPremium: true), isNull);

      // 3. Jika Event Aktif: Tampil untuk SISWA PREMIUM juga
      final configWithEvent = PopupAdsConfig(
        student: config.student,
        teacher: config.teacher,
        event: const PopupAdItem(
          imageUrl: 'https://example.com/event.jpg',
          ctaUrl: 'https://lynk.id/event',
          title: 'Event Akbar',
          isActive: true,
        ),
      );

      PopupAdItem? resolveHomeAdWithEvent({required bool isPremium}) {
        if (configWithEvent.event.isValid) return configWithEvent.event;
        if (!isPremium && configWithEvent.student.isValid) return configWithEvent.student;
        return null;
      }

      expect(resolveHomeAdWithEvent(isPremium: true), isNotNull);
      expect(resolveHomeAdWithEvent(isPremium: true)!.title, 'Event Akbar');
      expect(resolveHomeAdWithEvent(isPremium: false)!.title, 'Event Akbar');
    });
  });
}

