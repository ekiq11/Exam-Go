import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/view/student/widgets/exam_time_lock_dialog.dart';

void main() {
  testWidgets('showExamTimeLockDialog displays title, remaining time and closes on button tap', (tester) async {
    final endTime = DateTime.now().add(const Duration(minutes: 30));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showExamTimeLockDialog(
                  context,
                  endTime: endTime,
                  examTitle: 'Simulasi USBN Biologi',
                );
              },
              child: const Text('Open Lock Dialog'),
            ),
          ),
        ),
      ),
    );

    // Tap button to show dialog
    await tester.tap(find.text('Open Lock Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog contents
    expect(find.text('Waktu Ujian Belum Berakhir'), findsOneWidget);
    expect(find.textContaining('Pembahasan & Kunci Jawaban baru dapat diakses'), findsOneWidget);
    expect(find.textContaining('Menit Lagi'), findsOneWidget);
    expect(find.text('Mengerti'), findsOneWidget);

    // Tap Mengerti button
    await tester.tap(find.text('Mengerti'));
    await tester.pumpAndSettle();

    // Dialog is dismissed
    expect(find.text('Waktu Ujian Belum Berakhir'), findsNothing);
  });
}

