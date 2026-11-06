import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/pre_exam_checklist.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({
      'student_name': 'Ahmad Fauzi',
      'student_nis': '123456',
    });
  });

  Widget buildTestWidget() {
    return const MaterialApp(
      home: Scaffold(
        body: PreExamChecklistDialog(examTitle: 'Tryout Akbar SNBT 2026'),
      ),
    );
  }

  testWidgets('PreExamChecklistDialog menampilkan tata tertib anti-curang a, b, c, d & checkbox persetujuan', (tester) async {
    // Ukuran layar cukup untuk render modal
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    // Biarkan async dart:io OS call (NetworkInterface) selesai di real clock
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // Verifikasi judul dialog & sesi
    expect(find.text('Persiapan & Regulasi Ujian'), findsOneWidget);
    expect(find.text('Tryout Akbar SNBT 2026'), findsOneWidget);

    // Verifikasi judul box regulasi
    expect(find.text('TATA TERTIB ANTI-KECURANGAN'), findsOneWidget);

    // Verifikasi poin-poin regulasi anti-curang a, b, c, d
    expect(find.text('Dilarang Berpindah Aplikasi / Split Screen'), findsOneWidget);
    expect(find.text('Larangan Screenshot & Rekam Layar'), findsOneWidget);
    expect(find.text('Pelaporan Pelanggaran Real-Time'), findsOneWidget);
    expect(find.text('Batas Toleransi Maksimal 3 Kali'), findsOneWidget);

    // Verifikasi Checkbox persetujuan
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);
    expect(tester.widget<Checkbox>(checkboxFinder).value, false);

    // Klik tombol submit saat checkbox belum dicentang -> tidak boleh submit
    final submitFinder = find.text('Saya Paham & Mulai');
    await tester.ensureVisible(submitFinder);
    await tester.pumpAndSettle();
    await tester.tap(submitFinder);
    await tester.pump();
    expect(find.text('Harap baca dan centang persetujuan regulasi anti-curang'), findsOneWidget);

    // Tap checkbox untuk menyetujui
    await tester.ensureVisible(checkboxFinder);
    await tester.pumpAndSettle();
    await tester.tap(checkboxFinder);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkboxFinder).value, true);

    // Verifikasi tombol submit masih ada dan siap
    expect(submitFinder, findsOneWidget);
  });
}
