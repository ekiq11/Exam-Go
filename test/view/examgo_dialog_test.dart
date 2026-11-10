import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/widgets/examgo_dialog.dart';
import 'package:examgo/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'license_student_is_premium': true,
      'license_teacher_is_premium': true,
      'student_name': 'Ahmad Siswa',
      'teacher_pin_hash': 'testhash',
      'teacher_exam_history': ['EXAM-101|Matematika Wajib|1700000000000|http://exam.url'],
    });
  });

  group('ExamGoDialog Tests', () {
    testWidgets('Renders confirm dialog with custom title, message, and returns true on confirm', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ExamGoDialog.confirm(
                    context,
                    title: 'Konfirmasi Tes',
                    message: 'Apakah Anda yakin ingin melanjutkan?',
                    confirmText: 'Ya, Lanjutkan',
                    cancelText: 'Batal',
                  );
                },
                child: const Text('Buka Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi Tes'), findsOneWidget);
      expect(find.text('Apakah Anda yakin ingin melanjutkan?'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      expect(find.text('Ya, Lanjutkan'), findsOneWidget);

      await tester.tap(find.text('Ya, Lanjutkan'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('Renders danger dialog with destructive button styling and returns false on cancel', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ExamGoDialog.danger(
                    context,
                    title: 'Hapus Sesi?',
                    message: 'Data sesi akan dihapus permanen.',
                    confirmText: 'Hapus Sesi',
                    cancelText: 'Kembali',
                  );
                },
                child: const Text('Hapus'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      expect(find.text('Hapus Sesi?'), findsOneWidget);
      expect(find.text('Hapus Sesi'), findsOneWidget);

      await tester.tap(find.text('Kembali'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('Apple Guideline 5.1.1 Account & Data Deletion Tests', () {
    test('clearAllUserAccountData clears all preferences and licenses thoroughly', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('license_student_is_premium'), isTrue);
      expect(prefs.getString('student_name'), equals('Ahmad Siswa'));
      expect(prefs.getStringList('teacher_exam_history'), isNotEmpty);

      await LicenseService.instance.clearAllUserAccountData();

      expect(prefs.getBool('license_student_is_premium'), isNull);
      expect(prefs.getString('student_name'), isNull);
      expect(prefs.getStringList('teacher_exam_history'), isNull);
      expect(prefs.getString('teacher_pin_hash'), isNull);
    });
  });
}

