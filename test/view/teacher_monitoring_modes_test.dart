import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/teacher_monitoring_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'teacher_pin_hash': 'testhash',
      'teacher_exam_history': [
        'EXAM-101|Matematika Wajib|$now|http://exam.url',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('teacher_exam_history', [
      'EXAM-101|Matematika Wajib|$now|http://exam.url',
    ]);
  });

  group('TeacherMonitoringListScreen Modes & Anti-Overlap Tests', () {
    testWidgets('Riwayat Ujian & Token Saya (isLiveMode: false) renders tokens without Pantau Live button', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: TeacherMonitoringListScreen(isLiveMode: false),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan AppBar menampilkan judul Riwayat & Token Ujian dan rata kiri
      expect(find.text('Riwayat & Token Ujian'), findsOneWidget);
      expect(find.text('Katalog & Manajemen Token'), findsOneWidget);
      expect(find.text('1 Sesi'), findsOneWidget);

      final sliverAppBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(sliverAppBar.centerTitle, isFalse);

      // Memastikan kartu token menampilkan aksi Detail, Bagikan, dan Hapus
      expect(find.text('Detail'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      // Memastikan TIDAK ADA tombol Monitor pada Riwayat Token
      expect(find.text('Monitor'), findsNothing);
    });

    testWidgets('Live Monitoring (isLiveMode: true) renders live proctoring with Monitor button', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: TeacherMonitoringListScreen(isLiveMode: true),
        ),
      );
      await tester.pumpAndSettle();

      // Memastikan AppBar menampilkan judul Live Monitoring
      expect(find.text('Live Monitoring'), findsOneWidget);
      expect(find.text('Radar Pengawasan Real-Time'), findsOneWidget);
      expect(find.text('1 Sesi'), findsOneWidget);

      // Memastikan ada tombol Monitor pada mode Live Monitoring
      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Detail'), findsOneWidget);
      expect(find.text('Bagikan'), findsOneWidget);
    });
  });
}
