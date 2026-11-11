import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/teacher_monitoring_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'teacher_pin_hash': 'testhash',
      'teacher_exam_history': [
        'EXAM-101|Matematika Wajib|$now|http://exam.url',
      ],
    });
  });

  group('TeacherMonitoringListScreen Modes & Anti-Overlap Tests', () {
    testWidgets('Riwayat Ujian & Token Saya (isLiveMode: false) renders tokens without Pantau Live button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TeacherMonitoringListScreen(isLiveMode: false),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan AppBar menampilkan judul Riwayat Ujian & Token Saya dan rata kiri
      expect(find.text('Riwayat Ujian & Token Saya'), findsOneWidget);
      expect(find.text('Katalog & Manajemen Token'), findsOneWidget);
      expect(find.text('1 Sesi'), findsOneWidget);

      final sliverAppBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(sliverAppBar.centerTitle, isFalse);

      // Memastikan kartu token menampilkan aksi Detail & QR, Bagikan, dan Hapus
      expect(find.text('Detail & QR'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      // Memastikan TIDAK ADA tombol Pantau Live pada Riwayat Token
      expect(find.text('Pantau Live'), findsNothing);
    });

    testWidgets('Live Monitoring Peserta (isLiveMode: true) renders live proctoring with Pantau Live button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TeacherMonitoringListScreen(isLiveMode: true),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan AppBar menampilkan judul Live Monitoring Peserta
      expect(find.text('Live Monitoring Peserta'), findsOneWidget);
      expect(find.text('Radar Pengawasan Real-Time'), findsOneWidget);
      expect(find.text('1 Sesi'), findsOneWidget);

      // Memastikan ada tombol Pantau Live pada mode Live Monitoring
      expect(find.text('Pantau Live'), findsOneWidget);
      expect(find.text('Detail & QR'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
    });
  });
}
