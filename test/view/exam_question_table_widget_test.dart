import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/view/student/widgets/exam_question_table_widget.dart';

void main() {
  group('ExamQuestionTableWidget Tests', () {
    testWidgets('Tabel kosong merender SizedBox.shrink', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExamQuestionTableWidget(tabelStr: ''),
          ),
        ),
      );

      expect(find.byType(Table), findsNothing);
      expect(find.text('BACAAN'), findsNothing);
    });

    testWidgets('Teks Bacaan (Bacaan/Paragraf) dirender sebagai Card Editorial Vertikal, BUKAN Table', (tester) async {
      const passageStr =
          '1|||Bacaan===2|||Laju pertumbuhan penduduk yang tinggi memicu masalah sosial.===3|||Pemerintah menjalankan program KB guna mengendalikan angka kelahiran.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExamQuestionTableWidget(tabelStr: passageStr),
            ),
          ),
        ),
      );

      // Verifikasi: Tidak ada widget Table horizontal
      expect(find.byType(Table), findsNothing);

      // Verifikasi: Muncul ikon buku / bacaan
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);

      // Verifikasi: Header judul bacaan
      expect(find.text('BACAAN'), findsOneWidget);
    });

    testWidgets('Teks Bacaan Berlabel (Paragraph 1 & 2) dirender dengan label badge', (tester) async {
      const labeledPassage =
          '1|||Paragraph|||Text===2|||Paragraph 1|||Over this decade, fresh water demand increases.===3|||Paragraph 2|||Meanwhile, desalination plants expand.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExamQuestionTableWidget(tabelStr: labeledPassage),
            ),
          ),
        ),
      );

      expect(find.byType(Table), findsNothing);
      expect(find.text('Paragraph 1'), findsOneWidget);
      expect(find.text('Paragraph 2'), findsOneWidget);
    });

    testWidgets('Tabel Data Statistik/Angka tetap dirender sebagai Table Widget', (tester) async {
      const dataTableStr =
          '1|||Banyak Kucing|||Kelas A|||Kelas B===2|||0|||4|||2===3|||1|||8|||12';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExamQuestionTableWidget(tabelStr: dataTableStr),
            ),
          ),
        ),
      );

      // Verifikasi: Widget Table dirender untuk data angka
      expect(find.byType(Table), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
    });
  });
}
