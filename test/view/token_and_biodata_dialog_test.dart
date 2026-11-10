import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/home_screen.dart';
import 'package:examgo/view/pre_exam_checklist.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({
      'student_name': 'Ahmad Fauzi',
      'student_email': 'fauzi@example.com',
      'student_whatsapp': '081234567890',
    });
  });

  group('ManualTokenInputDialog Tests', () {
    testWidgets('renders gradient header, pills, and handles short & long event tokens on 320dp', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? submittedToken;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  submittedToken = await showDialog<String>(
                    context: context,
                    builder: (_) => const ManualTokenInputDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Buka dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verifikasi header banner & ikon badge
      expect(find.text('Input Token Ujian'), findsOneWidget);
      expect(find.text('Mendukung token 6-digit guru & tiket Event / Lynk.id'), findsOneWidget);

      // Verifikasi pil format token
      expect(find.text('6 Digit Guru'), findsOneWidget);
      expect(find.text('Tiket Event / Lynk'), findsOneWidget);

      // Masukkan token pendek 6-digit guru
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'abc123');
      await tester.pumpAndSettle();

      // Verifikasi otomatis kapital dan pill terdeteksi
      expect(find.text('ABC123'), findsOneWidget);
      expect(find.text('Token Ujian Guru (6 Digit)'), findsOneWidget);

      // Masukkan token event panjang (misal EVENT-2026-ABCD-1234)
      await tester.enterText(textField, 'event-2026-abcd-1234');
      await tester.pumpAndSettle();

      expect(find.text('EVENT-2026-ABCD-1234'), findsOneWidget);
      expect(find.text('Tiket Event Spesial'), findsOneWidget);

      // Submit token
      final submitBtn = find.text('Cari Ujian');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(submittedToken, 'EVENT-2026-ABCD-1234');
    });
  });

  group('StudentProfileDialog Tests', () {
    testWidgets('renders modern gradient header and validates biodata without overflow on 320dp', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool? submittedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  submittedResult = await showDialog<bool>(
                    context: context,
                    builder: (_) => const StudentProfileDialog(
                      initialName: '',
                      initialEmail: '',
                      initialWa: '',
                    ),
                  );
                },
                child: const Text('Open Profile Dialog'),
              ),
            ),
          ),
        ),
      );

      // Buka dialog
      await tester.tap(find.text('Open Profile Dialog'));
      await tester.pumpAndSettle();

      // Verifikasi header
      expect(find.text('Data Peserta Tryout'), findsOneWidget);
      expect(find.text('Lengkapi identitas untuk presensi ujian & sertifikat resmi'), findsOneWidget);

      // Verifikasi labels
      expect(find.text('Nama Lengkap Siswa:'), findsOneWidget);
      expect(find.text('No. WhatsApp Aktif:'), findsOneWidget);
      expect(find.text('Email Siswa (Aktif):'), findsOneWidget);

      // Klik simpan tanpa input -> validasi error muncul
      final saveBtn = find.text('Simpan & Lanjut');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Silakan masukkan Nama Lengkap Anda'), findsOneWidget);

      // Isi Nama dan WA
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Siti Rahma');
      await tester.enterText(textFields.at(1), '08987654321');
      await tester.enterText(textFields.at(2), 'rahma@example.com');
      await tester.pumpAndSettle();

      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(submittedResult, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('student_name'), 'Siti Rahma');
      expect(prefs.getString('student_whatsapp'), '08987654321');
    });
  });

  group('PreExamChecklistDialog Redesign Test', () {
    testWidgets('renders gradient header and DATA IDENTITAS PESERTA divider without overflow on 320dp', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PreExamChecklistDialog(examTitle: 'Tryout Akbar SNBT 2026'),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pumpAndSettle();

      expect(find.text('Persiapan & Regulasi Ujian'), findsOneWidget);
      expect(find.text('Sistem Anti-Kecurangan ExamGo Aktif'), findsOneWidget);
      expect(find.text('DATA IDENTITAS PESERTA'), findsOneWidget);
      expect(find.text('TATA TERTIB ANTI-KECURANGAN'), findsOneWidget);
    });
  });
}
