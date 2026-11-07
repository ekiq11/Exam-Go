import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActivationResult Tests', () {
    test('ActivationResult.success stores message and targetExamId', () {
      final res = ActivationResult.success('Aktivasi Berhasil!', 'TONAS2026');
      expect(res.isSuccess, isTrue);
      expect(res.message, equals('Aktivasi Berhasil!'));
      expect(res.targetExamId, equals('TONAS2026'));
    });

    test('ActivationResult.failure stores failure message', () {
      final res = ActivationResult.failure('Token tidak valid');
      expect(res.isSuccess, isFalse);
      expect(res.message, equals('Token tidak valid'));
      expect(res.targetExamId, isNull);
    });
  });

  group('LicenseService Freemium & Quota Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LicenseService.instance.setMockFirestore(null);
    });

    test('canStudentTakeExam returns true for unlimited free exams', () async {
      final canTake = await LicenseService.instance.canStudentTakeExam();
      expect(canTake, isTrue);
    });

    test('getRemainingStudentAttempts returns 9999 for unlimited mode', () async {
      final remaining = await LicenseService.instance.getRemainingStudentAttempts();
      expect(remaining, equals(9999));
    });

    test('recordExamAttempt increments student exam count locally', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('license_student_exam_count'), isNull);

      await LicenseService.instance.recordExamAttempt();
      expect(prefs.getInt('license_student_exam_count'), equals(1));

      await LicenseService.instance.recordExamAttempt();
      expect(prefs.getInt('license_student_exam_count'), equals(2));
    });

    test('isStudentPremium reads local SharedPreferences correctly', () async {
      expect(await LicenseService.instance.isStudentPremium(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('license_student_is_premium', true);

      expect(await LicenseService.instance.isStudentPremium(), isTrue);
    });

    test('isTeacherPremium reads local SharedPreferences correctly', () async {
      expect(await LicenseService.instance.isTeacherPremium(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('license_teacher_is_premium', true);

      expect(await LicenseService.instance.isTeacherPremium(), isTrue);
    });

    test('saveActiveEvent and getActiveEventToken / getActiveEventId work correctly', () async {
      expect(await LicenseService.instance.getActiveEventToken(), isNull);
      expect(await LicenseService.instance.getActiveEventId(), isNull);

      await LicenseService.instance.saveActiveEvent(
        token: 'EVT-2026-TEST',
        eventId: 'PKT-SNBT-01',
      );

      expect(await LicenseService.instance.getActiveEventToken(), equals('EVT-2026-TEST'));
      expect(await LicenseService.instance.getActiveEventId(), equals('PKT-SNBT-01'));
    });

    test('canStudentTakeEventExam returns true for valid event package', () async {
      final canTake = await LicenseService.instance.canStudentTakeEventExam('PKT-SNBT-01');
      expect(canTake, isTrue);
    });

    test('Teacher Free 3x Trial Uploads work correctly', () async {
      // Default: guru gratis mendapatkan 3x kesempatan coba
      expect(await LicenseService.instance.getRemainingTeacherUploads(), equals(3));
      expect(await LicenseService.instance.canTeacherUploadExam(), isTrue);

      // Pakai 1x coba
      await LicenseService.instance.recordTeacherUploadAttempt();
      expect(await LicenseService.instance.getRemainingTeacherUploads(), equals(2));
      expect(await LicenseService.instance.canTeacherUploadExam(), isTrue);

      // Pakai 2x coba lagi (total 3x)
      await LicenseService.instance.recordTeacherUploadAttempt();
      await LicenseService.instance.recordTeacherUploadAttempt();
      expect(await LicenseService.instance.getRemainingTeacherUploads(), equals(0));
      expect(await LicenseService.instance.canTeacherUploadExam(), isFalse);

      // Setelah upgrade ke Premium, akses kembali tak terbatas
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('license_teacher_is_premium', true);
      expect(await LicenseService.instance.canTeacherUploadExam(), isTrue);
      expect(await LicenseService.instance.getRemainingTeacherUploads(), equals(9999));
    });

    test('getDeviceId returns non-empty string without throwing', () async {
      final deviceId = await LicenseService.instance.getDeviceId();
      expect(deviceId, isNotEmpty);
    });
  });
}

