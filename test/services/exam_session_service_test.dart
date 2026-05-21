import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/services/exam_session_service.dart';

void main() {
  setUp(() {
    // Clear SharedPreferences before each test
    SharedPreferences.setMockInitialValues({});
  });

  group('ExamSessionService Tests', () {
    test('save() should persist session data correctly', () async {
      await ExamSessionService.instance.save(
        url: 'https://exam.com',
        title: 'Math Final',
        examId: 'exam123',
        studentName: 'Budi',
        studentNis: '12345',
        violations: 1,
      );

      final session = await ExamSessionService.instance.getActiveSession();
      expect(session, isNotNull);
      expect(session!.url, 'https://exam.com');
      expect(session.title, 'Math Final');
      expect(session.examId, 'exam123');
      expect(session.studentName, 'Budi');
      expect(session.studentNis, '12345');
      expect(session.violations, 1);
    });

    test('updateViolations() should update only violation count', () async {
      await ExamSessionService.instance.save(
        url: 'https://exam.com',
        title: 'Math Final',
        violations: 0,
      );

      await ExamSessionService.instance.updateViolations(3);

      final session = await ExamSessionService.instance.getActiveSession();
      expect(session!.violations, 3);
      expect(session.url, 'https://exam.com'); // Other data should remain
    });

    test('clear() should remove all session data', () async {
      await ExamSessionService.instance.save(
        url: 'https://exam.com',
        title: 'Math Final',
      );

      await ExamSessionService.instance.clear();

      final session = await ExamSessionService.instance.getActiveSession();
      expect(session, isNull);
    });

    test('getActiveSession() should return null if active flag is missing', () async {
      SharedPreferences.setMockInitialValues({
        'session_url': 'https://exam.com',
        // 'session_active': true is missing
      });

      final session = await ExamSessionService.instance.getActiveSession();
      expect(session, isNull);
    });

    test('elapsedSeconds should calculate time difference correctly', () async {
      await ExamSessionService.instance.save(
        url: 'https://exam.com',
        title: 'Math Final',
      );

      // Manipulate started_at to be 60 seconds ago
      final prefs = await SharedPreferences.getInstance();
      final sixtySecondsAgo = DateTime.now().subtract(const Duration(seconds: 60));
      await prefs.setString('session_started_at', sixtySecondsAgo.toIso8601String());

      final session = await ExamSessionService.instance.getActiveSession();
      expect(session, isNotNull);
      // Depending on execution speed, it might be 60 or 61 seconds.
      expect(session!.elapsedSeconds, inInclusiveRange(60, 62));
    });
  });
}
