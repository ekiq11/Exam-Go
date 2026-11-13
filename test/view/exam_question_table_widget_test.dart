import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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

    testWidgets('Teks Bacaan (Bacaan/Paragraf) dirender sebagai Paragraf Mengalir Vertikal, BUKAN Table', (tester) async {
      const passageStr =
          '1|||Bacaan===2|||Laju pertumbuhan penduduk yang tinggi memicu masalah sosial.===3|||Pemerintah menjalankan program KB guna mengendalikan angka kelahiran.';

      expect(ExamQuestionTableWidget.isReadingPassage(passageStr), isTrue);

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

      // Verifikasi: HtmlWidget dirender untuk paragraf bacaan
      expect(find.byType(HtmlWidget), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('Laju pertumbuhan penduduk')),
        findsOneWidget,
      );
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

    test('isReadingPassage mengenali subtest Pemahaman Bacaan dan Menulis secara otomatis', () {
      const passageStr = '1|||Kalimat===2|||Dari buku-buku dan tulisan yang beredar...';
      expect(
        ExamQuestionTableWidget.isReadingPassage(
          passageStr,
          subtestJudul: 'Pemahaman Bacaan dan Menulis',
        ),
        isTrue,
      );
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

    testWidgets('Tabel HTML dari WebGAS DOCX parser dirender sebagai Table Widget', (tester) async {
      const htmlTableStr =
          '<div class="overflow-x-auto my-3"><table class="min-w-full text-xs text-left">'
          '<tr class="bg-slate-800 text-slate-200 font-bold">'
          '<th class="px-3 py-2">No</th><th class="px-3 py-2">Kandungan</th><th class="px-3 py-2">Kadar</th>'
          '</tr>'
          '<tr>'
          '<td class="px-3 py-2">1</td><td class="px-3 py-2">Protein</td><td class="px-3 py-2">25%</td>'
          '</tr>'
          '<tr>'
          '<td class="px-3 py-2">2</td><td class="px-3 py-2">Lemak</td><td class="px-3 py-2">10%</td>'
          '</tr>'
          '</table></div>';

      final rows = ExamQuestionTableWidget.parseTableRows(htmlTableStr);
      expect(rows.length, equals(3));
      expect(rows[0], equals(['No', 'Kandungan', 'Kadar']));
      expect(rows[1], equals(['1', 'Protein', '25%']));
      expect(rows[2], equals(['2', 'Lemak', '10%']));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExamQuestionTableWidget(tabelStr: htmlTableStr),
            ),
          ),
        ),
      );

      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('Tabel Markdown (| ... |) dirender dengan benar', (tester) async {
      const markdownTableStr =
          '| Hari | Jam | Aktivitas |\n'
          '| --- | --- | --- |\n'
          '| Senin | 08.00 | Upacara |\n'
          '| Selasa | 09.00 | Praktikum |';

      final rows = ExamQuestionTableWidget.parseTableRows(markdownTableStr);
      expect(rows.length, equals(3));
      expect(rows[0], equals(['Hari', 'Jam', 'Aktivitas']));
      expect(rows[1], equals(['Senin', '08.00', 'Upacara']));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExamQuestionTableWidget(tabelStr: markdownTableStr),
            ),
          ),
        ),
      );

      expect(find.byType(Table), findsOneWidget);
    });
  });
}
