import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/view/widgets/examgo_loading_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamGoLoadingDialog Tests', () {
    testWidgets('Renders loading dialog with initial title and message', (tester) async {
      ExamGoLoadingController? controller;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  controller = ExamGoLoadingDialog.show(
                    context,
                    title: 'Mencari Token Ujian...',
                    message: 'Menghubungkan ke server CBT & memverifikasi token...',
                  );
                },
                child: const Text('Show Loading'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Loading'));
      await tester.pump(); // Pump frame for dialog entrance

      expect(find.text('Mencari Token Ujian...'), findsOneWidget);
      expect(
        find.text('Menghubungkan ke server CBT & memverifikasi token...'),
        findsOneWidget,
      );
      expect(find.text('Verifikasi Enkripsi CBT ExamGO'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up
      controller?.dismiss();
      await tester.pumpAndSettle();
      expect(find.text('Mencari Token Ujian...'), findsNothing);
    });

    testWidgets('Updates title and message dynamically via controller', (tester) async {
      ExamGoLoadingController? controller;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  controller = ExamGoLoadingDialog.show(
                    context,
                    title: 'Status Awal',
                    message: 'Pesan Awal',
                  );
                },
                child: const Text('Show Loading'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Loading'));
      await tester.pump();

      expect(find.text('Status Awal'), findsOneWidget);
      expect(find.text('Pesan Awal'), findsOneWidget);

      // Dynamically update text
      controller?.update(
        title: 'Mengunduh Soal...',
        message: 'Mengenkripsi paket soal CBT secara lokal...',
      );
      await tester.pump();

      expect(find.text('Status Awal'), findsNothing);
      expect(find.text('Pesan Awal'), findsNothing);
      expect(find.text('Mengunduh Soal...'), findsOneWidget);
      expect(
        find.text('Mengenkripsi paket soal CBT secara lokal...'),
        findsOneWidget,
      );

      // Dismiss dialog
      controller?.dismiss();
      await tester.pumpAndSettle();
      expect(find.text('Mengunduh Soal...'), findsNothing);
    });

    testWidgets('Controller handles multiple dismiss calls safely', (tester) async {
      ExamGoLoadingController? controller;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  controller = ExamGoLoadingDialog.show(
                    context,
                    title: 'Memeriksa...',
                    message: 'Sedang memuat data...',
                  );
                },
                child: const Text('Show Loading'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Loading'));
      await tester.pump();

      expect(find.text('Memeriksa...'), findsOneWidget);

      // First dismiss
      controller?.dismiss();
      await tester.pumpAndSettle();
      expect(find.text('Memeriksa...'), findsNothing);

      // Second dismiss should be safe no-op
      expect(() => controller?.dismiss(), returnsNormally);
      expect(
        () => controller?.update(title: 'Ignored', message: 'Ignored'),
        returnsNormally,
      );
    });
  });
}
